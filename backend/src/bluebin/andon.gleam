import bluebin/assignment
import bluebin/calendar.{type Calendar}
import bluebin/db
import bluebin/demand
import bluebin/measures
import bluebin/wire
import bluebin/wire_json
import gleam/dynamic/decode
import gleam/int
import gleam/json.{type Json}
import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/result
import sqlight

/// Computed on each read from the current state, the log and the Working
/// Calendar; nothing here is stored.
pub type Andon {
  /// A Team Member stopped the Work Station; its Team Leader closes it (F42).
  Stop(
    station_id: String,
    station: String,
    raised_by: Option(String),
    raised_at: String,
    team_leader_id: Option(String),
    team_leader: Option(String),
  )
  /// A Rework waits with no active Assignment for too long (F15).
  ReworkWaits(
    station_id: String,
    station: String,
    rework_id: String,
    piece: String,
    waiting: Int,
  )
}

/// An active Assignment with no event for more than one working day (F33).
pub type Stale {
  Stale(kind: String, id: String)
}

/// A Work Station that holds up the flow (F10, F29). `capacity` is the
/// average Touch Time of its last passes divided by its Team Members, in hours;
/// `slower` says it is above the Takt Time of the Line.
pub type Bottleneck {
  Bottleneck(
    station_id: String,
    capacity: Option(Float),
    slower: Bool,
    full_in_front: Bool,
  )
}

/// One hour of Working Time (F15).
const rework_wait_limit = 3600

pub fn current(
  connection: sqlight.Connection,
) -> Result(List(Andon), sqlight.Error) {
  use calendar <- result.try(calendar.load(connection))
  use now <- result.try(db.now(connection))
  andons(connection, calendar, now)
}

pub fn andons(
  connection: sqlight.Connection,
  calendar: Calendar,
  now: Int,
) -> Result(List(Andon), sqlight.Error) {
  use stops <- result.try(
    sqlight.query(
      "select a.station_id, w.name,
            (select pe.name from team_member pe where pe.id = a.raised_by),
            a.raised_at, w.team_leader,
            (select pe.name from team_member pe where pe.id = w.team_leader)
       from andon a
       join work_station w on w.id = a.station_id
      where a.closed_at is null
      order by a.raised_at, a.id",
      on: connection,
      with: [],
      expecting: {
        use station_id <- decode.field(0, decode.string)
        use station <- decode.field(1, decode.string)
        use raised_by <- decode.field(2, decode.optional(decode.string))
        use raised_at <- decode.field(3, decode.string)
        use team_leader_id <- decode.field(4, decode.optional(decode.string))
        use team_leader <- decode.field(5, decode.optional(decode.string))
        decode.success(Stop(
          station_id:,
          station:,
          raised_by:,
          raised_at:,
          team_leader_id:,
          team_leader:,
        ))
      },
    ),
  )
  use waiting <- result.try(
    sqlight.query(
      "select r.station_id, w.name, r.id, p.reference,
            cast(strftime('%s', r.opened_at) as integer)
       from rework r
       join piece p on p.id = r.piece_id
       join work_station w on w.id = r.station_id
      where r.closed_at is null
        and (r.assignee is null or r.started_at is null)
      order by r.opened_at, r.rowid",
      on: connection,
      with: [],
      expecting: {
        use station_id <- decode.field(0, decode.string)
        use station <- decode.field(1, decode.string)
        use rework_id <- decode.field(2, decode.string)
        use piece <- decode.field(3, decode.string)
        use opened <- decode.field(4, decode.int)
        decode.success(ReworkWaits(
          station_id:,
          station:,
          rework_id:,
          piece:,
          waiting: calendar.working_seconds(calendar, opened, now),
        ))
      },
    ),
  )
  let late =
    list.filter(waiting, fn(andon) {
      case andon {
        ReworkWaits(waiting:, ..) -> waiting >= rework_wait_limit
        Stop(..) -> False
      }
    })
  Ok(list.append(stops, late))
}

