import gleam/bool
import gleam/dynamic/decode
import gleam/json
import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/result
import gleam/string
import sqlight

/// A pull rule a Person is warned about, and breaks only as a Deviation with
/// its reason (F6, F9, F31).
pub type Rule {
  PullWithoutKanban
  SecondPieceInABlueBin
  /// Jidoka: while the Rework this Work Station raised is open, it repairs or
  /// helps downstream — it does not start another Piece (F14).
  PullWithAnOpenRework
}

pub type FlowError {
  UnknownStation
  NothingToPull
  /// The Work Station after the Branches finds no Piece whose Sub-Pieces all
  /// wait in the last Blue Bin of their Branch (F8).
  NothingToAssemble
  PieceNotHere
  /// The action breaks one or more rules: the Person must confirm it with a
  /// reason, which records one Deviation per rule broken.
  NeedsConfirmation(List(Rule))
  /// A defect is named against a Work Station that is not upstream of the one
  /// that found it; a Piece never moves backward.
  NotUpstream
  /// A Rework says in one line what the defect is.
  EmptyDescription
  /// No open Rework carries that id.
  UnknownRework
  /// The Person holds an open Rework: it comes first, before any new Piece.
  ReworkFirst
  /// An Assignment goes only to a Person of the Work Station it belongs to.
  NotOfStation
  StoreFailed
}

/// What one action changed: enough for the answer, and for the screens to say
/// what happened before they reload.
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
  }
}

/// The warning a Person reads before they decide (F6, F9).
pub fn rule_warning(rule: Rule) -> String {
  case rule {
    PullWithoutKanban ->
      "This Work Station holds no Kanban, so nothing downstream asked for a Piece. Pulling one anyway is a Deviation."
    SecondPieceInABlueBin ->
      "Every Blue Bin of this Work Station is full. Putting a second Piece in one is a Deviation."
    PullWithAnOpenRework ->
      "This Work Station found a defect and its Rework is still open. Starting another Piece before it is repaired is a Deviation."
  }
}

// --- The three actions ---

