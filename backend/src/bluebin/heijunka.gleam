import bluebin/calendar
import bluebin/demand.{type Demand}
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

/// A Piece waiting in the Backlog. `ordinal` is its place inside its Demand,
/// first-in first-out from 1; `arrived` is its global insertion order.
pub type Waiting {
  Waiting(
    id: String,
    reference: String,
    demand: String,
    arrived: Int,
    ordinal: Int,
    working_days_before_start: Int,
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

/// Working days count from the start of the first active Demand, so the slots
/// of Demands that started on different days compare.
const waiting_sql = "
with recursive
  span(first_day, last_day) as (
    select min(started_on), max(started_on) from demand where state = 'active'
  ),
  days(day) as (
    select first_day from span where first_day is not null
    union all
    select date(day, '+1 day') from days, span where day < last_day
  ),
  working_day(day) as (
    select day from days where " <> calendar.working_day_sql <> "
  )
select
  p.id,
  p.reference,
  p.demand_id,
  p.rowid,
  (select count(*) from piece o
    where o.demand_id = p.demand_id and o.parent_id is null
      and o.rowid <= p.rowid),
  (select count(*) from working_day w where w.day < d.started_on),
  p.urgent
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
  use ordinal <- decode.field(4, decode.int)
  use working_days_before_start <- decode.field(5, decode.int)
  use urgent <- decode.field(6, decode.optional(decode.int))
  decode.success(Waiting(
    id:,
    reference:,
    demand:,
    arrived:,
    ordinal:,
    working_days_before_start:,
    urgent:,
  ))
}

/// The Heijunka Sequence (F23): the Pieces made urgent by hand first, in the
/// order they were made urgent, then the earliest slot, the earliest due date,
/// first-in first-out. The slot of the n-th Piece of a Demand is n Takt Times
/// after the Demand started.
pub fn sequence(waiting: List(Waiting), demands: List(Demand)) -> List(Placed) {
  waiting
  |> list.filter_map(fn(piece) {
    use demand <- result.map(
      list.find(demands, fn(demand) { demand.id == piece.demand }),
    )
    let slot_hours =
      int.to_float(piece.working_days_before_start)
      *. demand.hours_per_day
      +. int.to_float(piece.ordinal)
      *. demand.takt_time_hours(demand)
    Placed(piece:, demand:, slot_hours:)
  })
  |> list.sort(compare)
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
    json.object([
      #("demand", json.string(effect.demand.id)),
      #("label", json.string(effect.demand.label)),
      #("places", json.int(effect.places)),
      #("hours", json.float(effect.hours)),
      #("taktGap", json.float(effect.takt_gap)),
    ])
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

pub const mix_days = 5

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

pub fn to_json(backlog: Backlog, mix: List(MixRow)) -> json.Json {
  let urgent_ok = can_be_urgent(backlog.sequence)
  json.object([
    #("taktTimeHours", json.float(demand.line_takt_hours(backlog.demands))),
    #(
      "sequence",
      json.array(backlog.sequence, fn(placed) {
        json.object([
          #("id", json.string(placed.piece.id)),
          #("reference", json.string(placed.piece.reference)),
          #("demand", json.string(placed.demand.id)),
          #("demandLabel", json.string(placed.demand.label)),
          #("client", json.string(placed.demand.client)),
          #("dueOn", json.string(placed.demand.due_on)),
          #("slotHours", json.float(demand.round_to_tenth(placed.slot_hours))),
          #("urgent", json.bool(placed.piece.urgent != None)),
          #("canBeUrgent", json.bool(list.contains(urgent_ok, placed.piece.id))),
        ])
      }),
    ),
    #(
      "mix",
      json.array(mix, fn(row) {
        json.object([
          #("demand", json.string(row.demand.id)),
          #("label", json.string(row.demand.label)),
          #(
            "cells",
            json.array(row.cells, fn(cell) {
              json.object([
                #("day", json.string(cell.day)),
                #("planned", json.float(cell.planned)),
                #("real", json.int(cell.real)),
                #("onPlan", json.bool(on_plan(cell))),
              ])
            }),
          ),
        ])
      }),
    ),
  ])
}
