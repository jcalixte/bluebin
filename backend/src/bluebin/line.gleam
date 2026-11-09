import bluebin/db
import bluebin/text
import bluebin/wire
import gleam/dict.{type Dict}
import gleam/dynamic/decode
import gleam/int
import gleam/list
import gleam/option.{type Option, None, Some}
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
    under_rework: Bool,
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
    found_by_id: Option(String),
    assignee: Option(String),
    assignee_id: Option(String),
  )
}

/// A Team Member on a Rework's Piece: one who helps it, or one who can.
pub type Helper {
  Helper(rework_id: String, piece_id: String, id: String, name: String)
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

pub fn load(
  connection: sqlight.Connection,
) -> Result(List(wire.WorkStation), sqlight.Error) {
  use stations <- result.try(query_stations(connection))
  use parked <- result.try(query_parked(connection))
  use members <- result.try(query_members(connection))
  use in_progress <- result.try(query_in_progress(connection))
  use kanbans <- result.try(query_kanbans(connection))
  use rework <- result.try(query_rework(connection))
  use helpers <- result.try(query_helpers(connection, helpers_sql))
  use can_help <- result.try(query_helpers(connection, can_help_sql))
  use quality <- result.try(query_quality(connection))
  use deviations <- result.try(query_deviations(connection))

  let rows =
    Rows(
      parked: by_station(parked, fn(one) { one.station_id }),
      members: by_station(members, fn(one) { one.station_id }),
      in_progress: by_station(in_progress, fn(one) { one.station_id }),
      kanbans: list.map(kanbans, fn(one) { #(one.station_id, one.count) })
        |> dict.from_list,
      rework: by_station(rework, fn(one) { one.station_id }),
      helpers_of_rework: by_station(helpers, fn(one) { one.rework_id }),
      helpers_of_piece: by_station(helpers, fn(one) { one.piece_id }),
      can_help: by_station(can_help, fn(one) { one.rework_id }),
      quality: list.map(quality, fn(one) { #(one.station_id, one) })
        |> dict.from_list,
      deviations: by_station(deviations, fn(one) { one.station_id }),
    )
  Ok(list.map(stations, wire_station(_, rows)))
}

/// The rows of every Work Station, by its id.
type Rows {
  Rows(
    parked: Dict(String, List(Parked)),
    members: Dict(String, List(Member)),
    in_progress: Dict(String, List(InProgress)),
    kanbans: Dict(String, Int),
    rework: Dict(String, List(Rework)),
    helpers_of_rework: Dict(String, List(Helper)),
    helpers_of_piece: Dict(String, List(Helper)),
    can_help: Dict(String, List(Helper)),
    quality: Dict(String, Quality),
    deviations: Dict(String, List(Deviation)),
  )
}

/// Keeps the order of `rows` within each Work Station.
fn by_station(
  rows: List(a),
  station_id: fn(a) -> String,
) -> Dict(String, List(a)) {
  list.fold_right(rows, dict.new(), fn(groups, row) {
    dict.upsert(groups, station_id(row), fn(found) {
      [row, ..option.unwrap(found, [])]
    })
  })
}

fn of(groups: Dict(String, List(a)), station: Station) -> List(a) {
  rows_of(groups, station.id)
}

fn rows_of(groups: Dict(String, List(a)), key: String) -> List(a) {
  dict.get(groups, key) |> result.unwrap([])
}

fn wire_station(station: Station, rows: Rows) -> wire.WorkStation {
  let #(in_bins, over) = list.split(of(rows.parked, station), station.blue_bins)
  let quality = dict.get(rows.quality, station.id)

  let first_pass_yield = case quality {
    Ok(Quality(passes: passes, defects: defects, ..)) if passes > 0 ->
      Some(int.to_float(int.max(passes - defects, 0)) /. int.to_float(passes))
    _ -> None
  }
  let rework_hours = case quality {
    Ok(one) -> one.rework_hours
    Error(_) -> 0.0
  }

  wire.WorkStation(
    id: station.id,
    name: station.name,
    position: station.position,
    branch: station.branch,
    blue_bin_count: station.blue_bins,
    team_leader: station.team_leader,
    blue_bins: bin_rows(1, station.blue_bins, in_bins),
    overflow: list.map(over, fn(piece) {
      wire.Overflow(id: piece.id, piece: piece.reference, demand: piece.demand)
    }),
    team_members: list.map(of(rows.members, station), fn(member) {
      wire.Member(id: member.id, name: member.name, busy: member.busy)
    }),
    in_progress: list.map(of(rows.in_progress, station), fn(piece) {
      wire.InProgressPiece(
        id: piece.id,
        piece: piece.piece,
        demand: piece.demand,
        team_member: piece.team_member,
        team_member_id: piece.team_member_id,
        paused: piece.paused,
        under_rework: piece.under_rework,
        helpers: wire_helpers(rows_of(rows.helpers_of_piece, piece.id)),
      )
    }),
    rework: list.map(of(rows.rework, station), fn(item) {
      wire.Rework(
        id: item.id,
        piece: item.piece,
        description: item.description,
        found_by: item.found_by,
        found_by_id: item.found_by_id,
        assignee: item.assignee,
        assignee_id: item.assignee_id,
        helpers: wire_helpers(rows_of(rows.helpers_of_rework, item.id)),
        can_help: wire_helpers(rows_of(rows.can_help, item.id)),
      )
    }),
    first_pass_yield:,
    rework_hours:,
    deviations: of(rows.deviations, station)
      |> list.take(3)
      |> list.map(fn(item) {
        wire.Deviation(
          rule: item.rule,
          piece: item.piece,
          reason: item.reason,
          at: item.at,
        )
      }),
    kanbans: dict.get(rows.kanbans, station.id) |> result.unwrap(0),
  )
}

fn wire_helpers(helpers: List(Helper)) -> List(wire.TeamMemberName) {
  list.map(helpers, fn(helper) {
    wire.TeamMemberName(id: helper.id, name: helper.name)
  })
}

fn bin_rows(slot: Int, last: Int, pieces: List(Parked)) -> List(wire.BlueBin) {
  case slot > last {
    True -> []
    False -> {
      let #(here, rest) = case pieces {
        [first, ..rest] -> #(Some(first), rest)
        [] -> #(None, [])
      }
      let row =
        wire.BlueBin(
          slot:,
          id: option.map(here, fn(one) { one.id }),
          piece: option.map(here, fn(one) { one.reference }),
          demand: option.map(here, fn(one) { one.demand }),
          pulled_by: option.then(here, fn(one) { one.pulled_by }),
        )
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
    use under_rework <- decode.field(7, decode.int)
    decode.success(InProgress(
      station_id:,
      id:,
      piece:,
      demand:,
      team_member:,
      team_member_id:,
      paused: paused > 0,
      under_rework: under_rework > 0,
    ))
  }
  sqlight.query(
    "select p.station_id, p.id, p.reference, d.label,
            (select pe.name from team_member pe where pe.id = p.assignee),
            p.state = 'paused', p.assignee,
            exists (select 1 from rework r
                     where r.piece_id = p.id and r.closed_at is null)
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

fn query_helpers(
  connection: sqlight.Connection,
  sql: String,
) -> Result(List(Helper), sqlight.Error) {
  let decoder = {
    use rework_id <- decode.field(0, decode.string)
    use piece_id <- decode.field(1, decode.string)
    use id <- decode.field(2, decode.string)
    use name <- decode.field(3, decode.string)
    decode.success(Helper(rework_id:, piece_id:, id:, name:))
  }
  sqlight.query(sql, on: connection, with: [], expecting: decoder)
}

const helpers_sql =
  "select h.rework_id, h.piece_id, h.team_member_id, pe.name
       from helper h
       join team_member pe on pe.id = h.team_member_id
      order by h.since, h.rowid"

/// F61: the Team Members of the two Work Stations concerned, while someone
/// repairs, but not who repairs nor who already helps a Piece.
const can_help_sql =
  "select r.id, r.piece_id, pe.id, pe.name
       from rework r
       join team_member pe
         on pe.id in (select sp.team_member_id from station_team_member sp
                       where sp.station_id in (r.station_id, r.raised_by))
      where r.closed_at is null and r.assignee is not null
        and pe.id <> r.assignee
        and not exists (select 1 from helper h where h.team_member_id = pe.id)
      order by r.id, pe.name, pe.id"

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
    use found_by_id <- decode.field(7, decode.optional(decode.string))
    decode.success(Rework(
      station_id:,
      id:,
      piece:,
      description:,
      found_by:,
      found_by_id:,
      assignee:,
      assignee_id:,
    ))
  }
  sqlight.query(
    "select r.station_id, r.id, p.reference, r.description,
            coalesce((select w.name from work_station w where w.id = r.raised_by),
                     'downstream'),
            (select pe.name from team_member pe where pe.id = r.assignee),
            r.assignee, r.raised_by
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

/// The longest name (step, Work Station, Branch, Team Member, label) the
/// wall-TV column layout holds without breaking.
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

pub fn wire_step(step: Step) -> wire.Step {
  wire.Step(position: step.position, name: step.name)
}

pub fn rename_step(
  connection: sqlight.Connection,
  position: Int,
  name: String,
) -> Result(Step, RenameError) {
  use trimmed <- result.try(
    text.check(name, max_name_length)
    |> result.map_error(fn(error) {
      case error {
        text.Empty -> EmptyName
        text.TooLong -> NameTooLong
      }
    }),
  )
  // The new name and its flow event commit together.
  use <- db.transaction(connection, fn(_) { StoreFailed })
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
          "insert into flow_event (kind, payload)
           values ('step_renamed', json_object('name', ?))
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