/// A Work Station spends one Kanban and takes the first Piece waiting in the
/// Blue Bins upstream — or in the Backlog, for the first Work Station (F24).
/// Emptying an upstream Blue Bin sends one Kanban back to it (F7).
///
/// Around a Split the pull changes shape. Each Branch pulls its own Sub-Piece,
/// and the Piece leaves the trunk's Blue Bin only once every Branch has pulled
/// its part. The Work Station after the Branches pulls by Assembly: all the
/// Sub-Pieces of one Piece at once, each from the last Blue Bin of its Branch.
pub fn pull(
  connection: sqlight.Connection,
  station_id: String,
  person: Option(String),
  reason: Option(String),
) -> Result(Flowed, FlowError) {
  use <- in_transaction(connection)
  use station <- result.try(load_station(connection, station_id))
  use repairing <- result.try(case person {
    None -> Ok(False)
    Some(person) -> holds_an_open_rework(connection, person, station.id)
  })
  use <- bool.guard(repairing, Error(ReworkFirst))
  use kind <- result.try(pull_kind(connection, station))

  use source <- result.try(next_source(connection, station, kind))

  use kanban <- result.try(oldest_kanban(connection, station.id))
  use open_rework <- result.try(has_an_open_rework(connection, station.id))
  let broken =
    list.append(
      case open_rework {
        True -> [PullWithAnOpenRework]
        False -> []
      },
      case kanban {
        None -> [PullWithoutKanban]
        Some(_) -> []
      },
    )
  use deviations <- result.try(record_deviations(
    connection,
    broken,
    station.id,
    source.id,
    reason,
  ))
  use _ <- result.try(spend_kanban(connection, kanban))

  use #(pulled, sent) <- result.try(case kind {
    FromBacklog | Straight -> take_whole(connection, station, source)
    AtSplit -> split_off(connection, station, source)
    Assembly -> assemble(connection, station, source)
  })
  // Taking a new Piece in hand puts the current one down (F32).
  use holder <- result.try(take_in_hand(
    connection,
    pulled.0,
    station.id,
    person,
  ))
  use _ <- result.try(case holder {
    None -> Ok([])
    Some(holder) -> pause_pieces(connection, holder, Some(pulled.0))
  })

  use _ <- result.try(record_event(
    connection,
    case kind {
      Assembly -> "piece_assembled"
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

/// A Work Station finishes a Piece and puts it in one of its Blue Bins, where
/// it waits for the downstream pull. A second Piece in one Blue Bin is a
/// Deviation (F9).
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

  // Who transformed the Piece here: the author a Rework goes to (F13), and
  // one more Piece out of this Work Station for its First Pass Yield (F16).
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

  // Free hands take up the Assignment they had put down (F32).
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

/// Production pulls a Piece out of the Blue Bin of the last Work Station: the
/// Piece reaches production, and the Work Station gets one Kanban back (F2).
pub fn deliver(
  connection: sqlight.Connection,
  piece_id: String,
) -> Result(Flowed, FlowError) {
  use <- in_transaction(connection)
  use last <- result.try(edge_position(connection, "max"))
  use piece <- result.try(load_piece_in_last_bin(connection, piece_id, last))

  use _ <- result.try(
    write(
      connection,
      "update piece
        set state = 'produced', station_id = null, assignee = null,
            produced_at = strftime('%Y-%m-%dT%H:%M:%SZ', 'now'),
            since = strftime('%Y-%m-%dT%H:%M:%SZ', 'now')
      where id = ?1",
      [sqlight.text(piece.id)],
    ),
  )

  use sent <- result.try(send_kanbans(connection, [piece.station_id]))

  use _ <- result.try(record_event(
    connection,
    "piece_reached_production",
    Some(piece.id),
    json.object([#("station", json.string(piece.station_id))]),
  ))

  Ok(Flowed(
    piece: piece.reference,
    demand: piece.demand,
    deviations: [],
    kanbans_sent_to: sent,
  ))
}

// --- Jidoka: a defect stops where it is found (F12, F13, F14, F32) ---

/// A Rework just raised: who repairs it, and what that Person put down.
pub type Raised {
  Raised(
    id: String,
    piece: String,
    demand: String,
    assignee: Option(String),
    paused: Option(String),
  )
}

/// A Rework just closed, and the Piece its author takes up again.
pub type Repaired {
  Repaired(piece: String, resumed: Option(String))
}

/// A Work Station finds a defect in the Piece it holds and names the Work
/// Station that made it (F12). The Piece never moves backward: it stays in
/// these hands, and the repair goes by default to its author — the Person who
/// transformed it at that Work Station — whose current Piece is paused so the
/// repair comes first (F13, F32).
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
  use <- bool.guard(!upstream_of(made_by, found_by), Error(NotUpstream))
  use piece <- result.try(load_piece_at(
    connection,
    piece_id,
    found_by.id,
    "in_flow",
  ))

  use author <- result.try(author_of(connection, piece.id, made_by.id))

  let opened =
    sqlight.query(
      "insert into rework (id, piece_id, station_id, description, raised_by,
                           assignee)
       values ('rw-' || lower(hex(randomblob(6))), ?1, ?2, ?3, ?4, ?5)
       returning id",
      on: connection,
      with: [
        sqlight.text(piece.id),
        sqlight.text(made_by.id),
        sqlight.text(description),
        sqlight.text(found_by.id),
        sqlight.nullable(sqlight.text, option.map(author, fn(one) { one.0 })),
      ],
      expecting: decode.at([0], decode.string),
    )
  use id <- result.try(case opened {
    Ok([id, ..]) -> Ok(id)
    _ -> Error(StoreFailed)
  })

  // The Rework becomes the author's active Assignment, unless another Rework
  // already is; their Piece in hand is put down either way.
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

/// The defect is repaired: the Rework closes, and its Person takes up their
/// next Assignment — another Rework, or the Piece they had put down.
pub fn repair_rework(
  connection: sqlight.Connection,
  rework_id: String,
) -> Result(Repaired, FlowError) {
  use <- in_transaction(connection)
  use #(piece_id, reference, assignee) <- result.try(load_open_rework(
    connection,
    rework_id,
  ))

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
    json.object([#("rework", json.string(rework_id))]),
  ))

  use settled <- result.try(settle_option(connection, assignee))
  Ok(Repaired(piece: reference, resumed: settled.resumed))
}

/// The open Rework with that id: its Piece, and who repairs it.
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
  let found =
    sqlight.query(
      "select r.piece_id, p.reference, r.assignee
         from rework r
         join piece p on p.id = r.piece_id
        where r.id = ?1 and r.closed_at is null",
      on: connection,
      with: [sqlight.text(rework_id)],
      expecting: decoder,
    )
  case found {
    Error(_) -> Error(StoreFailed)
    Ok([]) -> Error(UnknownRework)
    Ok([rework, ..]) -> Ok(rework)
  }
}

// --- Assignments: one active per Person, the rest paused (F21, F32) ---

/// What a Person's hands look like after a change.
pub type Settled {
  Settled(paused: List(String), resumed: Option(String))
}

/// What a Rework or a Piece in hand is, as an Assignment.
pub type AssignmentKind {
  ReworkAssignment
  PieceAssignment
}

/// An Assignment handed over to another Person of the same Work Station.
pub type Reassigned {
  Reassigned(piece: String, person: String)
}

/// Any Person of a Work Station hands one of its Assignments — a Piece in
/// hand or an open Rework — to another Person of that Work Station (F21). The
/// one who takes it puts down their current Piece; the one who gave it takes
/// up their next Assignment (F32).
pub fn reassign(
  connection: sqlight.Connection,
  kind: AssignmentKind,
  id: String,
  person_id: String,
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
  use name <- result.try(member_name(connection, station_id, person_id))
  use <- bool.guard(
    previous == Some(person_id),
    Ok(Reassigned(piece: reference, person: name)),
  )

  use _ <- result.try(
    write(
      connection,
      case kind {
        PieceAssignment -> "update piece set assignee = ?2 where id = ?1"
        ReworkAssignment -> "update rework set assignee = ?2 where id = ?1"
      },
      [sqlight.text(id), sqlight.text(person_id)],
    ),
  )
  use _ <- result.try(case in_flow {
    True -> pause_pieces(connection, person_id, Some(id)) |> result.replace(Nil)
    False -> Ok(Nil)
  })
  use _ <- result.try(settle(connection, person_id))
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
      #("to", json.string(person_id)),
    ]),
  ))
  Ok(Reassigned(piece: reference, person: name))
}

