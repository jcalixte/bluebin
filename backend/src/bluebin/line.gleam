import gleam/bool
import gleam/dynamic/decode
import gleam/int
import gleam/json.{type Json}
import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/result
import gleam/string
import sqlight

pub type Station {
  Station(
    id: String,
    name: String,
    position: Int,
    branch: Option(String),
    blue_bins: Int,
    team_leader: Option(String),
  )
}

pub type Parked {
  Parked(
    station_id: String,
    id: String,
    reference: String,
    demand: String,
    /// Comma-separated Branches that already took their Sub-Piece at a Split.
    pulled_by: Option(String),
  )
}

pub type Member {
  Member(station_id: String, id: String, name: String, busy: Bool)
}

pub type InProgress {
  InProgress(
    station_id: String,
    id: String,
    piece: String,
    demand: String,
    team_member: Option(String),
    team_member_id: Option(String),
    paused: Bool,
  )
}

pub type Kanbans {
  Kanbans(station_id: String, count: Int)
}

pub type Rework {
  Rework(
    station_id: String,
    id: String,
    piece: String,
    description: String,
    found_by: String,
    assignee: Option(String),
    assignee_id: Option(String),
  )
}

pub type Quality {
  Quality(station_id: String, passes: Int, defects: Int, rework_hours: Float)
}

pub type Deviation {
  Deviation(
    station_id: String,
    rule: String,
    piece: Option(String),
    reason: String,
    at: String,
  )
}

pub fn load(connection: sqlight.Connection) -> Result(Json, sqlight.Error) {
  use stations <- result.try(query_stations(connection))
  use parked <- result.try(query_parked(connection))
  use members <- result.try(query_members(connection))
  use in_progress <- result.try(query_in_progress(connection))
  use kanbans <- result.try(query_kanbans(connection))
  use rework <- result.try(query_rework(connection))
  use quality <- result.try(query_quality(connection))
  use deviations <- result.try(query_deviations(connection))

  stations
  |> list.map(fn(station) {
    station_json(
      station,
      parked,
      members,
      in_progress,
      kanbans,
      rework,
      quality,
      deviations,
    )
  })
  |> json.preprocessed_array
  |> Ok
}

