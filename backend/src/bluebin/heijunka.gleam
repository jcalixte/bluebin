import bluebin/calendar
import bluebin/demand.{type Demand}
import bluebin/wire
import bluebin/wire_json
import gleam/bool
import gleam/dynamic/decode
import gleam/float
import gleam/int
import gleam/json
import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/order
import gleam/result
import gleam/string
import sqlight

/// A Piece waiting in the Backlog. `arrived` is its global insertion order.
pub type Waiting {
  Waiting(
    id: String,
    reference: String,
    demand: String,
    arrived: Int,
    urgent: Option(Int),
  )
}

pub type Placed {
  Placed(piece: Waiting, demand: Demand, slot_hours: Float)
}

pub type Backlog {
  Backlog(sequence: List(Placed), demands: List(Demand))
}

/// What a manual reorder costs one Demand: its next Piece leaves `places`
/// later (negative: earlier), which is `hours` of Working Time at the Value
/// Line Takt Time, and `takt_gap` Pieces on its Takt Gap.
pub type Effect {
  Effect(demand: Demand, places: Int, hours: Float, takt_gap: Float)
}

const waiting_sql =
  "
select p.id, p.reference, p.demand_id, p.rowid, p.urgent
from piece p
join demand d on d.id = p.demand_id
where p.state = 'backlog' and p.parent_id is null and d.state = 'active'
"

pub fn load(connection: sqlight.Connection) -> Result(Backlog, sqlight.Error) {
  use demands <- result.try(demand.list_active(connection))
  use waiting <- result.try(sqlight.query(
    waiting_sql,
    on: connection,
    with: [],
    expecting: waiting_decoder(),
  ))
  Ok(Backlog(sequence: sequence(waiting, demands), demands:))
}

fn waiting_decoder() -> decode.Decoder(Waiting) {
  use id <- decode.field(0, decode.string)
  use reference <- decode.field(1, decode.string)
  use demand <- decode.field(2, decode.string)
  use arrived <- decode.field(3, decode.int)
  use urgent <- decode.field(4, decode.optional(decode.int))
  decode.success(Waiting(id:, reference:, demand:, arrived:, urgent:))
}

/// The Heijunka Sequence (F23): the Pieces made urgent by hand first, in the
/// order they were made urgent, then the earliest slot, the earliest due date,
/// first-in first-out. A Demand spreads the Pieces it has left in the Backlog
/// evenly over the Working Time it has left: the slot of its k-th Piece is
/// (k - 0.5) of that interval from now, so a late Demand gets more slots, still
/// mixed with the others.
pub fn sequence(waiting: List(Waiting), demands: List(Demand)) -> List(Placed) {
  demands
  |> list.flat_map(fn(demand) {
    let pieces =
      waiting
      |> list.filter(fn(piece) { piece.demand == demand.id })
      |> list.sort(fn(a, b) { int.compare(a.arrived, b.arrived) })
    let interval = hours_left(demand) /. int.to_float(list.length(pieces))
    list.index_map(pieces, fn(piece, index) {
      let slot_hours = { int.to_float(index) +. 0.5 } *. interval
      Placed(piece:, demand:, slot_hours:)
    })
  })
  |> list.sort(compare)
}

/// Working Time from today to the due date, today included. A Demand past its
/// due date keeps one day, so its Pieces all go in the first day.
fn hours_left(demand: Demand) -> Float {
  let days = demand.working_days_total - demand.working_days_elapsed + 1
  int.to_float(int.max(days, 1)) *. demand.hours_per_day
}

fn compare(a: Placed, b: Placed) -> order.Order {
  case a.piece.urgent, b.piece.urgent {
    Some(_), None -> order.Lt
    None, Some(_) -> order.Gt
    Some(first), Some(second) -> int.compare(first, second)
    None, None ->
      float.compare(a.slot_hours, b.slot_hours)
      |> order.break_tie(string.compare(a.demand.due_on, b.demand.due_on))
  }
  |> order.break_tie(int.compare(a.piece.arrived, b.piece.arrived))
}

/// Inside one Demand Pieces keep first-in first-out, so only the oldest Piece
/// of a Demand not yet urgent can be made urgent.
pub fn next_of_its_demand(sequence: List(Placed), piece: Placed) -> Bool {
  !list.any(sequence, fn(other) {
    other.piece.demand == piece.piece.demand
    && other.piece.urgent == None
    && other.piece.arrived < piece.piece.arrived
  })
}

/// The sequence once `piece_id` is made urgent: it goes behind the Pieces
/// already urgent, ahead of every other one.
pub fn make_urgent(sequence: List(Placed), piece_id: String) -> List(Placed) {
  let #(urgent, rest) =
    list.split_while(sequence, fn(placed) { placed.piece.urgent != None })
  let #(moved, others) =
    list.partition(rest, fn(placed) { placed.piece.id == piece_id })
  list.flatten([urgent, moved, others])
}

/// The Pieces a Team Member can make urgent and that would really move.
pub fn can_be_urgent(sequence: List(Placed)) -> List(String) {
  sequence
  |> list.filter(fn(placed) {
    placed.piece.urgent == None
    && next_of_its_demand(sequence, placed)
    && make_urgent(sequence, placed.piece.id) != sequence
  })
  |> list.map(fn(placed) { placed.piece.id })
}

