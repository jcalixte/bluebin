import bluebin/calendar.{type Calendar}
import bluebin/db
import bluebin/wire
import bluebin/wire_json
import gleam/dict.{type Dict}
import gleam/dynamic/decode
import gleam/float
import gleam/int
import gleam/json
import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/result
import sqlight

/// Unix seconds, `end` excluded.
pub type Interval =
  #(Int, Int)

pub type Event {
  Event(
    at: Int,
    kind: String,
    piece: Option(String),
    station: Option(String),
    from: Option(String),
    /// Why a Piece paused: `rework`, `helping` or `held` (DESIGN.md R11,
    /// R14). None before the cause was recorded, which reads as `held`.
    cause: Option(String),
  )
}

/// One stay of a Piece or Sub-Piece (`unit`) at a Work Station: from the pull
/// in to the pull out of its Blue Bin. `end` is None while it lasts. `filled`
/// is when it went in the Blue Bin; `held` are its pauses while its Team
/// Member held another Piece.
pub type Pass {
  Pass(
    unit: String,
    station: String,
    start: Int,
    end: Option(Int),
    touch: List(Interval),
    filled: Option(Int),
    held: List(Interval),
  )
}

/// Lead Time = Touch Time + Stagnation Time, in seconds, in Calendar Time and
/// in Working Time. Touch Time is net, so it is the same in both: only the
/// Stagnation counts the Working Calendar.
pub type Span {
  Span(touch: Int, stagnation: Int, stagnation_working: Int)
}

pub fn lead(span: Span) -> Int {
  span.touch + span.stagnation
}

pub fn lead_working(span: Span) -> Int {
  span.touch + span.stagnation_working
}

type Open {
  Open(
    station: String,
    start: Int,
    touching: Option(Int),
    touch: List(Interval),
    filled: Option(Int),
    held_since: Option(Int),
    held: List(Interval),
  )
}

type Replay {
  Replay(open: Dict(String, Open), done: List(Pass))
}

/// Replays the flow events in order into the Passes of every Piece and
/// Sub-Piece. A Piece is in hand from its pull (or Assembly, or resume) to its
/// pause or its Blue Bin; it leaves the Blue Bin on the next pull from there,
/// on its Split, on its Assembly (for its Sub-Pieces) or at its Deployment.
pub fn replay(
  events: List(Event),
  children: Dict(String, List(String)),
  now: Int,
) -> List(Pass) {
  let replayed =
    list.fold(events, Replay(open: dict.new(), done: []), fn(state, event) {
      case event.piece {
        None -> state
        Some(unit) -> step(state, event, unit, children)
      }
    })
  dict.fold(replayed.open, replayed.done, fn(done, unit, open) {
    [close_pass(unit, open, None, now), ..done]
  })
  |> list.reverse
}

fn step(
  state: Replay,
  event: Event,
  unit: String,
  children: Dict(String, List(String)),
) -> Replay {
  let at = event.at
  case event.kind, event.station {
    "piece_pulled", Some(station) | "piece_assembled", Some(station) -> {
      let state = case event.from {
        Some(from) -> leave(state, unit, from, at)
        None -> state
      }
      let state = case event.kind {
        "piece_assembled" ->
          dict.get(children, unit)
          |> result.unwrap([])
          |> list.fold(state, fn(state, child) { leave_any(state, child, at) })
        _ -> state
      }
      let state = leave_any(state, unit, at)
      Replay(
        ..state,
        open: dict.insert(
          state.open,
          unit,
          Open(
            station:,
            start: at,
            touching: Some(at),
            touch: [],
            filled: None,
            held_since: None,
            held: [],
          ),
        ),
      )
    }
    "piece_paused", _ ->
      update(state, unit, fn(open) {
        let open = stop_touching(open, at)
        case event.cause, open.held_since {
          Some("rework"), _ | Some("helping"), _ | _, Some(_) -> open
          _, None -> Open(..open, held_since: Some(at))
        }
      })
    "piece_put_in_blue_bin", _ ->
      update(state, unit, fn(open) {
        Open(
          ..stop_holding(stop_touching(open, at), at),
          filled: option.or(open.filled, Some(at)),
        )
      })
    "piece_resumed", _ ->
      update(state, unit, fn(open) {
        let open = stop_holding(open, at)
        case open.touching {
          None -> Open(..open, touching: Some(at))
          Some(_) -> open
        }
      })
    "piece_split", _ | "piece_deployed", _ -> leave_any(state, unit, at)
    _, _ -> state
  }
}

