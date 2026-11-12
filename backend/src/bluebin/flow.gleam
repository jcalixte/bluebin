import bluebin/db
import bluebin/demand
import bluebin/heijunka
import bluebin/shape
import bluebin/wire
import gleam/bool
import gleam/dynamic/decode
import gleam/json
import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/result
import gleam/string
import sqlight

pub type Rule {
  PullWithoutKanban
  SecondPieceInABlueBin
  PullWithAnOpenRework
  PullDuringAndon
  ReorderHeijunkaSequence
}

pub type FlowError {
  UnknownStation
  NothingToPull
  NothingToAssemble
  PieceNotHere
  NeedsConfirmation(List(Rule))
  NotUpstream
  EmptyDescription
  UnknownRework
  ReworkFirst
  NotOfStation
  NotNextOfDemand
  NoAndon
  NotTeamLeader
  ReorderNeedsConfirmation(List(heijunka.Effect))
  NobodyRepairs
  NotOfReworkStations
  RepairsItAlready
  HelpsAnotherPiece
  NotHelping
  StoreFailed
}

pub type Flowed {
  Flowed(
    piece: String,
    demand: String,
    deviations: List(Rule),
    kanbans_sent_to: List(String),
  )
}

pub fn rule_name(rule: Rule) -> String {
  case rule {
    PullWithoutKanban -> "pull_without_kanban"
    SecondPieceInABlueBin -> "second_piece_in_a_blue_bin"
    PullWithAnOpenRework -> "pull_with_an_open_rework"
    PullDuringAndon -> "pull_during_andon"
    ReorderHeijunkaSequence -> "reorder_heijunka_sequence"
  }
}

pub fn rule_warning(rule: Rule) -> String {
  case rule {
    PullWithoutKanban ->
      "This Work Station holds no Kanban, so nothing downstream asked for a Piece. Pulling one anyway is a Deviation."
    SecondPieceInABlueBin ->
      "Every Blue Bin of this Work Station is full. Putting a second Piece in one is a Deviation."
    PullWithAnOpenRework ->
      "This Work Station found a defect and its Rework is still open: a free Blue Bin or a Kanban does not change that. Starting another Piece before the repair is a Deviation."
    PullDuringAndon ->
      "An Andon stops this Work Station until its Team Leader closes it. Pulling a new Piece now is a Deviation."
    ReorderHeijunkaSequence ->
      "Moving this Piece to the top before its turn breaks the Heijunka Sequence and the levelled Product Mix. It is a Deviation."
  }
}

pub fn pull(
  connection: sqlight.Connection,
  station_id: String,
  team_member: Option(String),
  reason: Option(String),
) -> Result(Flowed, FlowError) {
  use <- in_transaction(connection)
  use station <- result.try(load_station(connection, station_id))
  use repairing <- result.try(case team_member {
    None -> Ok(False)
    Some(team_member) ->
      holds_an_open_rework(connection, team_member, station.id)
  })
  use <- bool.guard(repairing, Error(ReworkFirst))
  use source <- result.try(next_source(connection, station))

  use kanban <- result.try(oldest_kanban(connection, station.id))
  use open_rework <- result.try(raised_an_open_rework(connection, station.id))
  use stopped <- result.try(stopped_by_andon(connection, station.id))
  let broken =
    [
      #(stopped, PullDuringAndon),
      #(open_rework, PullWithAnOpenRework),
      #(kanban == None, PullWithoutKanban),
    ]
    |> list.filter_map(fn(check) {
      case check.0 {
        True -> Ok(check.1)
        False -> Error(Nil)
      }
    })
  use deviations <- result.try(record_deviations(
    connection,
    broken,
    station.id,
    source.id,
    reason,
  ))
  use _ <- result.try(spend_kanban(connection, kanban, station.id))

  use #(pulled, sent) <- result.try(case station.inflow {
    shape.FromBacklog | shape.Straight(_) ->
      take_whole(connection, station, source)
    shape.AtSplit(_, branches) ->
      split_off(connection, station, source, branches)
    shape.Assembly(_) -> assemble(connection, station, source)
  })
  use holder <- result.try(take_in_hand(
    connection,
    pulled.0,
    station.id,
    team_member,
  ))
  use _ <- result.try(case holder {
    None -> Ok([])
    Some(holder) -> {
      // Pulling is the Helper's choice of other work: the help ends.
      use _ <- result.try(leave_help(connection, holder, "pulled"))
      keep_nearest_active(connection, holder, pulled.0)
    }
  })

  use _ <- result.try(record_event(
    connection,
    case station.inflow {
      shape.Assembly(_) -> "piece_assembled"
      _ -> "piece_pulled"
    },
    Some(pulled.0),
    json.object([
      #("station", json.string(station.id)),
      #("from", json.nullable(source.station_id, json.string)),
    ]),
  ))

  Ok(Flowed(
    piece: pulled.1,
    demand: source.demand,
    deviations:,
    kanbans_sent_to: sent,
  ))
}