/// Puts a Person's hands in order: an open Rework comes first and is the one
/// active Assignment — every Piece they hold waits, paused. With no Rework,
/// free hands take up the paused Piece nearest to production, then the one
/// put down first (F18, F32).
fn settle(
  connection: sqlight.Connection,
  person_id: String,
) -> Result(Settled, FlowError) {
  let open =
    sqlight.query(
      "select count(*) from rework where assignee = ?1 and closed_at is null",
      on: connection,
      with: [sqlight.text(person_id)],
      expecting: decode.at([0], decode.int),
    )
  case open {
    Error(_) -> Error(StoreFailed)
    Ok([count, ..]) if count > 0 -> {
      use _ <- result.try(start_next_rework(connection, person_id))
      use paused <- result.try(pause_pieces(connection, person_id, None))
      Ok(Settled(paused:, resumed: None))
    }
    Ok(_) -> {
      use resumed <- result.try(resume_next_piece(connection, person_id))
      Ok(Settled(paused: [], resumed:))
    }
  }
}

fn settle_option(
  connection: sqlight.Connection,
  person_id: Option(String),
) -> Result(Settled, FlowError) {
  case person_id {
    None -> Ok(Settled(paused: [], resumed: None))
    Some(person_id) -> settle(connection, person_id)
  }
}

/// The oldest open Rework of the Person starts, unless one already runs: the
/// Rework Time counts from that moment (F16).
fn start_next_rework(
  connection: sqlight.Connection,
  person_id: String,
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
    [sqlight.text(person_id)],
  )
}

