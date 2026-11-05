import bluebin/calendar.{type Calendar}
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
  )
}

/// One stay of a Piece or Sub-Piece (`unit`) at a Work Station: from the pull
/// in to the pull out of its Blue Bin. `end` is None while it lasts.
pub type Pass {
  Pass(
    unit: String,
    station: String,
    start: Int,
    end: Option(Int),
    touch: List(Interval),
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
  )
}

type Replay {
  Replay(open: Dict(String, Open), done: List(Pass))
}

/// Replays the flow events in order into the Passes of every Piece and
/// Sub-Piece. A Piece is in hand from its pull (or Assembly, or resume) to its
/// pause or its Blue Bin; it leaves the Blue Bin on the next pull from there,
/// on its Split, on its Assembly (for its Sub-Pieces) or in production.
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
          Open(station:, start: at, touching: Some(at), touch: []),
        ),
      )
    }
    "piece_paused", _ | "piece_put_in_blue_bin", _ ->
      update(state, unit, fn(open) {
        case open.touching {
          Some(since) ->
            Open(..open, touching: None, touch: [#(since, at), ..open.touch])
          None -> open
        }
      })
    "piece_resumed", _ ->
      update(state, unit, fn(open) {
        case open.touching {
          None -> Open(..open, touching: Some(at))
          Some(_) -> open
        }
      })
    "piece_split", _ | "piece_reached_production", _ ->
      leave_any(state, unit, at)
    _, _ -> state
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
  let touch = case open.touching {
    Some(since) -> [#(since, at), ..open.touch]
    None -> open.touch
  }
  Pass(unit:, station: open.station, start: open.start, end:, touch:)
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
  let touch = list.fold(touched, 0, fn(total, one) { total + one.1 - one.0 })
  let stagnation_working =
    gaps(touched, from, to)
    |> list.fold(0, fn(total, gap) {
      total + calendar.working_seconds(calendar, gap.0, gap.1)
    })
  Span(touch:, stagnation: int.max(0, to - from) - touch, stagnation_working:)
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

// --- Measures of one period -------------------------------------------------

pub type Period {
  Period(from: String, to: String, start: Int, end: Int)
}

pub type PieceMeasure {
  PieceMeasure(
    id: String,
    demand: String,
    produced: Int,
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
    starvation: Int,
    starvation_working: Int,
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

pub type DeviationRow {
  DeviationRow(
    at: String,
    rule: String,
    station: String,
    station_name: String,
    piece: Option(String),
    reason: String,
  )
}

pub type Measures {
  Measures(
    period: Period,
    pieces: List(PieceMeasure),
    demands: List(DemandMeasure),
    stations: List(StationMeasure),
    deviations: List(DeviationRow),
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
    produced: Option(Int),
  )
}

/// Every measure is computed from the flow event log on each read, so a
/// change of the Working Calendar recomputes them all (DESIGN.md §4, C3).
pub fn load(
  connection: sqlight.Connection,
  from: String,
  to: String,
) -> Result(Measures, MeasuresError) {
  use period <- result.try(
    query(
      connection,
      "select date(?1) is ?1 and date(?2) is ?2 and ?1 <= ?2,
              cast(strftime('%s', ?1) as integer),
              cast(strftime('%s', ?2, '+1 day') as integer),
              cast(strftime('%s', 'now') as integer)",
      [sqlight.text(from), sqlight.text(to)],
      {
        use valid <- decode.field(0, decode.optional(decode.int))
        use start <- decode.field(1, decode.optional(decode.int))
        use end <- decode.field(2, decode.optional(decode.int))
        use now <- decode.field(3, decode.int)
        decode.success(#(valid, start, end, now))
      },
    ),
  )
  use #(period, now) <- result.try(case period {
    [#(Some(1), Some(start), Some(end), now)] ->
      Ok(#(Period(from:, to:, start:, end:), now))
    _ -> Error(InvalidPeriod)
  })
  use calendar <- result.try(
    calendar.load(connection) |> result.replace_error(StoreFailed),
  )
  use events <- result.try(query(connection, events_sql, [], event_decoder()))
  use pieces <- result.try(query(connection, pieces_sql, [], piece_decoder()))
  use reworks <- result.try(
    query(
      connection,
      "select piece_id, cast(strftime('%s', started_at) as integer),
            cast(strftime('%s', coalesce(closed_at, 'now')) as integer)
       from rework where started_at is not null",
      [],
      {
        use piece <- decode.field(0, decode.string)
        use start <- decode.field(1, decode.int)
        use end <- decode.field(2, decode.int)
        decode.success(#(piece, #(start, end)))
      },
    ),
  )
  use stations <- result.try(
    query(
      connection,
      "select id, name, branch, position from work_station
      order by position, branch",
      [],
      {
        use id <- decode.field(0, decode.string)
        use name <- decode.field(1, decode.string)
        use branch <- decode.field(2, decode.optional(decode.string))
        use position <- decode.field(3, decode.int)
        decode.success(#(id, name, branch, position))
      },
    ),
  )
  use demands <- result.try(
    query(
      connection,
      "select id, label, client from demand order by due_on",
      [],
      {
        use id <- decode.field(0, decode.string)
        use label <- decode.field(1, decode.string)
        use client <- decode.field(2, decode.string)
        decode.success(#(id, label, client))
      },
    ),
  )
  use deviations <- result.try(query(
    connection,
    deviations_sql,
    [sqlight.int(period.start), sqlight.int(period.end)],
    deviation_decoder(),
  ))

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
  let passes = replay(events, children, now)
  let touches = fn(units: List(String)) {
    list.append(
      passes
        |> list.filter(fn(pass) { list.contains(units, pass.unit) })
        |> list.flat_map(fn(pass) { pass.touch }),
      reworks
        |> list.filter(fn(rework) { list.contains(units, rework.0) })
        |> list.map(fn(rework) { rework.1 }),
    )
  }
  let units_of = fn(piece: PieceRow) {
    [piece.id, ..result.unwrap(dict.get(children, piece.id), [])]
  }
  let in_period = fn(at: Int) { at >= period.start && at < period.end }

  let produced =
    list.filter_map(pieces, fn(piece) {
      case piece.parent, piece.produced {
        None, Some(produced) ->
          case in_period(produced) {
            True -> {
              let first_pull =
                passes
                |> list.filter(fn(pass) { pass.unit == piece.id })
                |> list.map(fn(pass) { pass.start })
                |> list.reduce(int.min)
              Ok(PieceMeasure(
                id: piece.id,
                demand: piece.demand,
                produced:,
                span: span(
                  calendar,
                  piece.entered,
                  produced,
                  touches(units_of(piece)),
                ),
                backlog: first_pull
                  |> result.map(fn(pulled) {
                    span(calendar, piece.entered, pulled, [])
                  })
                  |> option.from_result,
              ))
            }
            False -> Error(Nil)
          }
        _, _ -> Error(Nil)
      }
    })

  let demand_measures =
    list.filter_map(demands, fn(demand) {
      let #(id, label, client) = demand
      case list.filter(produced, fn(piece) { piece.demand == id }) {
        [] -> Error(Nil)
        measured -> {
          let all =
            list.filter(pieces, fn(piece) {
              piece.demand == id && piece.parent == None
            })
          let last =
            all
            |> list.map(fn(piece) { option.unwrap(piece.produced, period.end) })
            |> list.fold(0, int.max)
          let whole = case
            list.all(all, fn(piece) { piece.produced != None })
            && last < period.end
          {
            True -> {
              let first =
                all
                |> list.map(fn(piece) { piece.entered })
                |> list.reduce(int.min)
                |> result.unwrap(last)
              Some(span(
                calendar,
                first,
                last,
                list.flat_map(all, fn(piece) { touches(units_of(piece)) }),
              ))
            }
            False -> None
          }
          Ok(DemandMeasure(id:, label:, client:, pieces: measured, lead: whole))
        }
      }
    })

  let held = kanban_held(events, now)
  let station_measures =
    list.map(stations, fn(station) {
      let #(id, name, branch, position) = station
      let station_passes =
        list.filter_map(passes, fn(pass) {
          case pass.station == id, pass.end {
            True, Some(end) ->
              case in_period(end) {
                True ->
                  Ok(span(
                    calendar,
                    pass.start,
                    end,
                    list.append(
                      pass.touch,
                      touches_of_reworks(reworks, pass.unit),
                    ),
                  ))
                False -> Error(Nil)
              }
            _, _ -> Error(Nil)
          }
        })
      let starving =
        dict.get(held, id)
        |> result.unwrap([])
        |> clip(period.start, int.min(period.end, now))
      StationMeasure(
        id:,
        name:,
        branch:,
        position:,
        passes: station_passes,
        starvation: list.fold(starving, 0, fn(total, one) {
          total + one.1 - one.0
        }),
        starvation_working: list.fold(starving, 0, fn(total, one) {
          total + calendar.working_seconds(calendar, one.0, one.1)
        }),
        pulls: list.count(events, fn(event) {
          { event.kind == "piece_pulled" || event.kind == "piece_assembled" }
          && event.station == Some(id)
          && in_period(event.at)
        }),
        deviations: list.count(deviations, fn(row) { row.station == id }),
      )
    })

  Ok(Measures(
    period:,
    pieces: produced,
    demands: demand_measures,
    stations: station_measures,
    deviations:,
  ))
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

fn touches_of_reworks(
  reworks: List(#(String, Interval)),
  unit: String,
) -> List(Interval) {
  list.filter_map(reworks, fn(rework) {
    case rework.0 == unit {
      True -> Ok(rework.1)
      False -> Error(Nil)
    }
  })
}

const events_sql = "
select cast(strftime('%s', at) as integer), kind, piece_id,
       json_extract(payload, '$.station'), json_extract(payload, '$.from')
  from flow_event
 where kind in ('piece_pulled', 'piece_assembled', 'piece_paused',
                'piece_resumed', 'piece_put_in_blue_bin', 'piece_split',
                'piece_reached_production', 'kanban_sent', 'kanban_spent')
 order by at, id
"

const pieces_sql = "
select p.id, p.parent_id, p.demand_id,
       cast(strftime('%s', coalesce(p.entered_at, d.started_on)) as integer),
       cast(strftime('%s', p.produced_at) as integer)
  from piece p join demand d on d.id = p.demand_id
"

const deviations_sql = "
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
  decode.success(Event(at:, kind:, piece:, station:, from:))
}

fn piece_decoder() -> decode.Decoder(PieceRow) {
  use id <- decode.field(0, decode.string)
  use parent <- decode.field(1, decode.optional(decode.string))
  use demand <- decode.field(2, decode.string)
  use entered <- decode.field(3, decode.int)
  use produced <- decode.field(4, decode.optional(decode.int))
  decode.success(PieceRow(id:, parent:, demand:, entered:, produced:))
}

fn deviation_decoder() -> decode.Decoder(DeviationRow) {
  use at <- decode.field(0, decode.string)
  use rule <- decode.field(1, decode.string)
  use station <- decode.field(2, decode.string)
  use station_name <- decode.field(3, decode.string)
  use piece <- decode.field(4, decode.optional(decode.string))
  use reason <- decode.field(5, decode.string)
  decode.success(DeviationRow(
    at:,
    rule:,
    station:,
    station_name:,
    piece:,
    reason:,
  ))
}

// --- JSON -------------------------------------------------------------------

pub fn to_json(measures: Measures) -> json.Json {
  let pieces = measures.pieces
  json.object([
    #("from", json.string(measures.period.from)),
    #("to", json.string(measures.period.to)),
    #(
      "pieces",
      json.object([
        #("count", json.int(list.length(pieces))),
        ..spans_json(list.map(pieces, fn(piece) { piece.span }))
        |> list.append([
          #(
            "backlogTime",
            average_lead(
              list.filter_map(pieces, fn(piece) {
                option.to_result(piece.backlog, Nil)
              }),
            ),
          ),
        ])
      ]),
    ),
    #(
      "demands",
      json.array(measures.demands, fn(demand) {
        json.object([
          #("id", json.string(demand.id)),
          #("label", json.string(demand.label)),
          #("client", json.string(demand.client)),
          #("pieces", json.int(list.length(demand.pieces))),
          #(
            "demandLeadTime",
            json.nullable(demand.lead, fn(span) {
              duration(Some(lead(span)), Some(lead_working(span)))
            }),
          ),
          ..spans_json(list.map(demand.pieces, fn(piece) { piece.span }))
        ])
      }),
    ),
    #(
      "stations",
      json.array(measures.stations, fn(station) {
        let touch = list.fold(station.passes, 0, fn(t, span) { t + span.touch })
        let leads = list.fold(station.passes, 0, fn(t, span) { t + lead(span) })
        json.object([
          #("id", json.string(station.id)),
          #("name", json.string(station.name)),
          #("branch", json.nullable(station.branch, json.string)),
          #("position", json.int(station.position)),
          #("passes", json.int(list.length(station.passes))),
          #("stationLeadTime", average_lead(station.passes)),
          #("touchTime", average_touch(station.passes)),
          #("touchShare", case leads {
            0 -> json.null()
            _ ->
              json.float(hundredth(int.to_float(touch) /. int.to_float(leads)))
          }),
          #(
            "starvationTime",
            duration(Some(station.starvation), Some(station.starvation_working)),
          ),
          #("pulls", json.int(station.pulls)),
          #("deviations", json.int(station.deviations)),
        ])
      }),
    ),
    #(
      "deviations",
      json.object([
        #(
          "byRule",
          json.array(by_rule(measures.deviations), fn(row) {
            json.object([
              #("rule", json.string(row.0)),
              #("count", json.int(row.1)),
            ])
          }),
        ),
        #(
          "list",
          json.array(measures.deviations, fn(row) {
            json.object([
              #("at", json.string(row.at)),
              #("rule", json.string(row.rule)),
              #("station", json.string(row.station)),
              #("stationName", json.string(row.station_name)),
              #("piece", json.nullable(row.piece, json.string)),
              #("reason", json.string(row.reason)),
            ])
          }),
        ),
      ]),
    ),
  ])
}