pub fn finish(
  connection: sqlight.Connection,
  station_id: String,
  piece_id: String,
  reason: Option(String),
) -> Result(Flowed, FlowError) {
  use <- in_transaction(connection)
  use station <- result.try(load_station(connection, station_id))
  use piece <- result.try(load_piece_at(
    connection,
    piece_id,
    station.id,
    "in_flow",
  ))

  use free <- result.try(free_blue_bins(connection, station.id))
  use deviations <- result.try(record_deviations(
    connection,
    case free > 0 {
      True -> []
      False -> [SecondPieceInABlueBin]
    },
    station.id,
    piece.id,
    reason,
  ))

  // Finishing the Piece accepts its repair: its open Rework closes.
  use open <- result.try(
    rows(
      connection,
      "select id, assignee from rework
      where piece_id = ?1 and closed_at is null
      order by opened_at, rowid",
      [sqlight.text(piece.id)],
      {
        use id <- decode.field(0, decode.string)
        use assignee <- decode.field(1, decode.optional(decode.string))
        decode.success(#(id, assignee))
      },
    ),
  )
  use _ <- result.try(
    list.try_each(open, fn(rework) {
      close_rework(connection, rework.0, piece.id, rework.1, "finish")
      |> result.replace(Nil)
    }),
  )

  // Before the assignee is cleared below: piece_pass records who transformed
  // the Piece, for the Rework author (F13) and First Pass Yield (F16).
  use _ <- result.try(record_pass(connection, piece.id, station.id))
  use holder <- result.try(assignee_of(connection, piece.id))

  use _ <- result.try(
    write(
      connection,
      "update piece
        set state = 'in_bin', assignee = null,
            since = strftime('%Y-%m-%dT%H:%M:%SZ', 'now')
      where id = ?1",
      [sqlight.text(piece.id)],
    ),
  )

  use _ <- result.try(record_event(
    connection,
    "piece_put_in_blue_bin",
    Some(piece.id),
    json.object([#("station", json.string(station.id))]),
  ))

  use _ <- result.try(settle_option(connection, holder))

  Ok(
    Flowed(
      piece: piece.reference,
      demand: piece.demand,
      deviations:,
      kanbans_sent_to: [],
    ),
  )
}

/// By default the Piece is released at its Deployment; with `hold` it waits,
/// held for Release, until `release`. Either way it leaves the Line.
pub fn deploy(
  connection: sqlight.Connection,
  piece_id: String,
  hold hold: Bool,
) -> Result(Flowed, FlowError) {
  use <- in_transaction(connection)
  use last <- result.try(last_position(connection))
  use piece <- result.try(load_piece_in_last_bin(connection, piece_id, last))

  use _ <- result.try(
    write(
      connection,
      "update piece
        set state = 'deployed', station_id = null, assignee = null,
            deployed_at = strftime('%Y-%m-%dT%H:%M:%SZ', 'now'),
            since = strftime('%Y-%m-%dT%H:%M:%SZ', 'now')
      where id = ?1",
      [sqlight.text(piece.id)],
    ),
  )

  use sent <- result.try(send_kanbans(connection, [piece.station_id]))

  use _ <- result.try(record_event(
    connection,
    "piece_deployed",
    Some(piece.id),
    json.object([#("station", json.string(piece.station_id))]),
  ))

  use _ <- result.try(case hold {
    True -> Ok(Nil)
    False -> release_one(connection, piece.id)
  })

  Ok(Flowed(
    piece: piece.reference,
    demand: piece.demand,
    deviations: [],
    kanbans_sent_to: sent,
  ))
}

/// Releases every Piece of `piece_ids`, or none of them when one is not held
/// for Release.
pub fn release(
  connection: sqlight.Connection,
  piece_ids: List(String),
) -> Result(Int, FlowError) {
  use <- in_transaction(connection)
  use _ <- result.try(list.try_each(piece_ids, release_one(connection, _)))
  Ok(list.length(piece_ids))
}

fn release_one(
  connection: sqlight.Connection,
  piece_id: String,
) -> Result(Nil, FlowError) {
  use released <- result.try(maybe_one(
    connection,
    "update piece set released_at = strftime('%Y-%m-%dT%H:%M:%SZ', 'now')
      where id = ?1 and state = 'deployed' and released_at is null
     returning id",
    [sqlight.text(piece_id)],
    decode.at([0], decode.string),
  ))
  use <- bool.guard(released == None, Error(PieceNotHere))
  use _ <- result.try(record_event(
    connection,
    "piece_released",
    Some(piece_id),
    json.object([]),
  ))
  deliver_demand_when_complete(connection, piece_id)
}

/// `waiting_hours` runs from its Deployment, in Calendar Time.
pub type HeldForRelease {
  HeldForRelease(
    id: String,
    reference: String,
    demand: String,
    demand_label: String,
    waiting_hours: Float,
  )
}

pub fn held_for_release(
  connection: sqlight.Connection,
) -> Result(List(HeldForRelease), sqlight.Error) {
  sqlight.query(
    "select p.id, p.reference, d.id, d.label,
            round((julianday('now') - julianday(p.deployed_at)) * 24, 1)
       from piece p join demand d on d.id = p.demand_id
      where p.state = 'deployed' and p.released_at is null
      order by p.deployed_at, p.id",
    on: connection,
    with: [],
    expecting: {
      use id <- decode.field(0, decode.string)
      use reference <- decode.field(1, decode.string)
      use demand <- decode.field(2, decode.string)
      use demand_label <- decode.field(3, decode.string)
      use waiting_hours <- decode.field(4, decode.float)
      decode.success(HeldForRelease(
        id:,
        reference:,
        demand:,
        demand_label:,
        waiting_hours:,
      ))
    },
  )
}

pub fn wire_held(one: HeldForRelease) -> wire.HeldForRelease {
  wire.HeldForRelease(
    id: one.id,
    piece: one.reference,
    demand: one.demand,
    demand_label: one.demand_label,
    waiting_hours: one.waiting_hours,
  )
}

fn deliver_demand_when_complete(
  connection: sqlight.Connection,
  piece_id: String,
) -> Result(Nil, FlowError) {
  use delivered <- result.try(maybe_one(
    connection,
    "update demand set state = 'delivered'
      where id = (select demand_id from piece where id = ?1)
        and state = 'active'
        and (select count(*) from piece p
              where p.demand_id = demand.id and p.parent_id is null
                and p.released_at is not null) >= pieces_asked
     returning id",
    [sqlight.text(piece_id)],
    decode.at([0], decode.string),
  ))
  case delivered {
    None -> Ok(Nil)
    Some(demand) ->
      record_event(
        connection,
        "demand_delivered",
        None,
        json.object([
          #("demand", json.string(demand)),
          #("piece", json.string(piece_id)),
        ]),
      )
  }
}

/// Moves the next Piece of a Demand to the top of the Backlog, behind the
/// Pieces already urgent (F25). It breaks the Heijunka Sequence, so it asks
/// for a reason first and shows what each Demand loses.
pub fn make_urgent(
  connection: sqlight.Connection,
  piece_id: String,
  reason: Option(String),
) -> Result(Flowed, FlowError) {
  use <- in_transaction(connection)
  use backlog <- result.try(
    heijunka.load(connection) |> result.replace_error(StoreFailed),
  )
  use placed <- result.try(
    list.find(backlog.sequence, fn(placed) { placed.piece.id == piece_id })
    |> result.replace_error(PieceNotHere),
  )
  let done =
    Flowed(
      piece: placed.piece.reference,
      demand: placed.demand.label,
      deviations: [],
      kanbans_sent_to: [],
    )
  use <- bool.guard(placed.piece.urgent != None, Ok(done))
  use <- bool.guard(
    !heijunka.next_of_its_demand(backlog.sequence, placed),
    Error(NotNextOfDemand),
  )
  let after = heijunka.make_urgent(backlog.sequence, piece_id)
  use <- bool.guard(after == backlog.sequence, Ok(done))

  case option.map(reason, string.trim) {
    None | Some("") ->
      Error(
        ReorderNeedsConfirmation(heijunka.effects(
          backlog.sequence,
          after,
          demand.line_takt_hours(backlog.demands),
        )),
      )
    Some(reason) -> {
      use first <- result.try(first_station(connection))
      use _ <- result.try(
        write(
          connection,
          "update piece
            set urgent = (select coalesce(max(urgent), 0) + 1 from piece)
          where id = ?1",
          [sqlight.text(piece_id)],
        ),
      )
      use _ <- result.try(record_deviation(
        connection,
        ReorderHeijunkaSequence,
        first,
        piece_id,
        reason,
      ))
      Ok(Flowed(..done, deviations: [ReorderHeijunkaSequence]))
    }
  }
}

/// A Backlog reorder is this Work Station's Deviation.
fn first_station(connection: sqlight.Connection) -> Result(String, FlowError) {
  one(
    connection,
    "select id from work_station order by position, id limit 1",
    [],
    decode.at([0], decode.string),
    or: UnknownStation,
  )
}

pub type Raised {
  Raised(
    id: String,
    piece: String,
    demand: String,
    assignee: Option(String),
    paused: Option(String),
  )
}

pub type Repaired {
  Repaired(piece: String, resumed: Option(String))
}

pub fn raise_rework(
  connection: sqlight.Connection,
  station_id: String,
  piece_id: String,
  made_by_id: String,
  description: String,
) -> Result(Raised, FlowError) {
  use <- in_transaction(connection)
  let description = string.trim(description)
  use <- bool.guard(description == "", Error(EmptyDescription))

  use found_by <- result.try(load_station(connection, station_id))
  use made_by <- result.try(load_station(connection, made_by_id))
  use <- bool.guard(
    !shape.is_upstream(found_by.nodes, made_by.id, found_by.id),
    Error(NotUpstream),
  )
  use piece <- result.try(load_piece_at(
    connection,
    piece_id,
    found_by.id,
    "in_flow",
  ))

  use author <- result.try(author_of(connection, piece.id, made_by.id))

  use id <- result.try(one(
    connection,
    "insert into rework (id, piece_id, station_id, description, raised_by,
                         assignee)
     values ('rw-' || lower(hex(randomblob(6))), ?1, ?2, ?3, ?4, ?5)
     returning id",
    [
      sqlight.text(piece.id),
      sqlight.text(made_by.id),
      sqlight.text(description),
      sqlight.text(found_by.id),
      sqlight.nullable(sqlight.text, option.map(author, fn(one) { one.0 })),
    ],
    decode.at([0], decode.string),
    or: StoreFailed,
  ))

  use settled <- result.try(settle_option(
    connection,
    option.map(author, fn(one) { one.0 }),
  ))

  use _ <- result.try(record_event(
    connection,
    "rework_raised",
    Some(piece.id),
    json.object([
      #("station", json.string(made_by.id)),
      #("raisedBy", json.string(found_by.id)),
      #("description", json.string(description)),
    ]),
  ))

  Ok(Raised(
    id:,
    piece: piece.reference,
    demand: piece.demand,
    assignee: option.map(author, fn(one) { one.1 }),
    paused: list.first(settled.paused) |> option.from_result,
  ))
}

pub fn repair_rework(
  connection: sqlight.Connection,
  rework_id: String,
) -> Result(Repaired, FlowError) {
  use <- in_transaction(connection)
  use #(piece_id, reference, assignee) <- result.try(load_open_rework(
    connection,
    rework_id,
  ))
  use resumed <- result.try(close_rework(
    connection,
    rework_id,
    piece_id,
    assignee,
    "repaired",
  ))
  Ok(Repaired(piece: reference, resumed:))
}

/// Closes an open Rework: ends its help (F63) and frees its repairer.
/// `by` is `repaired`, or `finish` when the Work Station that found the
/// defect finishes the Piece, which accepts the repair.
fn close_rework(
  connection: sqlight.Connection,
  rework_id: String,
  piece_id: String,
  assignee: Option(String),
  by: String,
) -> Result(Option(String), FlowError) {
  use _ <- result.try(
    write(
      connection,
      "update rework
          set closed_at = strftime('%Y-%m-%dT%H:%M:%SZ', 'now')
        where id = ?1",
      [sqlight.text(rework_id)],
    ),
  )

  use _ <- result.try(record_event(
    connection,
    "rework_repaired",
    Some(piece_id),
    json.object([
      #("rework", json.string(rework_id)),
      #("by", json.string(by)),
    ]),
  ))

  use helpers <- result.try(rows(
    connection,
    "delete from helper where rework_id = ?1 returning team_member_id",
    [sqlight.text(rework_id)],
    decode.at([0], decode.string),
  ))
  use _ <- result.try(
    list.try_each(helpers, fn(helper) {
      use _ <- result.try(record_help_left(
        connection,
        helper,
        piece_id,
        rework_id,
        "repaired",
      ))
      settle(connection, helper) |> result.replace(Nil)
    }),
  )

  use settled <- result.try(settle_option(connection, assignee))
  Ok(settled.resumed)
}

pub type Helped {
  Helped(piece: String, assignee: String, paused: List(String))
}

/// Help the Rework (F61): a Team Member of the Work Station that found the
/// defect, or of the one that made it, joins the Piece while someone holds
/// the Rework's Assignment. Their own Pieces pause (F62).
pub fn help_the_rework(
  connection: sqlight.Connection,
  rework_id: String,
  team_member_id: String,
) -> Result(Helped, FlowError) {
  use <- in_transaction(connection)
  let decoder = {
    use piece_id <- decode.field(0, decode.string)
    use reference <- decode.field(1, decode.string)
    use assignee <- decode.field(2, decode.optional(decode.string))
    use assignee_name <- decode.field(3, decode.optional(decode.string))
    use allowed <- decode.field(4, decode.int)
    decode.success(#(piece_id, reference, assignee, assignee_name, allowed > 0))
  }
  use #(piece_id, reference, assignee, assignee_name, allowed) <- result.try(
    one(
      connection,
      "select r.piece_id, p.reference, r.assignee, pe.name,
            exists (select 1 from station_team_member sp
                     where sp.team_member_id = ?2
                       and sp.station_id in (r.station_id, r.raised_by))
       from rework r
       join piece p on p.id = r.piece_id
       left join team_member pe on pe.id = r.assignee
      where r.id = ?1 and r.closed_at is null",
      [sqlight.text(rework_id), sqlight.text(team_member_id)],
      decoder,
      or: UnknownRework,
    ),
  )
  use <- bool.guard(!allowed, Error(NotOfReworkStations))
  use #(assignee, assignee_name) <- result.try(case assignee, assignee_name {
    Some(assignee), Some(name) -> Ok(#(assignee, name))
    _, _ -> Error(NobodyRepairs)
  })
  use <- bool.guard(assignee == team_member_id, Error(RepairsItAlready))
  use repairing <- result.try(
    exists(
      connection,
      "select count(*) from rework where assignee = ?1 and closed_at is null",
      [sqlight.text(team_member_id)],
    ),
  )
  use <- bool.guard(repairing, Error(ReworkFirst))
  use helping <- result.try(helped_rework(connection, team_member_id))
  case helping {
    Some(#(helped, _)) if helped == rework_id ->
      Ok(Helped(piece: reference, assignee: assignee_name, paused: []))
    Some(_) -> Error(HelpsAnotherPiece)
    None -> {
      use _ <- result.try(
        write(
          connection,
          "insert into helper (team_member_id, piece_id, rework_id)
         values (?1, ?2, ?3)",
          [
            sqlight.text(team_member_id),
            sqlight.text(piece_id),
            sqlight.text(rework_id),
          ],
        ),
      )
      use _ <- result.try(record_event(
        connection,
        "helper_joined",
        Some(piece_id),
        json.object([
          #("teamMember", json.string(team_member_id)),
          #("rework", json.string(rework_id)),
        ]),
      ))
      use settled <- result.try(settle(connection, team_member_id))
      Ok(Helped(
        piece: reference,
        assignee: assignee_name,
        paused: settled.paused,
      ))
    }
  }
}

pub type StoppedHelping {
  StoppedHelping(piece: String, resumed: Option(String))
}

/// The Helper stops before the Rework closes (F63); their next Piece resumes.
pub fn stop_helping(
  connection: sqlight.Connection,
  team_member_id: String,
) -> Result(StoppedHelping, FlowError) {
  use <- in_transaction(connection)
  use left <- result.try(leave_help(connection, team_member_id, "stopped"))
  case left {
    None -> Error(NotHelping)
    Some(reference) -> {
      use settled <- result.try(settle(connection, team_member_id))
      Ok(StoppedHelping(piece: reference, resumed: settled.resumed))
    }
  }
}

fn helped_rework(
  connection: sqlight.Connection,
  team_member_id: String,
) -> Result(Option(#(String, String)), FlowError) {
  let decoder = {
    use rework_id <- decode.field(0, decode.string)
    use piece_id <- decode.field(1, decode.string)
    decode.success(#(rework_id, piece_id))
  }
  maybe_one(
    connection,
    "select rework_id, piece_id from helper where team_member_id = ?1",
    [sqlight.text(team_member_id)],
    decoder,
  )
}

/// Ends the help of `team_member_id`, if any, and answers the reference of
/// the Piece they helped. The caller settles their Pieces.
fn leave_help(
  connection: sqlight.Connection,
  team_member_id: String,
  cause: String,
) -> Result(Option(String), FlowError) {
  let decoder = {
    use piece_id <- decode.field(0, decode.string)
    use rework_id <- decode.field(1, decode.string)
    use reference <- decode.field(2, decode.string)
    decode.success(#(piece_id, rework_id, reference))
  }
  use left <- result.try(maybe_one(
    connection,
    "delete from helper where team_member_id = ?1
     returning piece_id, rework_id,
               (select reference from piece where id = helper.piece_id)",
    [sqlight.text(team_member_id)],
    decoder,
  ))
  case left {
    None -> Ok(None)
    Some(#(piece_id, rework_id, reference)) -> {
      use _ <- result.try(record_help_left(
        connection,
        team_member_id,
        piece_id,
        rework_id,
        cause,
      ))
      Ok(Some(reference))
    }
  }
}

fn record_help_left(
  connection: sqlight.Connection,
  team_member_id: String,
  piece_id: String,
  rework_id: String,
  cause: String,
) -> Result(Nil, FlowError) {
  record_event(
    connection,
    "helper_left",
    Some(piece_id),
    json.object([
      #("teamMember", json.string(team_member_id)),
      #("rework", json.string(rework_id)),
      #("cause", json.string(cause)),
    ]),
  )
}

fn load_open_rework(
  connection: sqlight.Connection,
  rework_id: String,
) -> Result(#(String, String, Option(String)), FlowError) {
  let decoder = {
    use piece_id <- decode.field(0, decode.string)
    use reference <- decode.field(1, decode.string)
    use assignee <- decode.field(2, decode.optional(decode.string))
    decode.success(#(piece_id, reference, assignee))
  }
  one(
    connection,
    "select r.piece_id, p.reference, r.assignee
       from rework r
       join piece p on p.id = r.piece_id
      where r.id = ?1 and r.closed_at is null",
    [sqlight.text(rework_id)],
    decoder,
    or: UnknownRework,
  )
}

pub type Settled {
  Settled(paused: List(String), resumed: Option(String))
}

pub type AssignmentKind {
  ReworkAssignment
  PieceAssignment
}

pub type Reassigned {
  Reassigned(piece: String, team_member: String)
}

pub fn reassign(
  connection: sqlight.Connection,
  kind: AssignmentKind,
  id: String,
  team_member_id: String,
) -> Result(Reassigned, FlowError) {
  use <- in_transaction(connection)
  use #(reference, station_id, previous, in_flow) <- result.try(case kind {
    PieceAssignment -> load_piece_in_hand(connection, id)
    ReworkAssignment -> {
      use #(_, reference, previous) <- result.try(load_open_rework(
        connection,
        id,
      ))
      use station_id <- result.try(rework_station(connection, id))
      Ok(#(reference, station_id, previous, False))
    }
  })
  use name <- result.try(member_name(connection, station_id, team_member_id))
  use <- bool.guard(
    previous == Some(team_member_id),
    Ok(Reassigned(piece: reference, team_member: name)),
  )

  use _ <- result.try(
    write(
      connection,
      case kind {
        PieceAssignment -> "update piece set assignee = ?2 where id = ?1"
        ReworkAssignment -> "update rework set assignee = ?2 where id = ?1"
      },
      [sqlight.text(id), sqlight.text(team_member_id)],
    ),
  )
  use _ <- result.try(case in_flow {
    True ->
      keep_nearest_active(connection, team_member_id, id) |> result.replace(Nil)
    False -> Ok(Nil)
  })
  use _ <- result.try(settle(connection, team_member_id))
  use _ <- result.try(settle_option(connection, previous))

  use _ <- result.try(record_event(
    connection,
    "assignment_changed",
    case kind {
      PieceAssignment -> Some(id)
      ReworkAssignment -> None
    },
    json.object([
      #(
        "kind",
        json.string(case kind {
          PieceAssignment -> "piece"
          ReworkAssignment -> "rework"
        }),
      ),
      #("id", json.string(id)),
      #("from", json.nullable(previous, json.string)),
      #("to", json.string(team_member_id)),
    ]),
  ))
  Ok(Reassigned(piece: reference, team_member: name))
}

fn settle(
  connection: sqlight.Connection,
  team_member_id: String,
) -> Result(Settled, FlowError) {
  use open <- result.try(
    exists(
      connection,
      "select count(*) from rework where assignee = ?1 and closed_at is null",
      [sqlight.text(team_member_id)],
    ),
  )
  use helping <- result.try(helped_rework(connection, team_member_id))
  case open, helping {
    True, _ -> {
      // Rework first: their own repair ends any help.
      use _ <- result.try(leave_help(connection, team_member_id, "rework"))
      use _ <- result.try(start_next_rework(connection, team_member_id))
      use paused <- result.try(pause_pieces(
        connection,
        team_member_id,
        None,
        "rework",
      ))
      Ok(Settled(paused:, resumed: None))
    }
    False, Some(#(_, helped_piece)) -> {
      // The helped Piece can be in their own hands, as at the Work Station
      // that found the defect: it stays active.
      use paused <- result.try(pause_pieces(
        connection,
        team_member_id,
        Some(helped_piece),
        "helping",
      ))
      Ok(Settled(paused:, resumed: None))
    }
    False, None -> {
      use resumed <- result.try(resume_next_piece(connection, team_member_id))
      Ok(Settled(paused: [], resumed:))
    }
  }
}

fn settle_option(
  connection: sqlight.Connection,
  team_member_id: Option(String),
) -> Result(Settled, FlowError) {
  case team_member_id {
    None -> Ok(Settled(paused: [], resumed: None))
    Some(team_member_id) -> settle(connection, team_member_id)
  }
}

fn start_next_rework(
  connection: sqlight.Connection,
  team_member_id: String,
) -> Result(Nil, FlowError) {
  write(
    connection,
    "update rework set started_at = strftime('%Y-%m-%dT%H:%M:%SZ', 'now')
      where id = (select id from rework
                   where assignee = ?1 and closed_at is null
                   order by opened_at, rowid limit 1)
        and not exists (select 1 from rework
                         where assignee = ?1 and closed_at is null
                           and started_at is not null)",
    [sqlight.text(team_member_id)],
  )
}

/// A Team Member transforms one Piece at a time. When a Piece comes into their
/// hands, the one nearest to Deployment stays active and the others pause; on
/// a tie the newcomer waits. Finishing beats starting.
fn keep_nearest_active(
  connection: sqlight.Connection,
  team_member_id: String,
  newcomer: String,
) -> Result(List(String), FlowError) {
  use kept <- result.try(maybe_one(
    connection,
    "select p.id from piece p
       join work_station w on w.id = p.station_id
      where p.assignee = ?1 and p.state = 'in_flow'
      order by w.position desc, p.id = ?2, p.since, p.rowid limit 1",
    [sqlight.text(team_member_id), sqlight.text(newcomer)],
    decode.at([0], decode.string),
  ))
  pause_pieces(connection, team_member_id, kept, "held")
}

/// Answers the references of the Pieces paused.
fn pause_pieces(
  connection: sqlight.Connection,
  team_member_id: String,
  except: Option(String),
  cause: String,
) -> Result(List(String), FlowError) {
  use paused <- result.try(rows(
    connection,
    "update piece set state = 'paused',
                      since = strftime('%Y-%m-%dT%H:%M:%SZ', 'now')
      where assignee = ?1 and state = 'in_flow' and id is not ?2
      returning id, reference",
    [sqlight.text(team_member_id), sqlight.nullable(sqlight.text, except)],
    id_and_reference(),
  ))
  list.try_map(paused, fn(piece) {
    use _ <- result.try(record_event(
      connection,
      "piece_paused",
      Some(piece.0),
      json.object([
        #("teamMember", json.string(team_member_id)),
        #("cause", json.string(cause)),
      ]),
    ))
    Ok(piece.1)
  })
}

fn resume_next_piece(
  connection: sqlight.Connection,
  team_member_id: String,
) -> Result(Option(String), FlowError) {
  use resumed <- result.try(maybe_one(
    connection,
    "update piece set state = 'in_flow',
                      since = strftime('%Y-%m-%dT%H:%M:%SZ', 'now')
      where id = (select p.id from piece p
                    join work_station w on w.id = p.station_id
                   where p.assignee = ?1 and p.state = 'paused'
                   order by w.position desc, p.since, p.rowid limit 1)
        and not exists (select 1 from piece
                         where assignee = ?1 and state = 'in_flow')
      returning id, reference",
    [sqlight.text(team_member_id)],
    id_and_reference(),
  ))
  case resumed {
    None -> Ok(None)
    Some(#(id, reference)) -> {
      use _ <- result.try(record_event(
        connection,
        "piece_resumed",
        Some(id),
        json.object([#("teamMember", json.string(team_member_id))]),
      ))
      Ok(Some(reference))
    }
  }
}

fn holds_an_open_rework(
  connection: sqlight.Connection,
  team_member_id: String,
  station_id: String,
) -> Result(Bool, FlowError) {
  exists(
    connection,
    "select count(*) from rework r
      where r.assignee = ?1 and r.closed_at is null
        and exists (select 1 from station_team_member sp
                     where sp.station_id = ?2 and sp.team_member_id = ?1)",
    [sqlight.text(team_member_id), sqlight.text(station_id)],
  )
}

fn assignee_of(
  connection: sqlight.Connection,
  piece_id: String,
) -> Result(Option(String), FlowError) {
  maybe_one(
    connection,
    "select assignee from piece where id = ?1",
    [sqlight.text(piece_id)],
    decode.at([0], decode.optional(decode.string)),
  )
  |> result.map(option.flatten)
}

fn load_piece_in_hand(
  connection: sqlight.Connection,
  piece_id: String,
) -> Result(#(String, String, Option(String), Bool), FlowError) {
  let decoder = {
    use reference <- decode.field(0, decode.string)
    use station_id <- decode.field(1, decode.string)
    use assignee <- decode.field(2, decode.optional(decode.string))
    use in_flow <- decode.field(3, decode.int)
    decode.success(#(reference, station_id, assignee, in_flow > 0))
  }
  one(
    connection,
    "select reference, station_id, assignee, state = 'in_flow' from piece
      where id = ?1 and station_id is not null
        and state in ('in_flow', 'paused')",
    [sqlight.text(piece_id)],
    decoder,
    or: PieceNotHere,
  )
}

/// The Work Station that made the defect, not the one that raised it.
fn rework_station(
  connection: sqlight.Connection,
  rework_id: String,
) -> Result(String, FlowError) {
  one(
    connection,
    "select station_id from rework where id = ?1",
    [sqlight.text(rework_id)],
    decode.at([0], decode.string),
    or: UnknownRework,
  )
}

fn member_name(
  connection: sqlight.Connection,
  station_id: String,
  team_member_id: String,
) -> Result(String, FlowError) {
  one(
    connection,
    "select pe.name from station_team_member sp
       join team_member pe on pe.id = sp.team_member_id
      where sp.station_id = ?1 and sp.team_member_id = ?2",
    [sqlight.text(station_id), sqlight.text(team_member_id)],
    decode.at([0], decode.string),
    or: NotOfStation,
  )
}

/// Whether the Work Station can pull now without a Deviation (F20).
pub fn can_pull(
  connection: sqlight.Connection,
  station_id: String,
) -> Result(Bool, FlowError) {
  use station <- result.try(load_station(connection, station_id))
  use kanban <- result.try(oldest_kanban(connection, station.id))
  use open_rework <- result.try(raised_an_open_rework(connection, station.id))
  use stopped <- result.try(stopped_by_andon(connection, station.id))
  use <- bool.guard(kanban == None || open_rework || stopped, Ok(False))
  case next_source(connection, station) {
    Ok(_) -> Ok(True)
    Error(NothingToPull) | Error(NothingToAssemble) -> Ok(False)
    Error(failure) -> Error(failure)
  }
}

/// Any Team Member stops their Work Station with one click (F42). A second Andon
/// on a stopped Work Station changes nothing. A Team Member who is not of the Work
/// Station still stops it, but is not recorded as who raised it.
pub fn raise_andon(
  connection: sqlight.Connection,
  station_id: String,
  team_member: Option(String),
) -> Result(Nil, FlowError) {
  use <- in_transaction(connection)
  use station <- result.try(load_station(connection, station_id))
  use stopped <- result.try(stopped_by_andon(connection, station.id))
  use <- bool.guard(stopped, Ok(Nil))
  use raised_by <- result.try(one(
    connection,
    "insert into andon (station_id, raised_by)
     values (?1, (select sp.team_member_id from station_team_member sp
                   where sp.station_id = ?1 and sp.team_member_id = ?2))
     returning raised_by",
    [sqlight.text(station.id), sqlight.nullable(sqlight.text, team_member)],
    decode.at([0], decode.optional(decode.string)),
    or: StoreFailed,
  ))
  record_event(
    connection,
    "andon_raised",
    None,
    json.object([
      #("station", json.string(station.id)),
      #("teamMember", json.nullable(raised_by, json.string)),
    ]),
  )
}

/// Only the Team Leader of the Work Station closes its Andon.
pub fn close_andon(
  connection: sqlight.Connection,
  station_id: String,
  team_member: String,
) -> Result(Nil, FlowError) {
  use <- in_transaction(connection)
  use station <- result.try(load_station(connection, station_id))
  use closed <- result.try(rows(
    connection,
    "update andon
        set closed_by = ?2, closed_at = strftime('%Y-%m-%dT%H:%M:%SZ', 'now')
      where station_id = ?1 and closed_at is null
        and ?2 = (select team_leader from work_station where id = ?1)
      returning id",
    [sqlight.text(station.id), sqlight.text(team_member)],
    decode.at([0], decode.int),
  ))
  use stopped <- result.try(stopped_by_andon(connection, station.id))
  case closed, stopped {
    [], True -> Error(NotTeamLeader)
    [], False -> Error(NoAndon)
    _, _ ->
      record_event(
        connection,
        "andon_closed",
        None,
        json.object([
          #("station", json.string(station.id)),
          #("teamMember", json.string(team_member)),
        ]),
      )
  }
}

fn stopped_by_andon(
  connection: sqlight.Connection,
  station_id: String,
) -> Result(Bool, FlowError) {
  exists(
    connection,
    "select count(*) from andon where station_id = ?1 and closed_at is null",
    [sqlight.text(station_id)],
  )
}

fn author_of(
  connection: sqlight.Connection,
  piece_id: String,
  station_id: String,
) -> Result(Option(#(String, String)), FlowError) {
  let decoder = {
    use id <- decode.field(0, decode.string)
    use name <- decode.field(1, decode.string)
    decode.success(#(id, name))
  }
  maybe_one(
    connection,
    "select pp.team_member_id, pe.name
       from piece_pass pp
       join team_member pe on pe.id = pp.team_member_id
      where pp.station_id = ?2
        and (pp.piece_id = ?1
             or pp.piece_id in (select s.id from piece s
                                 where s.parent_id = ?1
                                    or s.parent_id in (select c.id from piece c
                                                        where c.parent_id = ?1))
             or pp.piece_id in (select o.parent_id from piece o where o.id = ?1)
             or pp.piece_id in (select g.parent_id from piece g
                                 where g.id = (select o.parent_id from piece o
                                                where o.id = ?1)))
      order by pp.at desc
      limit 1",
    [sqlight.text(piece_id), sqlight.text(station_id)],
    decoder,
  )
}

fn next_source(
  connection: sqlight.Connection,
  station: Station,
) -> Result(Source, FlowError) {
  case station.inflow {
    shape.FromBacklog -> next_backlog_piece(connection)
    shape.Straight(from) -> next_upstream_piece(connection, from)
    shape.AtSplit(from, _) -> next_unsplit_piece(connection, station, from)
    shape.Assembly(ends) -> next_complete_piece(connection, ends)
  }
}

/// Answers the id and reference of what moved, and the Work Stations that got
/// a Kanban back.
fn take_whole(
  connection: sqlight.Connection,
  station: Station,
  source: Source,
) -> Result(#(#(String, String), List(String)), FlowError) {
  use _ <- result.try(move_into_hands(connection, source.id, station.id))
  use sent <- result.try(send_kanbans(
    connection,
    option.values([source.station_id]),
  ))
  Ok(#(#(source.id, source.reference), sent))
}

/// The Piece holds the trunk's Blue Bin until the last Branch has taken its
/// Sub-Piece; only then does its Work Station get a Kanban back.
fn split_off(
  connection: sqlight.Connection,
  station: Station,
  source: Source,
  branches: List(String),
) -> Result(#(#(String, String), List(String)), FlowError) {
  let branch = option.unwrap(station.branch, "")
  use sub_piece <- result.try(one(
    connection,
    "insert into piece (id, demand_id, reference, number, state, station_id,
                        since, parent_id, branch)
     select p.id || '-' || lower(replace(?2, ' ', '-')), p.demand_id,
            coalesce((select r.reference from piece r where r.id = p.parent_id),
                     p.reference) || ' · ' || ?2,
            p.number, 'in_flow', ?3,
            strftime('%Y-%m-%dT%H:%M:%SZ', 'now'), p.id, ?2
     from piece p where p.id = ?1
     returning id, reference",
    [sqlight.text(source.id), sqlight.text(branch), sqlight.text(station.id)],
    id_and_reference(),
    or: StoreFailed,
  ))

  use left <- result.try(maybe_one(
    connection,
    "update piece
        set state = 'split', station_id = null,
            since = strftime('%Y-%m-%dT%H:%M:%SZ', 'now')
      where id = ?1
        and (select count(*) from piece s
              where s.parent_id = ?1
                and s.branch in (select value from json_each(?2)))
         >= json_array_length(?2)
      returning id",
    [
      sqlight.text(source.id),
      sqlight.text(json.to_string(json.array(branches, json.string))),
    ],
    decode.at([0], decode.string),
  ))
  use sent <- result.try(case left {
    None -> Ok([])
    Some(_) -> {
      // The Piece leaves the trunk's Blue Bin here, which ends its Station
      // Lead Time there.
      use _ <- result.try(record_event(
        connection,
        "piece_split",
        Some(source.id),
        json.object([
          #("station", json.nullable(source.station_id, json.string)),
        ]),
      ))
      send_kanbans(connection, option.values([source.station_id]))
    }
  })
  Ok(#(sub_piece, sent))
}

fn assemble(
  connection: sqlight.Connection,
  station: Station,
  source: Source,
) -> Result(#(#(String, String), List(String)), FlowError) {
  use branch_ends <- result.try(rows(
    connection,
    "select station_id from piece
      where parent_id = ?1 and state != 'assembled'
      order by branch",
    [sqlight.text(source.id)],
    decode.at([0], decode.string),
  ))

  use _ <- result.try(
    write(
      connection,
      "update piece
        set state = 'assembled', station_id = null, assignee = null,
            since = strftime('%Y-%m-%dT%H:%M:%SZ', 'now')
      where parent_id = ?1 and state != 'assembled'",
      [sqlight.text(source.id)],
    ),
  )
  use _ <- result.try(move_into_hands(connection, source.id, station.id))
  use sent <- result.try(send_kanbans(connection, branch_ends))
  Ok(#(#(source.id, source.reference), sent))
}

fn move_into_hands(
  connection: sqlight.Connection,
  piece_id: String,
  station_id: String,
) -> Result(Nil, FlowError) {
  write(
    connection,
    "update piece
        set state = 'in_flow', station_id = ?1, assignee = null,
            since = strftime('%Y-%m-%dT%H:%M:%SZ', 'now')
      where id = ?2",
    [sqlight.text(station_id), sqlight.text(piece_id)],
  )
}

fn send_kanbans(
  connection: sqlight.Connection,
  stations: List(String),
) -> Result(List(String), FlowError) {
  list.try_map(stations, fn(one) { send_kanban(connection, one) })
  |> result.map(option.values)
}

/// `nodes` is the whole Line, to follow its routes.
type Station {
  Station(
    id: String,
    branch: Option(String),
    inflow: shape.Inflow,
    nodes: List(shape.Node),
  )
}

/// `station_id` is the Work Station whose Blue Bin the Piece leaves; None from
/// the Backlog and at the Assembly.
type Source {
  Source(
    id: String,
    reference: String,
    demand: String,
    station_id: Option(String),
  )
}

type Held {
  Held(id: String, reference: String, demand: String, station_id: String)
}

fn load_station(
  connection: sqlight.Connection,
  station_id: String,
) -> Result(Station, FlowError) {
  use nodes <- result.try(
    shape.load(connection) |> result.replace_error(StoreFailed),
  )
  use node <- result.try(
    list.find(nodes, fn(node) { node.id == station_id })
    |> result.replace_error(UnknownStation),
  )
  use inflow <- result.try(
    shape.inflow(nodes, node) |> result.replace_error(StoreFailed),
  )
  Ok(Station(id: node.id, branch: node.branch, inflow:, nodes:))
}

fn last_position(connection: sqlight.Connection) -> Result(Int, FlowError) {
  one(
    connection,
    "select max(position) from work_station",
    [],
    decode.at([0], decode.int),
    or: UnknownStation,
  )
}

fn next_backlog_piece(
  connection: sqlight.Connection,
) -> Result(Source, FlowError) {
  case heijunka.load(connection) {
    Error(_) -> Error(StoreFailed)
    Ok(heijunka.Backlog(sequence: [], ..)) -> Error(NothingToPull)
    Ok(heijunka.Backlog(sequence: [next, ..], ..)) ->
      Ok(Source(
        id: next.piece.id,
        reference: next.piece.reference,
        demand: next.demand.label,
        station_id: None,
      ))
  }
}

fn next_upstream_piece(
  connection: sqlight.Connection,
  from: String,
) -> Result(Source, FlowError) {
  find_source(
    connection,
    "select p.id, p.reference, d.label, p.station_id
     from piece p
     join demand d on d.id = p.demand_id
     where p.state = 'in_bin' and p.station_id = ?1
     order by p.since, p.rowid
     limit 1",
    [sqlight.text(from)],
    NothingToPull,
  )
}

fn next_unsplit_piece(
  connection: sqlight.Connection,
  station: Station,
  from: String,
) -> Result(Source, FlowError) {
  find_source(
    connection,
    "select p.id, p.reference, d.label, p.station_id
     from piece p
     join demand d on d.id = p.demand_id
     where p.state = 'in_bin' and p.station_id = ?1
       and not exists (select 1 from piece s
                       where s.parent_id = p.id and s.branch = ?2)
     order by p.since, p.rowid
     limit 1",
    [
      sqlight.text(from),
      sqlight.nullable(sqlight.text, station.branch),
    ],
    NothingToPull,
  )
}

/// Every Sub-Piece waits in the last Blue Bin of its Branch; the Piece complete
/// the longest comes first.
fn next_complete_piece(
  connection: sqlight.Connection,
  ends: List(String),
) -> Result(Source, FlowError) {
  find_source(
    connection,
    "select p.id, p.reference, d.label, null
     from piece p
     join demand d on d.id = p.demand_id
     where p.state = 'split'
       and not exists (
         select 1 from piece s
         where s.parent_id = p.id and s.state != 'assembled'
           and not (s.state = 'in_bin'
                    and s.station_id in (select value from json_each(?1))))
     order by (select max(s.since) from piece s where s.parent_id = p.id),
              p.rowid
     limit 1",
    [sqlight.text(json.to_string(json.array(ends, json.string)))],
    NothingToAssemble,
  )
}

fn find_source(
  connection: sqlight.Connection,
  sql: String,
  values: List(sqlight.Value),
  when_none: FlowError,
) -> Result(Source, FlowError) {
  let decoder = {
    use id <- decode.field(0, decode.string)
    use reference <- decode.field(1, decode.string)
    use demand <- decode.field(2, decode.string)
    use station_id <- decode.field(3, decode.optional(decode.string))
    decode.success(Source(id:, reference:, demand:, station_id:))
  }
  one(connection, sql, values, decoder, or: when_none)
}

fn load_piece_at(
  connection: sqlight.Connection,
  piece_id: String,
  station_id: String,
  state: String,
) -> Result(Held, FlowError) {
  one(
    connection,
    "select p.id, p.reference, d.label, p.station_id
     from piece p
     join demand d on d.id = p.demand_id
     where p.id = ?1 and p.station_id = ?2 and p.state = ?3",
    [sqlight.text(piece_id), sqlight.text(station_id), sqlight.text(state)],
    held_decoder(),
    or: PieceNotHere,
  )
}

fn load_piece_in_last_bin(
  connection: sqlight.Connection,
  piece_id: String,
  last_position: Int,
) -> Result(Held, FlowError) {
  one(
    connection,
    "select p.id, p.reference, d.label, p.station_id
     from piece p
     join demand d on d.id = p.demand_id
     join work_station w on w.id = p.station_id
     where p.id = ?1 and p.state = 'in_bin' and w.position = ?2",
    [sqlight.text(piece_id), sqlight.int(last_position)],
    held_decoder(),
    or: PieceNotHere,
  )
}

fn held_decoder() -> decode.Decoder(Held) {
  use id <- decode.field(0, decode.string)
  use reference <- decode.field(1, decode.string)
  use demand <- decode.field(2, decode.string)
  use station_id <- decode.field(3, decode.string)
  decode.success(Held(id:, reference:, demand:, station_id:))
}

fn id_and_reference() -> decode.Decoder(#(String, String)) {
  use id <- decode.field(0, decode.string)
  use reference <- decode.field(1, decode.string)
  decode.success(#(id, reference))
}

fn oldest_kanban(
  connection: sqlight.Connection,
  station_id: String,
) -> Result(Option(String), FlowError) {
  maybe_one(
    connection,
    "select id from kanban where station_id = ?1
     order by created_at, rowid limit 1",
    [sqlight.text(station_id)],
    decode.at([0], decode.string),
  )
}

/// `kanban_sent` and `kanban_spent` date the Kanbans a Work Station holds,
/// for its Starvation Time.
fn spend_kanban(
  connection: sqlight.Connection,
  kanban: Option(String),
  station_id: String,
) -> Result(Nil, FlowError) {
  case kanban {
    None -> Ok(Nil)
    Some(id) -> {
      use _ <- result.try(
        write(connection, "delete from kanban where id = ?1", [sqlight.text(id)]),
      )
      record_event(
        connection,
        "kanban_spent",
        None,
        json.object([#("station", json.string(station_id))]),
      )
    }
  }
}

fn raised_an_open_rework(
  connection: sqlight.Connection,
  station_id: String,
) -> Result(Bool, FlowError) {
  exists(
    connection,
    "select count(*) from rework
     where raised_by = ?1 and closed_at is null",
    [sqlight.text(station_id)],
  )
}

/// A Team Member not of this Work Station leaves the Piece unassigned.
fn take_in_hand(
  connection: sqlight.Connection,
  piece_id: String,
  station_id: String,
  team_member: Option(String),
) -> Result(Option(String), FlowError) {
  case team_member {
    None -> Ok(None)
    Some(team_member) ->
      maybe_one(
        connection,
        "update piece
            set assignee = (select sp.team_member_id from station_team_member sp
                             where sp.station_id = ?2 and sp.team_member_id = ?3)
          where id = ?1
          returning assignee",
        [
          sqlight.text(piece_id),
          sqlight.text(station_id),
          sqlight.text(team_member),
        ],
        decode.at([0], decode.optional(decode.string)),
      )
      |> result.map(option.flatten)
  }
}

fn record_pass(
  connection: sqlight.Connection,
  piece_id: String,
  station_id: String,
) -> Result(Nil, FlowError) {
  write(
    connection,
    "insert or replace into piece_pass (piece_id, station_id, team_member_id)
     select ?1, ?2, assignee from piece where id = ?1",
    [sqlight.text(piece_id), sqlight.text(station_id)],
  )
}

/// The empty Blue Bins (F7) of the Work Station aliased `w`, as an SQL
/// expression. Negative when a Deviation already put a Piece over the count.
pub const free_blue_bins_sql =
  "w.blue_bins - (select count(*) from piece p
                  where p.station_id = w.id and p.state = 'in_bin')"

fn free_blue_bins(
  connection: sqlight.Connection,
  station_id: String,
) -> Result(Int, FlowError) {
  one(
    connection,
    "select " <> free_blue_bins_sql <> " from work_station w where w.id = ?1",
    [sqlight.text(station_id)],
    decode.at([0], decode.int),
    or: UnknownStation,
  )
}

/// Never more Kanbans than empty Blue Bins: at the limit the insert writes
/// nothing and answers None (F7).
fn send_kanban(
  connection: sqlight.Connection,
  station_id: String,
) -> Result(Option(String), FlowError) {
  use sent <- result.try(maybe_one(
    connection,
    "insert into kanban (id, station_id)
     select 'kb-' || lower(hex(randomblob(6))), ?1
     where (select count(*) from kanban k where k.station_id = ?1)
         < (select " <> free_blue_bins_sql <> "
            from work_station w where w.id = ?1)
     returning station_id",
    [sqlight.text(station_id)],
    decode.at([0], decode.string),
  ))
  case sent {
    None -> Ok(None)
    Some(station) -> {
      use _ <- result.try(record_event(
        connection,
        "kanban_sent",
        None,
        json.object([#("station", json.string(station))]),
      ))
      Ok(Some(station))
    }
  }
}

fn record_deviations(
  connection: sqlight.Connection,
  rules: List(Rule),
  station_id: String,
  piece_id: String,
  reason: Option(String),
) -> Result(List(Rule), FlowError) {
  use <- bool.guard(rules == [], Ok([]))
  case option.map(reason, string.trim) {
    None | Some("") -> Error(NeedsConfirmation(rules))
    Some(reason) -> {
      use _ <- result.try(
        list.try_map(rules, fn(rule) {
          record_deviation(connection, rule, station_id, piece_id, reason)
        }),
      )
      Ok(rules)
    }
  }
}

fn record_deviation(
  connection: sqlight.Connection,
  rule: Rule,
  station_id: String,
  piece_id: String,
  reason: String,
) -> Result(Nil, FlowError) {
  use _ <- result.try(
    write(
      connection,
      "insert into deviation (rule, station_id, piece_id, reason)
       values (?1, ?2, ?3, ?4)",
      [
        sqlight.text(rule_name(rule)),
        sqlight.text(station_id),
        sqlight.text(piece_id),
        sqlight.text(reason),
      ],
    ),
  )
  record_event(
    connection,
    "deviation",
    Some(piece_id),
    json.object([
      #("rule", json.string(rule_name(rule))),
      #("station", json.string(station_id)),
      #("reason", json.string(reason)),
    ]),
  )
}

fn record_event(
  connection: sqlight.Connection,
  kind: String,
  piece_id: Option(String),
  payload: json.Json,
) -> Result(Nil, FlowError) {
  write(
    connection,
    "insert into flow_event (kind, piece_id, payload) values (?1, ?2, ?3)",
    [
      sqlight.text(kind),
      sqlight.nullable(sqlight.text, piece_id),
      sqlight.text(json.to_string(payload)),
    ],
  )
}

fn write(
  connection: sqlight.Connection,
  sql: String,
  values: List(sqlight.Value),
) -> Result(Nil, FlowError) {
  rows(connection, sql, values, decode.dynamic) |> result.replace(Nil)
}

fn rows(
  connection: sqlight.Connection,
  sql: String,
  values: List(sqlight.Value),
  decoder: decode.Decoder(a),
) -> Result(List(a), FlowError) {
  sqlight.query(sql, on: connection, with: values, expecting: decoder)
  |> result.replace_error(StoreFailed)
}

fn one(
  connection: sqlight.Connection,
  sql: String,
  values: List(sqlight.Value),
  decoder: decode.Decoder(a),
  or none: FlowError,
) -> Result(a, FlowError) {
  use found <- result.try(rows(connection, sql, values, decoder))
  list.first(found) |> result.replace_error(none)
}

fn maybe_one(
  connection: sqlight.Connection,
  sql: String,
  values: List(sqlight.Value),
  decoder: decode.Decoder(a),
) -> Result(Option(a), FlowError) {
  rows(connection, sql, values, decoder)
  |> result.map(fn(found) { list.first(found) |> option.from_result })
}

/// Whether a `select count(*)` query counts more than zero.
fn exists(
  connection: sqlight.Connection,
  sql: String,
  values: List(sqlight.Value),
) -> Result(Bool, FlowError) {
  maybe_one(connection, sql, values, decode.at([0], decode.int))
  |> result.map(fn(count) { option.unwrap(count, 0) > 0 })
}

/// One action's state, flow event and Deviations commit together or not at
/// all (ADR-0002); a NeedsConfirmation rolls back too.
fn in_transaction(
  connection: sqlight.Connection,
  run: fn() -> Result(a, FlowError),
) -> Result(a, FlowError) {
  db.transaction(connection, fn(_) { StoreFailed }, run)
}