/// Every Piece the Person transforms, but `except`, is put down. Answers the
/// references of the Pieces paused.
fn pause_pieces(
  connection: sqlight.Connection,
  person_id: String,
  except: Option(String),
) -> Result(List(String), FlowError) {
  let paused =
    sqlight.query(
      "update piece set state = 'paused',
                        since = strftime('%Y-%m-%dT%H:%M:%SZ', 'now')
        where assignee = ?1 and state = 'in_flow' and id is not ?2
        returning id, reference",
      on: connection,
      with: [
        sqlight.text(person_id),
        sqlight.nullable(sqlight.text, except),
      ],
      expecting: {
        use id <- decode.field(0, decode.string)
        use reference <- decode.field(1, decode.string)
        decode.success(#(id, reference))
      },
    )
  use paused <- result.try(result.replace_error(paused, StoreFailed))
  list.try_map(paused, fn(piece) {
    use _ <- result.try(record_event(
      connection,
      "piece_paused",
      Some(piece.0),
      json.object([#("person", json.string(person_id))]),
    ))
    Ok(piece.1)
  })
}

/// With empty hands, the Person takes up the paused Piece nearest to
/// production, then the one put down first.
fn resume_next_piece(
  connection: sqlight.Connection,
  person_id: String,
) -> Result(Option(String), FlowError) {
  let resumed =
    sqlight.query(
      "update piece set state = 'in_flow',
                        since = strftime('%Y-%m-%dT%H:%M:%SZ', 'now')
        where id = (select p.id from piece p
                      join work_station w on w.id = p.station_id
                     where p.assignee = ?1 and p.state = 'paused'
                     order by w.position desc, p.since, p.rowid limit 1)
          and not exists (select 1 from piece
                           where assignee = ?1 and state = 'in_flow')
        returning id, reference",
      on: connection,
      with: [sqlight.text(person_id)],
      expecting: {
        use id <- decode.field(0, decode.string)
        use reference <- decode.field(1, decode.string)
        decode.success(#(id, reference))
      },
    )
  case resumed {
    Error(_) -> Error(StoreFailed)
    Ok([]) -> Ok(None)
    Ok([#(id, reference), ..]) -> {
      use _ <- result.try(record_event(
        connection,
        "piece_resumed",
        Some(id),
        json.object([#("person", json.string(person_id))]),
      ))
      Ok(Some(reference))
    }
  }
}

/// Whether the Person, being of this Work Station, still has a Rework to
/// repair: it comes before any new Piece (F18).
fn holds_an_open_rework(
  connection: sqlight.Connection,
  person_id: String,
  station_id: String,
) -> Result(Bool, FlowError) {
  let found =
    sqlight.query(
      "select count(*) from rework r
        where r.assignee = ?1 and r.closed_at is null
          and exists (select 1 from station_person sp
                       where sp.station_id = ?2 and sp.person_id = ?1)",
      on: connection,
      with: [sqlight.text(person_id), sqlight.text(station_id)],
      expecting: decode.at([0], decode.int),
    )
  case found {
    Ok([count, ..]) -> Ok(count > 0)
    Ok([]) -> Ok(False)
    Error(_) -> Error(StoreFailed)
  }
}

fn assignee_of(
  connection: sqlight.Connection,
  piece_id: String,
) -> Result(Option(String), FlowError) {
  let found =
    sqlight.query(
      "select assignee from piece where id = ?1",
      on: connection,
      with: [sqlight.text(piece_id)],
      expecting: decode.at([0], decode.optional(decode.string)),
    )
  case found {
    Ok([assignee, ..]) -> Ok(assignee)
    Ok([]) -> Ok(None)
    Error(_) -> Error(StoreFailed)
  }
}

/// A Piece in the hands of a Work Station, transformed or put down: its
/// reference, its Work Station, who holds it, and whether it is in flow.
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
  let found =
    sqlight.query(
      "select reference, station_id, assignee, state = 'in_flow' from piece
        where id = ?1 and station_id is not null
          and state in ('in_flow', 'paused')",
      on: connection,
      with: [sqlight.text(piece_id)],
      expecting: decoder,
    )
  case found {
    Error(_) -> Error(StoreFailed)
    Ok([]) -> Error(PieceNotHere)
    Ok([piece, ..]) -> Ok(piece)
  }
}

/// The Work Station a Rework stands against: its People repair it.
fn rework_station(
  connection: sqlight.Connection,
  rework_id: String,
) -> Result(String, FlowError) {
  let found =
    sqlight.query(
      "select station_id from rework where id = ?1",
      on: connection,
      with: [sqlight.text(rework_id)],
      expecting: decode.at([0], decode.string),
    )
  case found {
    Ok([station_id, ..]) -> Ok(station_id)
    Ok([]) -> Error(UnknownRework)
    Error(_) -> Error(StoreFailed)
  }
}

fn member_name(
  connection: sqlight.Connection,
  station_id: String,
  person_id: String,
) -> Result(String, FlowError) {
  let found =
    sqlight.query(
      "select pe.name from station_person sp
         join person pe on pe.id = sp.person_id
        where sp.station_id = ?1 and sp.person_id = ?2",
      on: connection,
      with: [sqlight.text(station_id), sqlight.text(person_id)],
      expecting: decode.at([0], decode.string),
    )
  case found {
    Ok([name, ..]) -> Ok(name)
    Ok([]) -> Error(NotOfStation)
    Error(_) -> Error(StoreFailed)
  }
}

/// Whether a Person of the Work Station can take its top Kanban now, with no
/// Deviation: a Kanban waits, no Rework it raised is open, and a Piece waits
/// upstream (F20).
pub fn can_pull(
  connection: sqlight.Connection,
  station_id: String,
) -> Result(Bool, FlowError) {
  use station <- result.try(load_station(connection, station_id))
  use kanban <- result.try(oldest_kanban(connection, station.id))
  use open_rework <- result.try(has_an_open_rework(connection, station.id))
  use <- bool.guard(kanban == None || open_rework, Ok(False))
  use kind <- result.try(pull_kind(connection, station))
  case next_source(connection, station, kind) {
    Ok(_) -> Ok(True)
    Error(NothingToPull) | Error(NothingToAssemble) -> Ok(False)
    Error(failure) -> Error(failure)
  }
}

/// A defect is named against a Work Station the Piece already crossed: an
/// earlier position, in the trunk or in the same Branch.
fn upstream_of(made_by: Station, found_by: Station) -> Bool {
  made_by.position < found_by.position
  && case made_by.branch, found_by.branch {
    Some(one), Some(other) -> one == other
    _, _ -> True
  }
}

/// The Person who transformed this Piece at that Work Station — of the Piece
/// itself, or of one of its Sub-Pieces when the defect was made in a Branch.
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
  let found =
    sqlight.query(
      "select pp.person_id, pe.name
         from piece_pass pp
         join person pe on pe.id = pp.person_id
        where pp.station_id = ?2
          and (pp.piece_id = ?1
               or pp.piece_id in (select s.id from piece s
                                   where s.parent_id = ?1))
        order by pp.at desc
        limit 1",
      on: connection,
      with: [sqlight.text(piece_id), sqlight.text(station_id)],
      expecting: decoder,
    )
  case found {
    Error(_) -> Error(StoreFailed)
    Ok([]) -> Ok(None)
    Ok([author, ..]) -> Ok(Some(author))
  }
}

// --- How a pull moves its Piece ---

/// Where a pull takes its Piece from, read from the shape of the chain.
type Kind {
  FromBacklog
  /// Inside the trunk, or inside one Branch.
  Straight
  /// A Branch pulls from the trunk: only its own Sub-Piece.
  AtSplit
  /// The Work Station after the Branches pulls every Sub-Piece of one Piece.
  Assembly
}

fn pull_kind(
  connection: sqlight.Connection,
  station: Station,
) -> Result(Kind, FlowError) {
  use first <- result.try(edge_position(connection, "min"))
  use <- bool.guard(station.position == first, Ok(FromBacklog))

  let upstream =
    sqlight.query(
      "select branch from work_station
       where position = (select max(position) from work_station
                         where position < ?1)",
      on: connection,
      with: [sqlight.int(station.position)],
      expecting: decode.at([0], decode.optional(decode.string)),
    )
  case upstream {
    Error(_) -> Error(StoreFailed)
    Ok(branches) ->
      case station.branch, list.any(branches, option.is_some) {
        Some(_), False -> Ok(AtSplit)
        None, True -> Ok(Assembly)
        _, _ -> Ok(Straight)
      }
  }
}

fn next_source(
  connection: sqlight.Connection,
  station: Station,
  kind: Kind,
) -> Result(Source, FlowError) {
  case kind {
    FromBacklog -> next_backlog_piece(connection)
    Straight -> next_upstream_piece(connection, station)
    AtSplit -> next_unsplit_piece(connection, station)
    Assembly -> next_complete_piece(connection, station)
  }
}

/// The whole Piece moves into the hands of the Work Station. Answers the id
/// and reference of what moved, and the Work Stations that got a Kanban back.
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

/// The Branch takes its own Sub-Piece. The Piece stays in the trunk's Blue
/// Bin, holding it, until the last Branch has taken its part; only then the
/// Blue Bin is empty and its Work Station gets a Kanban back.
fn split_off(
  connection: sqlight.Connection,
  station: Station,
  source: Source,
) -> Result(#(#(String, String), List(String)), FlowError) {
  let branch = option.unwrap(station.branch, "")
  let created =
    sqlight.query(
      "insert into piece (id, demand_id, reference, state, station_id, since,
                          parent_id, branch)
       select id || '-' || lower(replace(?2, ' ', '-')), demand_id,
              reference || ' · ' || ?2, 'in_flow', ?3,
              strftime('%Y-%m-%dT%H:%M:%SZ', 'now'), id, ?2
       from piece where id = ?1
       returning id, reference",
      on: connection,
      with: [
        sqlight.text(source.id),
        sqlight.text(branch),
        sqlight.text(station.id),
      ],
      expecting: {
        use id <- decode.field(0, decode.string)
        use reference <- decode.field(1, decode.string)
        decode.success(#(id, reference))
      },
    )
  use sub_piece <- result.try(case created {
    Ok([sub_piece, ..]) -> Ok(sub_piece)
    _ -> Error(StoreFailed)
  })

  let left =
    sqlight.query(
      "update piece
          set state = 'split', station_id = null,
              since = strftime('%Y-%m-%dT%H:%M:%SZ', 'now')
        where id = ?1
          and (select count(*) from piece s where s.parent_id = ?1)
           >= (select count(distinct branch) from work_station
               where position = ?2)
        returning id",
      on: connection,
      with: [sqlight.text(source.id), sqlight.int(station.position)],
      expecting: decode.at([0], decode.string),
    )
  use sent <- result.try(case left {
    Error(_) -> Error(StoreFailed)
    Ok([]) -> Ok([])
    Ok(_) -> send_kanbans(connection, option.values([source.station_id]))
  })
  Ok(#(sub_piece, sent))
}

/// The Sub-Pieces join again: each leaves the last Blue Bin of its Branch,
/// which sends that Work Station one Kanban, and the complete Piece goes into
/// the hands of the Work Station after the Branches.
fn assemble(
  connection: sqlight.Connection,
  station: Station,
  source: Source,
) -> Result(#(#(String, String), List(String)), FlowError) {
  let branch_ends =
    sqlight.query(
      "select station_id from piece where parent_id = ?1 order by branch",
      on: connection,
      with: [sqlight.text(source.id)],
      expecting: decode.at([0], decode.string),
    )
  use branch_ends <- result.try(result.replace_error(branch_ends, StoreFailed))

  use _ <- result.try(
    write(
      connection,
      "update piece
        set state = 'assembled', station_id = null, assignee = null,
            since = strftime('%Y-%m-%dT%H:%M:%SZ', 'now')
      where parent_id = ?1",
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

// --- The pieces the actions move ---

type Station {
  Station(id: String, position: Int, branch: Option(String), blue_bins: Int)
}

/// A Piece about to be pulled. `station_id` is the Work Station whose Blue Bin
/// it leaves, and is none when it leaves the Backlog.
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
  let decoder = {
    use id <- decode.field(0, decode.string)
    use position <- decode.field(1, decode.int)
    use branch <- decode.field(2, decode.optional(decode.string))
    use blue_bins <- decode.field(3, decode.int)
    decode.success(Station(id:, position:, branch:, blue_bins:))
  }
  let found =
    sqlight.query(
      "select id, position, branch, blue_bins from work_station where id = ?1",
      on: connection,
      with: [sqlight.text(station_id)],
      expecting: decoder,
    )
  case found {
    Error(_) -> Error(StoreFailed)
    Ok([]) -> Error(UnknownStation)
    Ok([station, ..]) -> Ok(station)
  }
}

/// The first or the last position of the chain, `"min"` or `"max"`.
fn edge_position(
  connection: sqlight.Connection,
  edge: String,
) -> Result(Int, FlowError) {
  let found =
    sqlight.query(
      "select " <> edge <> "(position) from work_station",
      on: connection,
      with: [],
      expecting: decode.at([0], decode.int),
    )
  case found {
    Ok([position, ..]) -> Ok(position)
    Ok([]) -> Error(UnknownStation)
    Error(_) -> Error(StoreFailed)
  }
}

/// The Piece the Backlog releases: only a Kanban of the first Work Station
/// takes it out (F24). Until the Heijunka Sequence exists (F23), the Backlog
/// keeps the order the Pieces were written in.
fn next_backlog_piece(
  connection: sqlight.Connection,
) -> Result(Source, FlowError) {
  find_source(
    connection,
    "select p.id, p.reference, d.label, null
     from piece p
     join demand d on d.id = p.demand_id
     where p.state = 'backlog' and p.parent_id is null
     order by p.rowid
     limit 1",
    [],
    NothingToPull,
  )
}

/// The Piece that has waited longest in a Blue Bin of the step just upstream,
/// in the trunk or in the same Branch.
fn next_upstream_piece(
  connection: sqlight.Connection,
  station: Station,
) -> Result(Source, FlowError) {
  find_source(
    connection,
    "select p.id, p.reference, d.label, p.station_id
     from piece p
     join demand d on d.id = p.demand_id
     join work_station w on w.id = p.station_id
     where p.state = 'in_bin'
       and w.position = (select max(position) from work_station
                         where position < ?1)
       and w.branch is ?2
     order by p.since, p.rowid
     limit 1",
    [
      sqlight.int(station.position),
      sqlight.nullable(sqlight.text, station.branch),
    ],
    NothingToPull,
  )
}

/// At the Split: the Piece that has waited longest in the trunk's Blue Bins
/// and whose Sub-Piece for this Branch is not pulled yet.
fn next_unsplit_piece(
  connection: sqlight.Connection,
  station: Station,
) -> Result(Source, FlowError) {
  find_source(
    connection,
    "select p.id, p.reference, d.label, p.station_id
     from piece p
     join demand d on d.id = p.demand_id
     join work_station w on w.id = p.station_id
     where p.state = 'in_bin'
       and w.position = (select max(position) from work_station
                         where position < ?1)
       and not exists (select 1 from piece s
                       where s.parent_id = p.id and s.branch = ?2)
     order by p.since, p.rowid
     limit 1",
    [
      sqlight.int(station.position),
      sqlight.nullable(sqlight.text, station.branch),
    ],
    NothingToPull,
  )
}

/// At the Assembly: the Piece whose Sub-Pieces all wait in the last Blue Bin
/// of their Branch, the one complete for the longest time first.
fn next_complete_piece(
  connection: sqlight.Connection,
  station: Station,
) -> Result(Source, FlowError) {
  find_source(
    connection,
    "select p.id, p.reference, d.label, null
     from piece p
     join demand d on d.id = p.demand_id
     where p.state = 'split'
       and not exists (
         select 1 from piece s
         left join work_station w on w.id = s.station_id
         where s.parent_id = p.id
           and not (s.state = 'in_bin'
                    and w.position = (select max(position) from work_station
                                      where position < ?1)))
     order by (select max(s.since) from piece s where s.parent_id = p.id),
              p.rowid
     limit 1",
    [sqlight.int(station.position)],
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
  case sqlight.query(sql, on: connection, with: values, expecting: decoder) {
    Error(_) -> Error(StoreFailed)
    Ok([]) -> Error(when_none)
    Ok([piece, ..]) -> Ok(piece)
  }
}

fn load_piece_at(
  connection: sqlight.Connection,
  piece_id: String,
  station_id: String,
  state: String,
) -> Result(Held, FlowError) {
  let found =
    sqlight.query(
      "select p.id, p.reference, d.label, p.station_id
       from piece p
       join demand d on d.id = p.demand_id
       where p.id = ?1 and p.station_id = ?2 and p.state = ?3",
      on: connection,
      with: [
        sqlight.text(piece_id),
        sqlight.text(station_id),
        sqlight.text(state),
      ],
      expecting: held_decoder(),
    )
  case found {
    Error(_) -> Error(StoreFailed)
    Ok([]) -> Error(PieceNotHere)
    Ok([piece, ..]) -> Ok(piece)
  }
}

fn load_piece_in_last_bin(
  connection: sqlight.Connection,
  piece_id: String,
  last_position: Int,
) -> Result(Held, FlowError) {
  let found =
    sqlight.query(
      "select p.id, p.reference, d.label, p.station_id
       from piece p
       join demand d on d.id = p.demand_id
       join work_station w on w.id = p.station_id
       where p.id = ?1 and p.state = 'in_bin' and w.position = ?2",
      on: connection,
      with: [sqlight.text(piece_id), sqlight.int(last_position)],
      expecting: held_decoder(),
    )
  case found {
    Error(_) -> Error(StoreFailed)
    Ok([]) -> Error(PieceNotHere)
    Ok([piece, ..]) -> Ok(piece)
  }
}

fn held_decoder() -> decode.Decoder(Held) {
  use id <- decode.field(0, decode.string)
  use reference <- decode.field(1, decode.string)
  use demand <- decode.field(2, decode.string)
  use station_id <- decode.field(3, decode.string)
  decode.success(Held(id:, reference:, demand:, station_id:))
}

// --- Kanbans, Blue Bins and Deviations ---

/// The oldest Kanban of the Work Station, the one a pull spends. None means
/// nothing downstream asked for a Piece: pulling anyway is a Deviation (F6).
fn oldest_kanban(
  connection: sqlight.Connection,
  station_id: String,
) -> Result(Option(String), FlowError) {
  let oldest =
    sqlight.query(
      "select id from kanban where station_id = ?1
       order by created_at, rowid limit 1",
      on: connection,
      with: [sqlight.text(station_id)],
      expecting: decode.at([0], decode.string),
    )
  case oldest {
    Error(_) -> Error(StoreFailed)
    Ok([]) -> Ok(None)
    Ok([kanban, ..]) -> Ok(Some(kanban))
  }
}

fn spend_kanban(
  connection: sqlight.Connection,
  kanban: Option(String),
) -> Result(Nil, FlowError) {
  case kanban {
    None -> Ok(Nil)
    Some(id) ->
      write(connection, "delete from kanban where id = ?1", [sqlight.text(id)])
  }
}

/// Whether the Work Station is waiting on a defect it found itself: until the
/// repair is done, it does not start another Piece (F14).
fn has_an_open_rework(
  connection: sqlight.Connection,
  station_id: String,
) -> Result(Bool, FlowError) {
  let open =
    sqlight.query(
      "select count(*) from rework
       where raised_by = ?1 and closed_at is null",
      on: connection,
      with: [sqlight.text(station_id)],
      expecting: decode.at([0], decode.int),
    )
  case open {
    Ok([count, ..]) -> Ok(count > 0)
    Ok([]) -> Ok(False)
    Error(_) -> Error(StoreFailed)
  }
}

/// The Person of the Work Station who takes the Piece in hand, answered back.
/// A name that is not of this Work Station leaves the Piece unassigned.
fn take_in_hand(
  connection: sqlight.Connection,
  piece_id: String,
  station_id: String,
  person: Option(String),
) -> Result(Option(String), FlowError) {
  case person {
    None -> Ok(None)
    Some(person) -> {
      let taken =
        sqlight.query(
          "update piece
              set assignee = (select sp.person_id from station_person sp
                               where sp.station_id = ?2 and sp.person_id = ?3)
            where id = ?1
            returning assignee",
          on: connection,
          with: [
            sqlight.text(piece_id),
            sqlight.text(station_id),
            sqlight.text(person),
          ],
          expecting: decode.at([0], decode.optional(decode.string)),
        )
      case taken {
        Ok([holder, ..]) -> Ok(holder)
        Ok([]) -> Ok(None)
        Error(_) -> Error(StoreFailed)
      }
    }
  }
}

/// One Piece more out of this Work Station, by the Person who transformed it.
fn record_pass(
  connection: sqlight.Connection,
  piece_id: String,
  station_id: String,
) -> Result(Nil, FlowError) {
  write(
    connection,
    "insert or replace into piece_pass (piece_id, station_id, person_id)
     select ?1, ?2, assignee from piece where id = ?1",
    [sqlight.text(piece_id), sqlight.text(station_id)],
  )
}

/// How many Blue Bins of the Work Station hold no Piece. Negative is possible:
/// a Deviation already put a Piece over the count.
fn free_blue_bins(
  connection: sqlight.Connection,
  station_id: String,
) -> Result(Int, FlowError) {
  let found =
    sqlight.query(
      "select w.blue_bins - (select count(*) from piece p
                             where p.station_id = w.id and p.state = 'in_bin')
       from work_station w where w.id = ?1",
      on: connection,
      with: [sqlight.text(station_id)],
      expecting: decode.at([0], decode.int),
    )
  case found {
    Ok([free, ..]) -> Ok(free)
    Ok([]) -> Error(UnknownStation)
    Error(_) -> Error(StoreFailed)
  }
}

/// One more Kanban for the Work Station whose Blue Bin just emptied — never
/// more Kanbans than its empty Blue Bins, so the insert checks the count
/// itself and answers nothing when the limit is already reached (F7).
fn send_kanban(
  connection: sqlight.Connection,
  station_id: String,
) -> Result(Option(String), FlowError) {
  let sent =
    sqlight.query(
      "insert into kanban (id, station_id)
       select 'kb-' || lower(hex(randomblob(6))), ?1
       where (select count(*) from kanban k where k.station_id = ?1)
           < (select w.blue_bins - (select count(*) from piece p
                                    where p.station_id = w.id
                                      and p.state = 'in_bin')
              from work_station w where w.id = ?1)
       returning station_id",
      on: connection,
      with: [sqlight.text(station_id)],
      expecting: decode.at([0], decode.string),
    )
  case sent {
    Error(_) -> Error(StoreFailed)
    Ok([]) -> Ok(None)
    Ok([station, ..]) -> Ok(Some(station))
  }
}

/// Record every rule the action breaks, with the one-line reason the Person
/// gave (F31). With no reason, nothing is written and the caller is asked to
/// confirm first; an action that breaks no rule asks for nothing.
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
  case
    sqlight.query(sql, on: connection, with: values, expecting: decode.dynamic)
  {
    Ok(_) -> Ok(Nil)
    Error(_) -> Error(StoreFailed)
  }
}

/// The current state, the flow event and the Deviation of one action are
/// written together or not at all (ADR-0002). A rule that needs confirming
/// rolls back too, so a warning never leaves a half-written action behind.
fn in_transaction(
  connection: sqlight.Connection,
  run: fn() -> Result(a, FlowError),
) -> Result(a, FlowError) {
  case sqlight.exec("begin immediate;", connection) {
    Error(_) -> Error(StoreFailed)
    Ok(Nil) ->
      case run() {
        Ok(value) ->
          case sqlight.exec("commit;", connection) {
            Ok(Nil) -> Ok(value)
            Error(_) -> Error(StoreFailed)
          }
        Error(failure) -> {
          let _ = sqlight.exec("rollback;", connection)
          Error(failure)
        }
      }
  }
}