/// The last activity of a Piece in hand is its newest event or state change;
/// of a Rework, the start of its repair.
pub fn stale(
  connection: sqlight.Connection,
  calendar: Calendar,
  now: Int,
) -> Result(#(List(Stale), Int), sqlight.Error) {
  use active <- result.try(
    sqlight.query(
      "select 'piece', p.id,
            cast(strftime('%s', max(coalesce(p.since, ''),
              coalesce((select max(e.at) from flow_event e
                         where e.piece_id = p.id), ''))) as integer)
       from piece p
      where p.state = 'in_flow' and p.assignee is not null
     union all
     select 'rework', r.id, cast(strftime('%s', r.started_at) as integer)
       from rework r
      where r.closed_at is null and r.started_at is not null
        and r.assignee is not null",
      on: connection,
      with: [],
      expecting: {
        use kind <- decode.field(0, decode.string)
        use id <- decode.field(1, decode.string)
        use last <- decode.field(2, decode.optional(decode.int))
        decode.success(#(kind, id, last))
      },
    ),
  )
  let working_day = { calendar.end - calendar.start } * 60
  let stale =
    list.filter_map(active, fn(one) {
      case one.2 {
        Some(last) ->
          case calendar.working_seconds(calendar, last, now) > working_day {
            True -> Ok(Stale(kind: one.0, id: one.1))
            False -> Error(Nil)
          }
        None -> Error(Nil)
      }
    })
  Ok(#(stale, list.length(active)))
}

/// Capacity reads the passes that ended in the last 7 days.
pub fn bottlenecks(
  connection: sqlight.Connection,
  takt_hours: Float,
) -> Result(List(Bottleneck), sqlight.Error) {
  use stations <- result.try(assignment.stations(connection))
  use period <- result.try(
    sqlight.query(
      "select date('now', '-6 day'), date('now')",
      on: connection,
      with: [],
      expecting: {
        use from <- decode.field(0, decode.string)
        use to <- decode.field(1, decode.string)
        decode.success(#(from, to))
      },
    ),
  )
  let measured = case period {
    [#(from, to), ..] ->
      measures.load(connection, from, to)
      |> result.map(fn(found) { found.stations })
      |> result.unwrap([])
    [] -> []
  }
  stations
  |> list.filter_map(fn(station) {
    let capacity =
      measured
      |> list.find(fn(one) { one.id == station.id })
      |> result.try(fn(one) {
        capacity_hours(one, list.length(station.team_members))
      })
      |> option.from_result
    let slower = case capacity {
      Some(hours) -> takt_hours >. 0.0 && hours >. takt_hours
      None -> False
    }
    let full_in_front = assignment.in_front_full(station, stations)
    case slower || full_in_front {
      True ->
        Ok(Bottleneck(
          station_id: station.id,
          capacity:,
          slower:,
          full_in_front:,
        ))
      False -> Error(Nil)
    }
  })
  |> Ok
}

pub fn capacity_hours(
  station: measures.StationMeasure,
  team_members: Int,
) -> Result(Float, Nil) {
  case station.passes, team_members {
    [], _ | _, 0 -> Error(Nil)
    passes, _ -> {
      let touch = list.fold(passes, 0, fn(total, span) { total + span.touch })
      Ok(
        int.to_float(touch)
        /. int.to_float(list.length(passes))
        /. 3600.0
        /. int.to_float(team_members),
      )
    }
  }
}

/// The Andons a Team Member sees on their own screen: those of their Work Stations
/// only (DESIGN.md R2).
pub fn of_stations(andons: List(Andon), stations: List(String)) -> List(Andon) {
  list.filter(andons, fn(andon) { list.contains(stations, andon.station_id) })
}

pub fn andons_json(andons: List(Andon)) -> Json {
  json.array(andons, fn(andon) { wire_andon(andon) |> wire_json.andon })
}

pub fn wire_andon(andon: Andon) -> wire.Andon {
  case andon {
    Stop(
      station_id:,
      station:,
      raised_by:,
      raised_at:,
      team_leader_id:,
      team_leader:,
    ) ->
      wire.StopAndon(
        station: station_id,
        station_name: station,
        raised_by:,
        raised_at:,
        team_leader_id:,
        team_leader:,
      )
    ReworkWaits(station_id:, station:, rework_id:, piece:, waiting:) ->
      wire.ReworkWaitsAndon(
        station: station_id,
        station_name: station,
        rework: rework_id,
        piece:,
        waiting_hours: hours(waiting),
      )
  }
}

pub fn wire_stale(stale: Stale) -> wire.StaleAssignment {
  // `stale` gives only the kinds "piece" and "rework".
  let kind = case stale.kind {
    "rework" -> wire.ReworkKind
    _ -> wire.PieceKind
  }
  wire.StaleAssignment(kind:, id: stale.id)
}

pub fn wire_bottleneck(bottleneck: Bottleneck) -> wire.Bottleneck {
  wire.Bottleneck(
    station: bottleneck.station_id,
    capacity_hours: option.map(bottleneck.capacity, demand.round_to_tenth),
    slower: bottleneck.slower,
    full_in_front: bottleneck.full_in_front,
  )
}

fn hours(seconds: Int) -> Float {
  demand.round_to_tenth(int.to_float(seconds) /. 3600.0)
}