fn station_json(
  station: Station,
  parked: List(Parked),
  members: List(Member),
  in_progress: List(InProgress),
  kanbans: List(Kanbans),
  rework: List(Rework),
  quality: List(Quality),
  deviations: List(Deviation),
) -> Json {
  let waiting =
    parked |> list.filter(fn(piece) { piece.station_id == station.id })
  let #(in_bins, over) = list.split(waiting, station.blue_bins)
  let station_bins = bin_rows(1, station.blue_bins, in_bins)
  let station_overflow =
    over
    |> list.map(fn(piece) {
      json.object([
        #("id", json.string(piece.id)),
        #("piece", json.string(piece.reference)),
        #("demand", json.string(piece.demand)),
      ])
    })

  let station_members =
    members
    |> list.filter(fn(member) { member.station_id == station.id })
    |> list.map(fn(member) {
      json.object([
        #("id", json.string(member.id)),
        #("name", json.string(member.name)),
        #("busy", json.bool(member.busy)),
      ])
    })

  let station_pieces =
    in_progress
    |> list.filter(fn(piece) { piece.station_id == station.id })
    |> list.map(fn(piece) {
      json.object([
        #("id", json.string(piece.id)),
        #("piece", json.string(piece.piece)),
        #("demand", json.string(piece.demand)),
        #("teamMember", json.nullable(piece.team_member, json.string)),
        #("teamMemberId", json.nullable(piece.team_member_id, json.string)),
        #("paused", json.bool(piece.paused)),
      ])
    })

  let station_rework =
    rework
    |> list.filter(fn(item) { item.station_id == station.id })
    |> list.map(fn(item) {
      json.object([
        #("id", json.string(item.id)),
        #("piece", json.string(item.piece)),
        #("description", json.string(item.description)),
        #("foundBy", json.string(item.found_by)),
        #("assignee", json.nullable(item.assignee, json.string)),
        #("assigneeId", json.nullable(item.assignee_id, json.string)),
      ])
    })

  let station_deviations =
    deviations
    |> list.filter(fn(item) { item.station_id == station.id })
    |> list.take(3)
    |> list.map(fn(item) {
      json.object([
        #("rule", json.string(item.rule)),
        #("piece", json.nullable(item.piece, json.string)),
        #("reason", json.string(item.reason)),
        #("at", json.string(item.at)),
      ])
    })

  let station_quality =
    quality |> list.find(fn(item) { item.station_id == station.id })

  let first_pass_yield = case station_quality {
    Ok(Quality(passes: passes, defects: defects, ..)) if passes > 0 ->
      Some(int.to_float(int.max(passes - defects, 0)) /. int.to_float(passes))
    _ -> None
  }
  let rework_hours = case station_quality {
    Ok(one) -> one.rework_hours
    Error(_) -> 0.0
  }

  let kanban_count =
    kanbans
    |> list.find(fn(item) { item.station_id == station.id })
    |> result.map(fn(item) { item.count })
    |> result.unwrap(0)

  json.object([
    #("id", json.string(station.id)),
    #("name", json.string(station.name)),
    #("position", json.int(station.position)),
    #("branch", json.nullable(station.branch, json.string)),
    #("blueBinCount", json.int(station.blue_bins)),
    #("teamLeader", json.nullable(station.team_leader, json.string)),
    #("blueBins", json.preprocessed_array(station_bins)),
    #("overflow", json.preprocessed_array(station_overflow)),
    #("teamMembers", json.preprocessed_array(station_members)),
    #("inProgress", json.preprocessed_array(station_pieces)),
    #("rework", json.preprocessed_array(station_rework)),
    #("firstPassYield", json.nullable(first_pass_yield, json.float)),
    #("reworkHours", json.float(rework_hours)),
    #("deviations", json.preprocessed_array(station_deviations)),
    #("kanbans", json.int(kanban_count)),
  ])
}

fn bin_rows(slot: Int, last: Int, pieces: List(Parked)) -> List(Json) {
  case slot > last {
    True -> []
    False -> {
      let #(here, rest) = case pieces {
        [first, ..rest] -> #(Some(first), rest)
        [] -> #(None, [])
      }
      let row =
        json.object([
          #("slot", json.int(slot)),
          #(
            "id",
            json.nullable(option.map(here, fn(one) { one.id }), json.string),
          ),
          #(
            "piece",
            json.nullable(
              option.map(here, fn(one) { one.reference }),
              json.string,
            ),
          ),
          #(
            "demand",
            json.nullable(option.map(here, fn(one) { one.demand }), json.string),
          ),
          #(
            "pulledBy",
            json.nullable(
              option.then(here, fn(one) { one.pulled_by }),
              json.string,
            ),
          ),
        ])
      [row, ..bin_rows(slot + 1, last, rest)]
    }
  }
}

fn query_stations(
  connection: sqlight.Connection,
) -> Result(List(Station), sqlight.Error) {
  let decoder = {
    use id <- decode.field(0, decode.string)
    use name <- decode.field(1, decode.string)
    use position <- decode.field(2, decode.int)
    use branch <- decode.field(3, decode.optional(decode.string))
    use blue_bins <- decode.field(4, decode.int)
    use team_leader <- decode.field(5, decode.optional(decode.string))
    decode.success(Station(
      id:,
      name:,
      position:,
      branch:,
      blue_bins:,
      team_leader:,
    ))
  }
  sqlight.query(
    "select w.id, w.name, w.position, w.branch, w.blue_bins,
            (select p.name from team_member p where p.id = w.team_leader)
     from work_station w
     order by w.position, w.branch",
    on: connection,
    with: [],
    expecting: decoder,
  )
}