pub fn effects(
  before: List(Placed),
  after: List(Placed),
  line_takt_hours: Float,
) -> List(Effect) {
  before
  |> list.map(fn(placed) { placed.demand })
  |> list.unique
  |> list.filter_map(fn(demand) {
    let places = next_place(after, demand.id) - next_place(before, demand.id)
    use <- bool.guard(when: places == 0, return: Error(Nil))
    let hours = int.to_float(places) *. line_takt_hours
    let takt_gap = case demand.takt_time_hours(demand) {
      0.0 -> 0.0
      takt -> 0.0 -. hours /. takt
    }
    Ok(Effect(
      demand:,
      places:,
      hours: demand.round_to_tenth(hours),
      takt_gap: demand.round_to_tenth(takt_gap),
    ))
  })
}

fn next_place(sequence: List(Placed), demand_id: String) -> Int {
  sequence
  |> list.take_while(fn(placed) { placed.demand.id != demand_id })
  |> list.length
}

pub fn effects_json(effects: List(Effect)) -> json.Json {
  json.array(effects, fn(effect) {
    wire.ReorderEffect(
      demand: effect.demand.id,
      label: effect.demand.label,
      places: effect.places,
      hours: effect.hours,
      takt_gap: effect.takt_gap,
    )
    |> wire_json.reorder_effect
  })
}

/// One Demand on one day: the Pieces the Takt Time plans to leave the Backlog
/// and the Pieces that really left it (F26).
pub type MixCell {
  MixCell(day: String, planned: Float, real: Int)
}

pub type MixRow {
  MixRow(demand: Demand, cells: List(MixCell))
}

/// A Piece leaves the Backlog on the only pull that has no Blue Bin upstream.
const mix_sql = "
with recursive
  days(day) as (
    select date('now')
    union all
    select date(day, '-1 day') from days where day > date('now', '-13 day')
  ),
  shown(day) as (
    select day from days where " <> calendar.working_day_sql <> "
    order by day desc limit ?1
  )
select
  s.day,
  d.id,
  s.day between d.started_on and d.due_on,
  (select count(*) from flow_event e
     join piece p on p.id = e.piece_id
    where e.kind = 'piece_pulled'
      and json_extract(e.payload, '$.from') is null
      and p.demand_id = d.id
      and date(e.at) = s.day)
from shown s, demand d
where d.state = 'active'
order by s.day
"

const mix_days = 5

pub fn product_mix(
  connection: sqlight.Connection,
  demands: List(Demand),
) -> Result(List(MixRow), sqlight.Error) {
  let decoder = {
    use day <- decode.field(0, decode.string)
    use demand <- decode.field(1, decode.string)
    use active <- decode.field(2, decode.int)
    use real <- decode.field(3, decode.int)
    decode.success(#(day, demand, active == 1, real))
  }
  use rows <- result.try(sqlight.query(
    mix_sql,
    on: connection,
    with: [sqlight.int(mix_days)],
    expecting: decoder,
  ))
  Ok(
    list.map(demands, fn(demand) {
      let per_day = case demand.takt_time_hours(demand) {
        0.0 -> 0.0
        takt -> demand.hours_per_day /. takt
      }
      MixRow(
        demand:,
        cells: rows
          |> list.filter(fn(row) { row.1 == demand.id })
          |> list.map(fn(row) {
            let #(day, _, active, real) = row
            MixCell(
              day:,
              planned: case active {
                True -> demand.round_to_tenth(per_day)
                False -> 0.0
              },
              real:,
            )
          }),
      )
    }),
  )
}

/// F26 target: at most one Piece of gap for each Demand, each day.
pub fn on_plan(cell: MixCell) -> Bool {
  float.absolute_value(int.to_float(cell.real) -. cell.planned) <=. 1.0
}

/// The days shown, added up. A plan under 1 Piece a day keeps each day on
/// plan with no Piece at all, so only the sum shows a Demand left behind.
pub fn total(cells: List(MixCell)) -> MixCell {
  MixCell(
    day: "",
    planned: demand.round_to_tenth(
      list.fold(cells, 0.0, fn(sum, cell) { sum +. cell.planned }),
    ),
    real: list.fold(cells, 0, fn(sum, cell) { sum + cell.real }),
  )
}

pub fn to_json(backlog: Backlog, mix: List(MixRow)) -> json.Json {
  let urgent_ok = can_be_urgent(backlog.sequence)
  wire.Backlog(
    takt_time_hours: demand.line_takt_hours(backlog.demands),
    sequence: list.map(backlog.sequence, fn(placed) {
      wire.BacklogPiece(
        id: placed.piece.id,
        reference: placed.piece.reference,
        demand: placed.demand.id,
        demand_label: placed.demand.label,
        client: placed.demand.client,
        due_on: placed.demand.due_on,
        slot_hours: demand.round_to_tenth(placed.slot_hours),
        urgent: placed.piece.urgent != None,
        can_be_urgent: list.contains(urgent_ok, placed.piece.id),
      )
    }),
    mix: list.map(mix, fn(row) {
      let sum = total(row.cells)
      wire.MixRow(
        demand: row.demand.id,
        label: row.demand.label,
        cells: list.map(row.cells, fn(cell) {
          wire.MixCell(
            day: cell.day,
            planned: cell.planned,
            real: cell.real,
            on_plan: on_plan(cell),
          )
        }),
        total: wire.MixTotal(
          planned: sum.planned,
          real: sum.real,
          on_plan: on_plan(sum),
        ),
      )
    }),
  )
  |> wire_json.backlog
}
