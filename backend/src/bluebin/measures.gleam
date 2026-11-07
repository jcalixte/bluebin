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
    /// Why a Piece paused: `rework` or `held` (DESIGN.md R11). None before the
    /// cause was recorded, which reads as `held`.
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
          Some("rework"), _ | _, Some(_) -> open
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
    "piece_split", _ | "piece_reached_production", _ ->
      leave_any(state, unit, at)
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
  let held =
    clip(pass.held, pass.start, filled)
    |> list.fold(0, fn(total, one) {
      total + calendar.working_seconds(calendar, one.0, one.1)
    })
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
  use #(calendar, events, pieces, children, passes) <- result.try(load_passes(
    connection,
    now,
  ))
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
  use stops <- result.try(
    query(
      connection,
      "select station_id, cast(strftime('%s', raised_at) as integer),
            cast(strftime('%s', coalesce(closed_at, 'now')) as integer)
       from andon",
      [],
      {
        use station <- decode.field(0, decode.string)
        use start <- decode.field(1, decode.int)
        use end <- decode.field(2, decode.int)
        decode.success(#(station, #(start, end)))
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
  use delivery_rows <- result.try(
    query(connection, on_time_sql, [sqlight.text(from), sqlight.text(to)], {
      use delivered <- decode.field(0, decode.int)
      use on_time <- decode.field(1, decode.int)
      decode.success(#(delivered, on_time))
    }),
  )
  let #(delivered, on_time) = case delivery_rows {
    [row, ..] -> row
    [] -> #(0, 0)
  }
  use deviations <- result.try(query(
    connection,
    deviations_sql,
    [sqlight.int(period.start), sqlight.int(period.end)],
    deviation_decoder(),
  ))

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
  let in_measured = fn(intervals) {
    let intervals = clip(intervals, period.start, int.min(period.end, now))
    #(
      list.fold(intervals, 0, fn(total, one) { total + one.1 - one.0 }),
      list.fold(intervals, 0, fn(total, one) {
        total + calendar.working_seconds(calendar, one.0, one.1)
      }),
    )
  }
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
      let replenishments =
        list.filter_map(passes, fn(pass) {
          case pass.station == id {
            True ->
              replenishment(calendar, pass)
              |> result.try(fn(one) {
                case in_period(one.filled) {
                  True -> Ok(one)
                  False -> Error(Nil)
                }
              })
            False -> Error(Nil)
          }
        })
      let #(starvation, starvation_working) =
        dict.get(held, id) |> result.unwrap([]) |> in_measured
      let station_stops =
        list.filter_map(stops, fn(stop) {
          case stop.0 == id {
            True -> Ok(stop.1)
            False -> Error(Nil)
          }
        })
      let #(andon, andon_working) = in_measured(station_stops)
      StationMeasure(
        id:,
        name:,
        branch:,
        position:,
        passes: station_passes,
        replenishments:,
        starvation:,
        starvation_working:,
        andon:,
        andon_working:,
        andons: list.count(station_stops, fn(stop) { in_period(stop.0) }),
        pulls: list.count(events, fn(event) {
          { event.kind == "piece_pulled" || event.kind == "piece_assembled" }
          && event.station == Some(id)
          && in_period(event.at)
        }),
        deviations: list.count(deviations, fn(row) { row.station == id }),
      )
    })

  let #(andon, andon_working) =
    stops |> list.map(fn(stop) { stop.1 }) |> union |> in_measured
  Ok(Measures(
    period:,
    pieces: produced,
    demands: demand_measures,
    stations: station_measures,
    deviations:,
    andon:,
    andon_working:,
    delivered:,
    on_time:,
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
  use now <- result.try(query(
    connection,
    "select cast(strftime('%s', 'now') as integer)",
    [],
    decode.at([0], decode.int),
  ))
  use #(calendar, _, _, _, passes) <- result.try(load_passes(
    connection,
    list.first(now) |> result.unwrap(0),
  ))
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

const events_sql =
  "
select cast(strftime('%s', at) as integer), kind, piece_id,
       json_extract(payload, '$.station'), json_extract(payload, '$.from'),
       json_extract(payload, '$.cause')
  from flow_event
 where kind in ('piece_pulled', 'piece_assembled', 'piece_paused',
                'piece_resumed', 'piece_put_in_blue_bin', 'piece_split',
                'piece_reached_production', 'kanban_sent', 'kanban_spent')
 order by at, id
"

const pieces_sql =
  "
select p.id, p.parent_id, p.demand_id,
       cast(strftime('%s', coalesce(p.entered_at, d.started_on)) as integer),
       cast(strftime('%s', p.produced_at) as integer)
  from piece p join demand d on d.id = p.demand_id
"

/// A Demand is delivered on the day of its last Piece in production.
const on_time_sql =
  "
select count(*), coalesce(sum(delivered_on <= due_on), 0)
  from (select d.due_on,
               (select date(max(p.produced_at)) from piece p
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
          #("replenishmentTime", p85_duration(station.replenishments)),
          #("touchShare", case leads {
            0 -> json.null()
            _ ->
              json.float(hundredth(int.to_float(touch) /. int.to_float(leads)))
          }),
          #(
            "starvationTime",
            duration(Some(station.starvation), Some(station.starvation_working)),
          ),
          #(
            "andonTime",
            duration(Some(station.andon), Some(station.andon_working)),
          ),
          #("andons", json.int(station.andons)),
          #("pulls", json.int(station.pulls)),
          #("deviations", json.int(station.deviations)),
        ])
      }),
    ),
    #("andonTime", duration(Some(measures.andon), Some(measures.andon_working))),
    #(
      "onTime",
      json.object([
        #("delivered", json.int(measures.delivered)),
        #("onTime", json.int(measures.on_time)),
      ]),
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

/// p85 Replenishment Time, or null under `min_passes` passes (F54).
fn p85_duration(replenishments: List(Replenishment)) -> json.Json {
  case list.length(replenishments) >= min_passes {
    False -> json.null()
    True ->
      duration(
        p85(list.map(replenishments, fn(one) { one.calendar }))
          |> option.from_result,
        p85(list.map(replenishments, fn(one) { one.working }))
          |> option.from_result,
      )
  }
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