fn spans_json(spans: List(Span)) -> List(#(String, json.Json)) {
  [
    #("leadTime", average_lead(spans)),
    #("touchTime", average_touch(spans)),
    #(
      "stagnationTime",
      average(spans, fn(span) { #(span.stagnation, span.stagnation_working) }),
    ),
  ]
}

fn average_lead(spans: List(Span)) -> json.Json {
  average(spans, fn(span) { #(lead(span), lead_working(span)) })
}

fn average_touch(spans: List(Span)) -> json.Json {
  average(spans, fn(span) { #(span.touch, span.touch) })
}

/// The average per Span of a measure in Calendar and Working Time, or null
/// when there is nothing to average.
fn average(spans: List(Span), measure: fn(Span) -> #(Int, Int)) -> json.Json {
  case list.length(spans) {
    0 -> json.null()
    count -> {
      let #(calendar, working) =
        list.fold(spans, #(0, 0), fn(total, span) {
          let #(c, w) = measure(span)
          #(total.0 + c, total.1 + w)
        })
      duration(Some(calendar / count), Some(working / count))
    }
  }
}

fn duration(calendar: Option(Int), working: Option(Int)) -> json.Json {
  let hours = fn(seconds) {
    json.float(hundredth(int.to_float(seconds) /. 3600.0))
  }
  json.object([
    #("calendar", json.nullable(calendar, hours)),
    #("working", json.nullable(working, hours)),
  ])
}

fn hundredth(value: Float) -> Float {
  int.to_float(float.round(value *. 100.0)) /. 100.0
}

fn by_rule(rows: List(DeviationRow)) -> List(#(String, Int)) {
  rows
  |> list.group(fn(row) { row.rule })
  |> dict.to_list
  |> list.map(fn(group) { #(group.0, list.length(group.1)) })
  |> list.sort(fn(a, b) { int.compare(b.1, a.1) })
}