fn query_parked(
  connection: sqlight.Connection,
) -> Result(List(Parked), sqlight.Error) {
  let decoder = {
    use station_id <- decode.field(0, decode.string)
    use id <- decode.field(1, decode.string)
    use reference <- decode.field(2, decode.string)
    use demand <- decode.field(3, decode.string)
    use pulled_by <- decode.field(4, decode.optional(decode.string))
    decode.success(Parked(station_id:, id:, reference:, demand:, pulled_by:))
  }
  sqlight.query(
    "select p.station_id, p.id, p.reference, d.label,
            (select group_concat(s.branch, ', ') from piece s
             where s.parent_id = p.id)
     from piece p
     join demand d on d.id = p.demand_id
     where p.state = 'in_bin' and p.station_id is not null
     order by p.station_id, p.since, p.rowid",
    on: connection,
    with: [],
    expecting: decoder,
  )
}

fn query_members(
  connection: sqlight.Connection,
) -> Result(List(Member), sqlight.Error) {
  let decoder = {
    use station_id <- decode.field(0, decode.string)
    use id <- decode.field(1, decode.string)
    use name <- decode.field(2, decode.string)
    use busy <- decode.field(3, decode.int)
    decode.success(Member(station_id:, id:, name:, busy: busy > 0))
  }
  sqlight.query(
    "select sp.station_id, p.id, p.name,
            (select count(*) from piece pi
             where pi.assignee = p.id and pi.station_id = sp.station_id)
     from station_team_member sp
     join team_member p on p.id = sp.team_member_id
     order by sp.station_id, p.name",
    on: connection,
    with: [],
    expecting: decoder,
  )
}

fn query_in_progress(
  connection: sqlight.Connection,
) -> Result(List(InProgress), sqlight.Error) {
  let decoder = {
    use station_id <- decode.field(0, decode.string)
    use id <- decode.field(1, decode.string)
    use piece <- decode.field(2, decode.string)
    use demand <- decode.field(3, decode.string)
    use team_member <- decode.field(4, decode.optional(decode.string))
    use paused <- decode.field(5, decode.int)
    use team_member_id <- decode.field(6, decode.optional(decode.string))
    decode.success(InProgress(
      station_id:,
      id:,
      piece:,
      demand:,
      team_member:,
      team_member_id:,
      paused: paused > 0,
    ))
  }
  sqlight.query(
    "select p.station_id, p.id, p.reference, d.label,
            (select pe.name from team_member pe where pe.id = p.assignee),
            p.state = 'paused', p.assignee
     from piece p
     join demand d on d.id = p.demand_id
     where p.station_id is not null and p.state in ('in_flow', 'paused')
     order by p.station_id, p.reference",
    on: connection,
    with: [],
    expecting: decoder,
  )
}

fn query_kanbans(
  connection: sqlight.Connection,
) -> Result(List(Kanbans), sqlight.Error) {
  let decoder = {
    use station_id <- decode.field(0, decode.string)
    use count <- decode.field(1, decode.int)
    decode.success(Kanbans(station_id:, count:))
  }
  sqlight.query(
    "select station_id, count(*) from kanban group by station_id",
    on: connection,
    with: [],
    expecting: decoder,
  )
}

fn query_rework(
  connection: sqlight.Connection,
) -> Result(List(Rework), sqlight.Error) {
  let decoder = {
    use station_id <- decode.field(0, decode.string)
    use id <- decode.field(1, decode.string)
    use piece <- decode.field(2, decode.string)
    use description <- decode.field(3, decode.string)
    use found_by <- decode.field(4, decode.string)
    use assignee <- decode.field(5, decode.optional(decode.string))
    use assignee_id <- decode.field(6, decode.optional(decode.string))
    decode.success(Rework(
      station_id:,
      id:,
      piece:,
      description:,
      found_by:,
      assignee:,
      assignee_id:,
    ))
  }
  sqlight.query(
    "select r.station_id, r.id, p.reference, r.description,
            coalesce((select w.name from work_station w where w.id = r.raised_by),
                     'downstream'),
            (select pe.name from team_member pe where pe.id = r.assignee),
            r.assignee
     from rework r
     join piece p on p.id = r.piece_id
     where r.closed_at is null
     order by r.opened_at",
    on: connection,
    with: [],
    expecting: decoder,
  )
}