fn stop_touching(open: Open, at: Int) -> Open {
  case open.touching {
    Some(since) ->
      Open(..open, touching: None, touch: [#(since, at), ..open.touch])
    None -> open
  }
}

fn stop_holding(open: Open, at: Int) -> Open {
  case open.held_since {
    Some(since) ->
      Open(..open, held_since: None, held: [#(since, at), ..open.held])
    None -> open
  }
}

fn update(state: Replay, unit: String, change: fn(Open) -> Open) -> Replay {
  case dict.get(state.open, unit) {
    Ok(open) ->
      Replay(..state, open: dict.insert(state.open, unit, change(open)))
    Error(Nil) -> state
  }
}

/// A Sub-Piece pulled from the trunk was never in that Blue Bin itself, so
/// only a Pass at `station` ends.
fn leave(state: Replay, unit: String, station: String, at: Int) -> Replay {
  case dict.get(state.open, unit) {
    Ok(open) if open.station == station -> leave_any(state, unit, at)
    _ -> state
  }
}

fn leave_any(state: Replay, unit: String, at: Int) -> Replay {
  case dict.get(state.open, unit) {
    Ok(open) ->
      Replay(open: dict.delete(state.open, unit), done: [
        close_pass(unit, open, Some(at), at),
        ..state.done
      ])
    Error(Nil) -> state
  }
}

fn close_pass(unit: String, open: Open, end: Option(Int), at: Int) -> Pass {
  let open = stop_holding(stop_touching(open, at), at)
  Pass(
    unit:,
    station: open.station,
    start: open.start,
    end:,
    touch: open.touch,
    filled: open.filled,
    held: open.held,
  )
}

/// Replenishment Time of one pass, from the pull in to the Blue Bin.
pub type Replenishment {
  Replenishment(
    filled: Int,
    calendar: Int,
    working: Int,
    /// Working Time without the pauses while the Team Member held another
    /// Piece: those grow with the WIP, not with the work (DESIGN.md R11).
    working_without_held: Int,
  )
}

pub fn replenishment(
  calendar: Calendar,
  pass: Pass,
) -> Result(Replenishment, Nil) {
  use filled <- result.try(option.to_result(pass.filled, Nil))
  let span = span(calendar, pass.start, filled, pass.touch)
  let working = lead_working(span)
  let held = working_total(calendar, clip(pass.held, pass.start, filled))
  Ok(Replenishment(
    filled:,
    calendar: lead(span),
    working:,
    working_without_held: int.max(0, working - held),
  ))
}

/// The value that 85 % of `values` stay at or under (nearest rank).
pub fn p85(values: List(Int)) -> Result(Int, Nil) {
  let sorted = list.sort(values, int.compare)
  let rank = { list.length(sorted) * 85 + 99 } / 100
  sorted |> list.drop(int.max(rank - 1, 0)) |> list.first
}

/// Fewer passes than this give no Replenishment Time and no suggestion.
pub const min_passes = 5

/// The suggestion reads the last passes that went in the Blue Bin (H15).
pub const suggestion_passes = 20

/// Suggested Blue Bins (F55): enough to cover the Replenishment Time at the
/// Takt Time of the Line.
pub type Suggestion {
  Suggestion(passes: Int, replenishment: Option(Int), blue_bins: Option(Int))
}

pub fn suggest(
  replenishments: List(Replenishment),
  takt_hours: Float,
) -> Suggestion {
  let last =
    replenishments
    |> list.sort(fn(a, b) { int.compare(b.filled, a.filled) })
    |> list.take(suggestion_passes)
  let passes = list.length(last)
  let replenishment = case passes >= min_passes {
    True ->
      p85(list.map(last, fn(one) { one.working_without_held }))
      |> option.from_result
    False -> None
  }
  // In whole seconds, so that 8 h at a Takt Time of 4 h is 2, not 2.0000001.
  let takt = float.round(takt_hours *. 3600.0)
  let blue_bins = case replenishment, takt > 0 {
    Some(seconds), True -> Some(int.max(1, { seconds + takt - 1 } / takt))
    _, _ -> None
  }
  Suggestion(passes:, replenishment:, blue_bins:)
}

/// Touch Time is the union of `touches` inside [from, to); the rest of that
/// time is Stagnation Time.
pub fn span(
  calendar: Calendar,
  from: Int,
  to: Int,
  touches: List(Interval),
) -> Span {
  let touched = union(clip(touches, from, to))
  let touch = calendar_total(touched)
  let stagnation_working = working_total(calendar, gaps(touched, from, to))
  Span(touch:, stagnation: int.max(0, to - from) - touch, stagnation_working:)
}

/// The sum of `intervals`, in Calendar Time.
fn calendar_total(intervals: List(Interval)) -> Int {
  list.fold(intervals, 0, fn(total, one) { total + one.1 - one.0 })
}

/// The sum of `intervals`, in Working Time.
fn working_total(calendar: Calendar, intervals: List(Interval)) -> Int {
  list.fold(intervals, 0, fn(total, one) {
    total + calendar.working_seconds(calendar, one.0, one.1)
  })
}

fn clip(intervals: List(Interval), from: Int, to: Int) -> List(Interval) {
  list.filter_map(intervals, fn(one) {
    let clipped = #(int.max(one.0, from), int.min(one.1, to))
    case clipped.0 < clipped.1 {
      True -> Ok(clipped)
      False -> Error(Nil)
    }
  })
}

fn union(intervals: List(Interval)) -> List(Interval) {
  intervals
  |> list.sort(fn(a, b) { int.compare(a.0, b.0) })
  |> list.fold([], fn(merged: List(Interval), one: Interval) {
    case merged {
      [last, ..rest] if one.0 <= last.1 -> [
        #(last.0, int.max(last.1, one.1)),
        ..rest
      ]
      _ -> [one, ..merged]
    }
  })
  |> list.reverse
}

/// `touched` is sorted and disjoint, inside [from, to).
fn gaps(touched: List(Interval), from: Int, to: Int) -> List(Interval) {
  let #(cursor, found) =
    list.fold(touched, #(from, []), fn(acc, one) {
      let #(cursor, found) = acc
      #(one.1, [#(cursor, one.0), ..found])
    })
  [#(cursor, to), ..found]
  |> list.filter(fn(gap) { gap.0 < gap.1 })
}

/// The time a Work Station holds at least one Kanban.
pub fn kanban_held(
  events: List(Event),
  now: Int,
) -> Dict(String, List(Interval)) {
  let #(held, intervals) =
    list.fold(events, #(dict.new(), dict.new()), fn(acc, event) {
      let #(held, intervals) = acc
      case event.kind, event.station {
        "kanban_sent", Some(station) ->
          case dict.get(held, station) {
            Ok(#(count, since)) -> #(
              dict.insert(held, station, #(count + 1, since)),
              intervals,
            )
            Error(Nil) -> #(
              dict.insert(held, station, #(1, event.at)),
              intervals,
            )
          }
        "kanban_spent", Some(station) ->
          case dict.get(held, station) {
            Ok(#(1, since)) -> #(
              dict.delete(held, station),
              add(intervals, station, #(since, event.at)),
            )
            Ok(#(count, since)) -> #(
              dict.insert(held, station, #(count - 1, since)),
              intervals,
            )
            Error(Nil) -> acc
          }
        _, _ -> acc
      }
    })
  dict.fold(held, intervals, fn(intervals, station, still) {
    add(intervals, station, #(still.1, now))
  })
}

fn add(
  intervals: Dict(String, List(Interval)),
  station: String,
  one: Interval,
) -> Dict(String, List(Interval)) {
  dict.upsert(intervals, station, fn(found) {
    [one, ..option.unwrap(found, [])]
  })
}

pub type Period {
  Period(from: String, to: String, start: Int, end: Int)
}

pub type PieceMeasure {
  PieceMeasure(
    id: String,
    demand: String,
    released: Int,
    span: Span,
    backlog: Option(Span),
  )
}

pub type StationMeasure {
  StationMeasure(
    id: String,
    name: String,
    branch: Option(String),
    position: Int,
    passes: List(Span),
    /// The passes that went in the Blue Bin in the period (F54).
    replenishments: List(Replenishment),
    starvation: Int,
    starvation_working: Int,
    andon: Int,
    andon_working: Int,
    andons: Int,
    pulls: Int,
    deviations: Int,
  )
}

pub type DemandMeasure {
  DemandMeasure(
    id: String,
    label: String,
    client: String,
    pieces: List(PieceMeasure),
    lead: Option(Span),
  )
}

pub type Measures {
  Measures(
    period: Period,
    pieces: List(PieceMeasure),
    demands: List(DemandMeasure),
    stations: List(StationMeasure),
    deviations: List(wire.RecordedDeviation),
    /// The time at least one Work Station is stopped: stops at the same time
    /// count once.
    andon: Int,
    andon_working: Int,
    /// Demands delivered in the period, and those of them delivered on or
    /// before their due date.
    delivered: Int,
    on_time: Int,
  )
}

pub type MeasuresError {
  InvalidPeriod
  StoreFailed
}

type PieceRow {
  PieceRow(
    id: String,
    parent: Option(String),
    demand: String,
    entered: Int,
    released: Option(Int),
  )
}

/// Every measure is computed from the flow event log on each read, so a
/// change of the Working Calendar recomputes them all (DESIGN.md §4, C3).
pub fn load(
  connection: sqlight.Connection,
  from: String,
  to: String,
) -> Result(Measures, MeasuresError) {
  use period <- result.try(load_period(connection, from, to))
  use now <- result.try(db.now(connection) |> result.replace_error(StoreFailed))
  use #(calendar, events, pieces, children, passes) <- result.try(load_passes(
    connection,
    now,
  ))
  use reworks <- result.try(query(connection, reworks_sql, [], timed_decoder()))
  use stops <- result.try(query(connection, stops_sql, [], timed_decoder()))
  use stations <- result.try(query(
    connection,
    stations_sql,
    [],
    station_decoder(),
  ))
  use demands <- result.try(query(connection, demands_sql, [], demand_decoder()))
  use #(delivered, on_time) <- result.try(load_deliveries(connection, from, to))
  use deviations <- result.try(query(
    connection,
    deviations_sql,
    [sqlight.int(period.start), sqlight.int(period.end)],
    deviation_decoder(),
  ))

  let context =
    Context(
      calendar:,
      period:,
      now:,
      children:,
      passes_by_unit: group(passes, fn(pass) { pass.unit }),
      reworks_by_unit: group(reworks, fn(rework) { rework.0 })
        |> dict.map_values(fn(_, found) { list.map(found, fn(one) { one.1 }) }),
    )
  let released = piece_measures(context, pieces)
  let #(andon, andon_working) =
    stops |> list.map(fn(stop) { stop.1 }) |> union |> measured(context, _)
  Ok(Measures(
    period:,
    pieces: released,
    demands: demand_measures(context, demands, pieces, released),
    stations: station_measures(
      context,
      stations,
      passes,
      events,
      stops,
      deviations,
    ),
    deviations:,
    andon:,
    andon_working:,
    delivered:,
    on_time:,
  ))
}

/// The first day of the Line, and the last `weeks` weeks, Monday to Sunday
/// (UTC), the current week last: the points of the run chart (F38). The log is read once for all the weeks.
pub fn weekly(
  connection: sqlight.Connection,
  weeks: Int,
) -> Result(wire.WeekHistory, MeasuresError) {
  use periods <- result.try(
    query(
      connection,
      "with recursive week(n, monday) as (
      select 1, date('now', '-6 days', 'weekday 1', ?1)
      union all
      select n + 1, date(monday, '+7 days') from week where n < ?2
    )
    select monday, date(monday, '+6 days'),
           cast(strftime('%s', monday) as integer),
           cast(strftime('%s', monday, '+7 days') as integer)
    from week order by n",
      [
        sqlight.text("-" <> int.to_string(7 * { weeks - 1 }) <> " days"),
        sqlight.int(weeks),
      ],
      {
        use from <- decode.field(0, decode.string)
        use to <- decode.field(1, decode.string)
        use start <- decode.field(2, decode.int)
        use end <- decode.field(3, decode.int)
        decode.success(Period(from:, to:, start:, end:))
      },
    ),
  )
  // Every Line sends its first Kanbans when it starts, so its log is never
  // empty for long; until then, it starts today.
  use started <- result.try(query(
    connection,
    "select date(coalesce(min(at), 'now')) from flow_event",
    [],
    decode.at([0], decode.string),
  ))
  let started_on = list.first(started) |> result.unwrap("")
  use now <- result.try(db.now(connection) |> result.replace_error(StoreFailed))
  use #(calendar, _, pieces, children, passes) <- result.try(load_passes(
    connection,
    now,
  ))
  use reworks <- result.try(query(connection, reworks_sql, [], timed_decoder()))
  let passes_by_unit = group(passes, fn(pass) { pass.unit })
  let reworks_by_unit =
    group(reworks, fn(rework) { rework.0 })
    |> dict.map_values(fn(_, found) { list.map(found, fn(one) { one.1 }) })
  list.map(periods, fn(period) {
    let context =
      Context(
        calendar:,
        period:,
        now:,
        children:,
        passes_by_unit:,
        reworks_by_unit:,
      )
    let released = piece_measures(context, pieces)
    wire.WeekMeasures(
      from: period.from,
      to: period.to,
      pieces: list.length(released),
      lead_time: average_lead(list.map(released, fn(piece) { piece.span })),
    )
  })
  |> wire.WeekHistory(started_on:, weeks: _)
  |> Ok
}

/// What the measures of one `load` share. The passes and the Rework touches
/// are grouped by Piece or Sub-Piece once, so no measure rescans them.
type Context {
  Context(
    calendar: Calendar,
    period: Period,
    now: Int,
    children: Dict(String, List(String)),
    passes_by_unit: Dict(String, List(Pass)),
    reworks_by_unit: Dict(String, List(Interval)),
  )
}

type StationRow {
  StationRow(id: String, name: String, branch: Option(String), position: Int)
}

type DemandRow {
  DemandRow(id: String, label: String, client: String)
}

fn load_period(
  connection: sqlight.Connection,
  from: String,
  to: String,
) -> Result(Period, MeasuresError) {
  use rows <- result.try(
    query(
      connection,
      "select date(?1) is ?1 and date(?2) is ?2 and ?1 <= ?2,
              cast(strftime('%s', ?1) as integer),
              cast(strftime('%s', ?2, '+1 day') as integer)",
      [sqlight.text(from), sqlight.text(to)],
      {
        use valid <- decode.field(0, decode.optional(decode.int))
        use start <- decode.field(1, decode.optional(decode.int))
        use end <- decode.field(2, decode.optional(decode.int))
        decode.success(#(valid, start, end))
      },
    ),
  )
  case rows {
    [#(Some(1), Some(start), Some(end))] -> Ok(Period(from:, to:, start:, end:))
    _ -> Error(InvalidPeriod)
  }
}

/// Demands delivered in the period, and those of them on time.
fn load_deliveries(
  connection: sqlight.Connection,
  from: String,
  to: String,
) -> Result(#(Int, Int), MeasuresError) {
  use rows <- result.try(
    query(connection, on_time_sql, [sqlight.text(from), sqlight.text(to)], {
      use delivered <- decode.field(0, decode.int)
      use on_time <- decode.field(1, decode.int)
      decode.success(#(delivered, on_time))
    }),
  )
  case rows {
    [row, ..] -> Ok(row)
    [] -> Ok(#(0, 0))
  }
}

fn in_period(context: Context, at: Int) -> Bool {
  at >= context.period.start && at < context.period.end
}

/// Calendar Time and Working Time of `intervals` inside the period, up to now.
fn measured(context: Context, intervals: List(Interval)) -> #(Int, Int) {
  let intervals =
    clip(
      intervals,
      context.period.start,
      int.min(context.period.end, context.now),
    )
  #(calendar_total(intervals), working_total(context.calendar, intervals))
}

/// The touches of a Piece and its Sub-Pieces: their passes and their Rework.
fn touches(context: Context, piece: String) -> List(Interval) {
  [piece, ..lookup(context.children, piece)]
  |> list.flat_map(fn(unit) {
    list.append(
      lookup(context.passes_by_unit, unit)
        |> list.flat_map(fn(pass) { pass.touch }),
      lookup(context.reworks_by_unit, unit),
    )
  })
}

/// The Pieces released in the period. The Lead Time ends at the Release.
fn piece_measures(
  context: Context,
  pieces: List(PieceRow),
) -> List(PieceMeasure) {
  list.filter_map(pieces, fn(piece) {
    case piece.parent, piece.released {
      None, Some(released) ->
        case in_period(context, released) {
          True -> {
            let first_pull =
              lookup(context.passes_by_unit, piece.id)
              |> list.map(fn(pass) { pass.start })
              |> list.reduce(int.min)
            Ok(PieceMeasure(
              id: piece.id,
              demand: piece.demand,
              released:,
              span: span(
                context.calendar,
                piece.entered,
                released,
                touches(context, piece.id),
              ),
              backlog: first_pull
                |> result.map(fn(pulled) {
                  span(context.calendar, piece.entered, pulled, [])
                })
                |> option.from_result,
            ))
          }
          False -> Error(Nil)
        }
      _, _ -> Error(Nil)
    }
  })
}

/// The Demands with a Piece released in the period. The Demand Lead Time
/// shows once every Piece of the Demand is released.
fn demand_measures(
  context: Context,
  demands: List(DemandRow),
  pieces: List(PieceRow),
  released: List(PieceMeasure),
) -> List(DemandMeasure) {
  let released_by_demand = group(released, fn(piece) { piece.demand })
  let pieces_by_demand =
    pieces
    |> list.filter(fn(piece) { piece.parent == None })
    |> group(fn(piece) { piece.demand })
  list.filter_map(demands, fn(demand) {
    case lookup(released_by_demand, demand.id) {
      [] -> Error(Nil)
      measured ->
        Ok(DemandMeasure(
          id: demand.id,
          label: demand.label,
          client: demand.client,
          pieces: measured,
          lead: demand_lead(context, lookup(pieces_by_demand, demand.id)),
        ))
    }
  })
}

/// `all` is every Piece of the Demand.
fn demand_lead(context: Context, all: List(PieceRow)) -> Option(Span) {
  let end = context.period.end
  let last =
    all
    |> list.map(fn(piece) { option.unwrap(piece.released, end) })
    |> list.fold(0, int.max)
  case list.all(all, fn(piece) { piece.released != None }) && last < end {
    True -> {
      let first =
        all
        |> list.map(fn(piece) { piece.entered })
        |> list.reduce(int.min)
        |> result.unwrap(last)
      Some(span(
        context.calendar,
        first,
        last,
        list.flat_map(all, fn(piece) { touches(context, piece.id) }),
      ))
    }
    False -> None
  }
}

fn station_measures(
  context: Context,
  stations: List(StationRow),
  passes: List(Pass),
  events: List(Event),
  stops: List(#(String, Interval)),
  deviations: List(wire.RecordedDeviation),
) -> List(StationMeasure) {
  let passes_by_station = group(passes, fn(pass) { pass.station })
  let stops_by_station =
    group(stops, fn(stop) { stop.0 })
    |> dict.map_values(fn(_, found) { list.map(found, fn(stop) { stop.1 }) })
  let pulls_by_station =
    list.filter_map(events, fn(event) {
      case event.kind, event.station {
        "piece_pulled", Some(station) | "piece_assembled", Some(station) ->
          case in_period(context, event.at) {
            True -> Ok(station)
            False -> Error(Nil)
          }
        _, _ -> Error(Nil)
      }
    })
    |> group(fn(station) { station })
  let deviations_by_station = group(deviations, fn(row) { row.station })
  let held = kanban_held(events, context.now)
  list.map(stations, fn(station) {
    let id = station.id
    let station_passes = lookup(passes_by_station, id)
    let station_stops = lookup(stops_by_station, id)
    let #(starvation, starvation_working) = measured(context, lookup(held, id))
    let #(andon, andon_working) = measured(context, station_stops)
    StationMeasure(
      id:,
      name: station.name,
      branch: station.branch,
      position: station.position,
      passes: closed_spans(context, station_passes),
      replenishments: list.filter_map(station_passes, fn(pass) {
        replenishment(context.calendar, pass)
        |> result.try(fn(one) {
          case in_period(context, one.filled) {
            True -> Ok(one)
            False -> Error(Nil)
          }
        })
      }),
      starvation:,
      starvation_working:,
      andon:,
      andon_working:,
      andons: list.count(station_stops, fn(stop) { in_period(context, stop.0) }),
      pulls: list.length(lookup(pulls_by_station, id)),
      deviations: list.length(lookup(deviations_by_station, id)),
    )
  })
}

/// The Station Lead Time of each pass that ended in the period, with the
/// Rework of its Piece as touch.
fn closed_spans(context: Context, passes: List(Pass)) -> List(Span) {
  list.filter_map(passes, fn(pass) {
    case pass.end {
      Some(end) ->
        case in_period(context, end) {
          True ->
            Ok(span(
              context.calendar,
              pass.start,
              end,
              list.append(
                pass.touch,
                lookup(context.reworks_by_unit, pass.unit),
              ),
            ))
          False -> Error(Nil)
        }
      None -> Error(Nil)
    }
  })
}

/// `items` grouped by `key`, each group in the order of `items`: the order
/// of the passes breaks ties when the suggestion sorts them.
fn group(items: List(a), key: fn(a) -> k) -> Dict(k, List(a)) {
  // `list.group` prepends, so grouping the reversed list keeps the order.
  items |> list.reverse |> list.group(key)
}

fn lookup(groups: Dict(k, List(a)), key: k) -> List(a) {
  dict.get(groups, key) |> result.unwrap([])
}

fn query(
  connection: sqlight.Connection,
  sql: String,
  values: List(sqlight.Value),
  decoder: decode.Decoder(a),
) -> Result(List(a), MeasuresError) {
  sqlight.query(sql, on: connection, with: values, expecting: decoder)
  |> result.replace_error(StoreFailed)
}

/// The Passes of every Piece and Sub-Piece, replayed from the log.
fn load_passes(
  connection: sqlight.Connection,
  now: Int,
) -> Result(
  #(
    Calendar,
    List(Event),
    List(PieceRow),
    Dict(String, List(String)),
    List(Pass),
  ),
  MeasuresError,
) {
  use calendar <- result.try(
    calendar.load(connection) |> result.replace_error(StoreFailed),
  )
  use events <- result.try(query(connection, events_sql, [], event_decoder()))
  use pieces <- result.try(query(connection, pieces_sql, [], piece_decoder()))
  let children =
    list.fold(pieces, dict.new(), fn(children, piece) {
      case piece.parent {
        Some(parent) ->
          dict.upsert(children, parent, fn(found) {
            [piece.id, ..option.unwrap(found, [])]
          })
        None -> children
      }
    })
  Ok(#(calendar, events, pieces, children, replay(events, children, now)))
}

/// Suggested Blue Bins for each Work Station that has passes (F55, H15).
pub fn suggestions(
  connection: sqlight.Connection,
  takt_hours: Float,
) -> Result(Dict(String, Suggestion), MeasuresError) {
  use now <- result.try(db.now(connection) |> result.replace_error(StoreFailed))
  use #(calendar, _, _, _, passes) <- result.try(load_passes(connection, now))
  passes
  |> list.filter_map(fn(pass) {
    replenishment(calendar, pass)
    |> result.map(fn(one) { #(pass.station, one) })
  })
  |> list.group(fn(entry) { entry.0 })
  |> dict.map_values(fn(_, entries) {
    suggest(list.map(entries, fn(entry) { entry.1 }), takt_hours)
  })
  |> Ok
}

const events_sql =
  "
select cast(strftime('%s', at) as integer), kind, piece_id,
       json_extract(payload, '$.station'), json_extract(payload, '$.from'),
       json_extract(payload, '$.cause')
  from flow_event
 where kind in ('piece_pulled', 'piece_assembled', 'piece_paused',
                'piece_resumed', 'piece_put_in_blue_bin', 'piece_split',
                'piece_deployed', 'kanban_sent', 'kanban_spent')
 order by at, id
"

const pieces_sql =
  "
select p.id, p.parent_id, p.demand_id,
       cast(strftime('%s', coalesce(p.entered_at, d.started_on)) as integer),
       cast(strftime('%s', p.released_at) as integer)
  from piece p join demand d on d.id = p.demand_id
"

const reworks_sql =
  "
select piece_id, cast(strftime('%s', started_at) as integer),
       cast(strftime('%s', coalesce(closed_at, 'now')) as integer)
  from rework where started_at is not null
"

const stops_sql =
  "
select station_id, cast(strftime('%s', raised_at) as integer),
       cast(strftime('%s', coalesce(closed_at, 'now')) as integer)
  from andon
"

const stations_sql =
  "
select id, name, branch, position from work_station
 order by position, branch
"

const demands_sql = "select id, label, client from demand order by due_on"

/// A Demand is delivered on the day of the Release of its last Piece.
const on_time_sql =
  "
select count(*), coalesce(sum(delivered_on <= due_on), 0)
  from (select d.due_on,
               (select date(max(p.released_at)) from piece p
                 where p.demand_id = d.id and p.parent_id is null) as delivered_on
          from demand d
         where d.state = 'delivered')
 where delivered_on between ?1 and ?2
"

const deviations_sql =
  "
select d.at, d.rule, d.station_id, w.name, p.reference, d.reason
  from deviation d
  join work_station w on w.id = d.station_id
  left join piece p on p.id = d.piece_id
 where cast(strftime('%s', d.at) as integer) >= ?1
   and cast(strftime('%s', d.at) as integer) < ?2
 order by d.at, d.id
"

fn event_decoder() -> decode.Decoder(Event) {
  use at <- decode.field(0, decode.int)
  use kind <- decode.field(1, decode.string)
  use piece <- decode.field(2, decode.optional(decode.string))
  use station <- decode.field(3, decode.optional(decode.string))
  use from <- decode.field(4, decode.optional(decode.string))
  use cause <- decode.field(5, decode.optional(decode.string))
  decode.success(Event(at:, kind:, piece:, station:, from:, cause:))
}

fn piece_decoder() -> decode.Decoder(PieceRow) {
  use id <- decode.field(0, decode.string)
  use parent <- decode.field(1, decode.optional(decode.string))
  use demand <- decode.field(2, decode.string)
  use entered <- decode.field(3, decode.int)
  use released <- decode.field(4, decode.optional(decode.int))
  decode.success(PieceRow(id:, parent:, demand:, entered:, released:))
}

/// A Rework of a Piece, or an Andon of a Work Station, with its interval.
fn timed_decoder() -> decode.Decoder(#(String, Interval)) {
  use id <- decode.field(0, decode.string)
  use start <- decode.field(1, decode.int)
  use end <- decode.field(2, decode.int)
  decode.success(#(id, #(start, end)))
}

fn station_decoder() -> decode.Decoder(StationRow) {
  use id <- decode.field(0, decode.string)
  use name <- decode.field(1, decode.string)
  use branch <- decode.field(2, decode.optional(decode.string))
  use position <- decode.field(3, decode.int)
  decode.success(StationRow(id:, name:, branch:, position:))
}

fn demand_decoder() -> decode.Decoder(DemandRow) {
  use id <- decode.field(0, decode.string)
  use label <- decode.field(1, decode.string)
  use client <- decode.field(2, decode.string)
  decode.success(DemandRow(id:, label:, client:))
}

fn deviation_decoder() -> decode.Decoder(wire.RecordedDeviation) {
  use at <- decode.field(0, decode.string)
  use rule <- decode.field(1, decode.string)
  use station <- decode.field(2, decode.string)
  use station_name <- decode.field(3, decode.string)
  use piece <- decode.field(4, decode.optional(decode.string))
  use reason <- decode.field(5, decode.string)
  decode.success(wire.RecordedDeviation(
    at:,
    rule:,
    station:,
    station_name:,
    piece:,
    reason:,
  ))
}

pub fn to_json(measures: Measures) -> json.Json {
  let pieces = measures.pieces
  let piece_spans = list.map(pieces, fn(piece) { piece.span })
  wire.Measures(
    from: measures.period.from,
    to: measures.period.to,
    pieces: wire.PieceMeasures(
      count: list.length(pieces),
      lead_time: average_lead(piece_spans),
      touch_time: average_touch(piece_spans),
      stagnation_time: average_stagnation(piece_spans),
      backlog_time: average_lead(
        list.filter_map(pieces, fn(piece) {
          option.to_result(piece.backlog, Nil)
        }),
      ),
    ),
    demands: list.map(measures.demands, fn(demand) {
      let spans = list.map(demand.pieces, fn(piece) { piece.span })
      wire.DemandMeasures(
        id: demand.id,
        label: demand.label,
        client: demand.client,
        pieces: list.length(demand.pieces),
        demand_lead_time: option.map(demand.lead, fn(span) {
          duration(Some(lead(span)), Some(lead_working(span)))
        }),
        lead_time: average_lead(spans),
        touch_time: average_touch(spans),
        stagnation_time: average_stagnation(spans),
      )
    }),
    stations: list.map(measures.stations, fn(station) {
      let touch = list.fold(station.passes, 0, fn(t, span) { t + span.touch })
      let leads = list.fold(station.passes, 0, fn(t, span) { t + lead(span) })
      wire.StationMeasures(
        id: station.id,
        name: station.name,
        branch: station.branch,
        position: station.position,
        passes: list.length(station.passes),
        station_lead_time: average_lead(station.passes),
        touch_time: average_touch(station.passes),
        replenishment_time: p85_duration(station.replenishments),
        touch_share: case leads {
          0 -> None
          _ -> Some(hundredth(int.to_float(touch) /. int.to_float(leads)))
        },
        starvation_time: Some(duration(
          Some(station.starvation),
          Some(station.starvation_working),
        )),
        andon_time: Some(duration(
          Some(station.andon),
          Some(station.andon_working),
        )),
        andons: station.andons,
        pulls: station.pulls,
        deviations: station.deviations,
      )
    }),
    andon_time: Some(duration(
      Some(measures.andon),
      Some(measures.andon_working),
    )),
    on_time: wire.OnTime(
      delivered: measures.delivered,
      on_time: measures.on_time,
    ),
    deviations: wire.DeviationMeasures(
      by_rule: by_rule(measures.deviations),
      list: measures.deviations,
    ),
  )
  |> wire_json.measures
}

/// p85 Replenishment Time, or null under `min_passes` passes (F54).
fn p85_duration(replenishments: List(Replenishment)) -> Option(wire.Duration) {
  case list.length(replenishments) >= min_passes {
    False -> None
    True ->
      Some(duration(
        p85(list.map(replenishments, fn(one) { one.calendar }))
          |> option.from_result,
        p85(list.map(replenishments, fn(one) { one.working }))
          |> option.from_result,
      ))
  }
}

fn average_lead(spans: List(Span)) -> Option(wire.Duration) {
  average(spans, fn(span) { #(lead(span), lead_working(span)) })
}

fn average_touch(spans: List(Span)) -> Option(wire.Duration) {
  average(spans, fn(span) { #(span.touch, span.touch) })
}

fn average_stagnation(spans: List(Span)) -> Option(wire.Duration) {
  average(spans, fn(span) { #(span.stagnation, span.stagnation_working) })
}

fn average(
  spans: List(Span),
  measure: fn(Span) -> #(Int, Int),
) -> Option(wire.Duration) {
  case list.length(spans) {
    0 -> None
    count -> {
      let #(calendar, working) =
        list.fold(spans, #(0, 0), fn(total, span) {
          let #(c, w) = measure(span)
          #(total.0 + c, total.1 + w)
        })
      Some(duration(Some(calendar / count), Some(working / count)))
    }
  }
}

fn duration(calendar: Option(Int), working: Option(Int)) -> wire.Duration {
  let hours = fn(seconds) { hundredth(int.to_float(seconds) /. 3600.0) }
  wire.Duration(
    calendar: option.map(calendar, hours),
    working: option.map(working, hours),
  )
}

fn hundredth(value: Float) -> Float {
  int.to_float(float.round(value *. 100.0)) /. 100.0
}

fn by_rule(rows: List(wire.RecordedDeviation)) -> List(wire.RuleCount) {
  rows
  |> list.group(fn(row) { row.rule })
  |> dict.to_list
  |> list.map(fn(group) { #(group.0, list.length(group.1)) })
  |> list.sort(fn(a, b) { int.compare(b.1, a.1) })
  |> list.map(fn(row) { wire.RuleCount(rule: row.0, count: row.1) })
}
