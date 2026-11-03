import gleam/dynamic/decode
import gleam/json.{type Json}
import gleam/list
import gleam/option.{type Option}
import gleam/result
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

pub type Bin {
  Bin(
    station_id: String,
    slot: Int,
    piece: Option(String),
    demand: Option(String),
  )
}

pub type Member {
  Member(station_id: String, name: String, busy: Bool)
}

pub type InProgress {
  InProgress(
    station_id: String,
    piece: String,
    demand: String,
    person: Option(String),
  )
}

pub type Kanbans {
  Kanbans(station_id: String, count: Int)
}

pub type Rework {
  Rework(station_id: String, piece: String, description: String)
}

/// The whole Value Stream, read in six small queries and assembled here. The
/// shape stays flat so a screen can be rebuilt from one payload (F27).
pub fn load(
  connection: sqlight.Connection,
) -> Result(Json, sqlight.Error) {
  use stations <- result.try(query_stations(connection))
  use bins <- result.try(query_bins(connection))
  use members <- result.try(query_members(connection))
  use in_progress <- result.try(query_in_progress(connection))
  use kanbans <- result.try(query_kanbans(connection))
  use rework <- result.try(query_rework(connection))

  stations
  |> list.map(fn(station) {
    station_json(station, bins, members, in_progress, kanbans, rework)
  })
  |> json.preprocessed_array
  |> Ok
}

fn station_json(
  station: Station,
  bins: List(Bin),
  members: List(Member),
  in_progress: List(InProgress),
  kanbans: List(Kanbans),
  rework: List(Rework),
) -> Json {
  let station_bins =
    bins
    |> list.filter(fn(bin) { bin.station_id == station.id })
    |> list.map(fn(bin) {
      json.object([
        #("slot", json.int(bin.slot)),
        #("piece", json.nullable(bin.piece, json.string)),
        #("demand", json.nullable(bin.demand, json.string)),
      ])
    })

  let station_members =
    members
    |> list.filter(fn(member) { member.station_id == station.id })
    |> list.map(fn(member) {
      json.object([
        #("name", json.string(member.name)),
        #("busy", json.bool(member.busy)),
      ])
    })

  let station_pieces =
    in_progress
    |> list.filter(fn(piece) { piece.station_id == station.id })
    |> list.map(fn(piece) {
      json.object([
        #("piece", json.string(piece.piece)),
        #("demand", json.string(piece.demand)),
        #("person", json.nullable(piece.person, json.string)),
      ])
    })

  let station_rework =
    rework
    |> list.filter(fn(item) { item.station_id == station.id })
    |> list.map(fn(item) {
      json.object([
        #("piece", json.string(item.piece)),
        #("description", json.string(item.description)),
      ])
    })

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
    #("people", json.preprocessed_array(station_members)),
    #("inProgress", json.preprocessed_array(station_pieces)),
    #("rework", json.preprocessed_array(station_rework)),
    #("kanbans", json.int(kanban_count)),
  ])
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
            (select p.name from person p where p.id = w.team_leader)
     from work_station w
     order by w.position, w.branch",
    on: connection,
    with: [],
    expecting: decoder,
  )
}

fn query_bins(
  connection: sqlight.Connection,
) -> Result(List(Bin), sqlight.Error) {
  let decoder = {
    use station_id <- decode.field(0, decode.string)
    use slot <- decode.field(1, decode.int)
    use piece <- decode.field(2, decode.optional(decode.string))
    use demand <- decode.field(3, decode.optional(decode.string))
    decode.success(Bin(station_id:, slot:, piece:, demand:))
  }
  sqlight.query(
    "select b.station_id, b.slot, p.reference, d.label
     from blue_bin b
     left join piece p on p.id = b.piece_id
     left join demand d on d.id = p.demand_id
     order by b.station_id, b.slot",
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
    use name <- decode.field(1, decode.string)
    use busy <- decode.field(2, decode.int)
    decode.success(Member(station_id:, name:, busy: busy > 0))
  }
  sqlight.query(
    "select sp.station_id, p.name,
            (select count(*) from piece pi
             where pi.assignee = p.id and pi.station_id = sp.station_id)
     from station_person sp
     join person p on p.id = sp.person_id
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
    use piece <- decode.field(1, decode.string)
    use demand <- decode.field(2, decode.string)
    use person <- decode.field(3, decode.optional(decode.string))
    decode.success(InProgress(station_id:, piece:, demand:, person:))
  }
  sqlight.query(
    "select p.station_id, p.reference, d.label,
            (select pe.name from person pe where pe.id = p.assignee)
     from piece p
     join demand d on d.id = p.demand_id
     where p.station_id is not null and p.state = 'in_flow'
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
    use piece <- decode.field(1, decode.string)
    use description <- decode.field(2, decode.string)
    decode.success(Rework(station_id:, piece:, description:))
  }
  sqlight.query(
    "select r.station_id, p.reference, r.description
     from rework r
     join piece p on p.id = r.piece_id
     where r.closed_at is null
     order by r.opened_at",
    on: connection,
    with: [],
    expecting: decoder,
  )
}