fn query_quality(
  connection: sqlight.Connection,
) -> Result(List(Quality), sqlight.Error) {
  let decoder = {
    use station_id <- decode.field(0, decode.string)
    use passes <- decode.field(1, decode.int)
    use defects <- decode.field(2, decode.int)
    use rework_hours <- decode.field(3, decode.float)
    decode.success(Quality(station_id:, passes:, defects:, rework_hours:))
  }
  sqlight.query(
    "select w.id,
            (select count(*) from piece_pass pp where pp.station_id = w.id),
            (select count(distinct r.piece_id) from rework r
              where r.station_id = w.id),
            (select coalesce(round(sum(
               (julianday(coalesce(r.closed_at,
                                   strftime('%Y-%m-%dT%H:%M:%SZ', 'now')))
                - julianday(r.started_at)) * 24.0), 2), 0.0)
               from rework r
              where r.station_id = w.id and r.started_at is not null)
     from work_station w",
    on: connection,
    with: [],
    expecting: decoder,
  )
}

fn query_deviations(
  connection: sqlight.Connection,
) -> Result(List(Deviation), sqlight.Error) {
  let decoder = {
    use station_id <- decode.field(0, decode.string)
    use rule <- decode.field(1, decode.string)
    use piece <- decode.field(2, decode.optional(decode.string))
    use reason <- decode.field(3, decode.string)
    use at <- decode.field(4, decode.string)
    decode.success(Deviation(station_id:, rule:, piece:, reason:, at:))
  }
  sqlight.query(
    "select v.station_id, v.rule,
            (select p.reference from piece p where p.id = v.piece_id),
            v.reason, v.at
     from deviation v
     order by v.at desc, v.id desc
     limit 50",
    on: connection,
    with: [],
    expecting: decoder,
  )
}

pub type Step {
  Step(position: Int, name: String)
}

pub type RenameError {
  EmptyName
  NameTooLong
  UnknownStep
  StoreFailed
}

/// The longest step name the wall-TV column layout holds without breaking.
pub const max_name_length = 40

pub fn list_steps(
  connection: sqlight.Connection,
) -> Result(List(Step), sqlight.Error) {
  let decoder = {
    use position <- decode.field(0, decode.int)
    use name <- decode.field(1, decode.string)
    decode.success(Step(position:, name:))
  }
  sqlight.query(
    "select position, name from line_step order by position",
    on: connection,
    with: [],
    expecting: decoder,
  )
}

pub fn steps_json(steps: List(Step)) -> Json {
  json.array(steps, fn(step) {
    json.object([
      #("position", json.int(step.position)),
      #("name", json.string(step.name)),
    ])
  })
}

pub fn rename_step(
  connection: sqlight.Connection,
  position: Int,
  name: String,
) -> Result(Step, RenameError) {
  let trimmed = string.trim(name)
  use <- bool.guard(trimmed == "", Error(EmptyName))
  use <- bool.guard(
    string.length(trimmed) > max_name_length,
    Error(NameTooLong),
  )

  let update =
    sqlight.query(
      "update line_step
       set name = ?, renamed_at = strftime('%Y-%m-%dT%H:%M:%SZ', 'now')
       where position = ?
       returning position, name",
      on: connection,
      with: [sqlight.text(trimmed), sqlight.int(position)],
      expecting: {
        use position <- decode.field(0, decode.int)
        use name <- decode.field(1, decode.string)
        decode.success(Step(position:, name:))
      },
    )

  case update {
    Error(_) -> Error(StoreFailed)
    Ok([]) -> Error(UnknownStep)
    Ok([step, ..]) -> {
      let event =
        sqlight.query(
          "insert into flow_event (kind, payload) values ('step_renamed', ?)
           returning id",
          on: connection,
          with: [sqlight.text(trimmed)],
          expecting: decode.at([0], decode.int),
        )
      case event {
        Ok(_) -> Ok(step)
        Error(_) -> Error(StoreFailed)
      }
    }
  }
}
