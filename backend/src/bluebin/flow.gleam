import gleam/dynamic/decode
import gleam/json
import gleam/option.{type Option, None, Some}
import gleam/result
import gleam/string
import sqlight

/// A pull rule a Person is warned about, and breaks only as a Deviation with
/// its reason (F6, F9, F31).
pub type Rule {
  PullWithoutKanban
  SecondPieceInABlueBin
}

pub type FlowError {
  UnknownStation
  NothingToPull
  PieceNotHere
  /// The action breaks a pull rule: the Person must confirm it with a reason.
  NeedsConfirmation(Rule)
  StoreFailed
}

/// What one action changed: enough for the answer, and for the screens to say
/// what happened before they reload.
pub type Flowed {
  Flowed(
    piece: String,
    demand: String,
    deviation: Option(Rule),
    kanban_sent_to: Option(String),
  )
}

pub fn rule_name(rule: Rule) -> String {
  case rule {
    PullWithoutKanban -> "pull_without_kanban"
    SecondPieceInABlueBin -> "second_piece_in_a_blue_bin"
  }
}

/// The warning a Person reads before they decide (F6, F9).
pub fn rule_warning(rule: Rule) -> String {
  case rule {
    PullWithoutKanban ->
      "This Work Station holds no Kanban, so nothing downstream asked for a Piece. Pulling one anyway is a Deviation."
    SecondPieceInABlueBin ->
      "Every Blue Bin of this Work Station is full. Putting a second Piece in one is a Deviation."
  }
}

// --- The three actions ---

/// A Work Station spends one Kanban and takes the first Piece waiting in the
/// Blue Bins upstream — or in the Backlog, for the first Work Station (F24).
/// Emptying an upstream Blue Bin sends one Kanban back to it (F7).
pub fn pull(
  connection: sqlight.Connection,
  station_id: String,
  reason: Option(String),
) -> Result(Flowed, FlowError) {
  use <- in_transaction(connection)
  use station <- result.try(load_station(connection, station_id))
  use first <- result.try(edge_position(connection, "min"))

  use source <- result.try(case station.position == first {
    True -> next_backlog_piece(connection)
    False -> next_upstream_piece(connection, station)
  })

  use deviation <- result.try(spend_kanban(connection, station, source, reason))

  use _ <- result.try(
    write(
      connection,
      "update piece
        set state = 'in_flow', station_id = ?1, assignee = null,
            since = strftime('%Y-%m-%dT%H:%M:%SZ', 'now')
      where id = ?2",
      [sqlight.text(station.id), sqlight.text(source.id)],
    ),
  )

  use sent <- result.try(case source.station_id {
    Some(upstream) -> send_kanban(connection, upstream)
    None -> Ok(None)
  })

  use _ <- result.try(record_event(
    connection,
    "piece_pulled",
    Some(source.id),
    json.object([
      #("station", json.string(station.id)),
      #("from", json.nullable(source.station_id, json.string)),
    ]),
  ))

  Ok(Flowed(
    piece: source.reference,
    demand: source.demand,
    deviation:,
    kanban_sent_to: sent,
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
  use deviation <- result.try(case free > 0 {
    True -> Ok(None)
    False ->
      record_deviation(
        connection,
        SecondPieceInABlueBin,
        station.id,
        piece.id,
        reason,
      )
  })

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

  Ok(Flowed(
    piece: piece.reference,
    demand: piece.demand,
    deviation:,
    kanban_sent_to: None,
  ))
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

  use sent <- result.try(send_kanban(connection, piece.station_id))

  use _ <- result.try(record_event(
    connection,
    "piece_reached_production",
    Some(piece.id),
    json.object([#("station", json.string(piece.station_id))]),
  ))

  Ok(Flowed(
    piece: piece.reference,
    demand: piece.demand,
    deviation: None,
    kanban_sent_to: sent,
  ))
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
  let decoder = {
    use id <- decode.field(0, decode.string)
    use reference <- decode.field(1, decode.string)
    use demand <- decode.field(2, decode.string)
    decode.success(Source(id:, reference:, demand:, station_id: None))
  }
  let found =
    sqlight.query(
      "select p.id, p.reference, d.label
       from piece p
       join demand d on d.id = p.demand_id
       where p.state = 'backlog'
       order by p.rowid
       limit 1",
      on: connection,
      with: [],
      expecting: decoder,
    )
  case found {
    Error(_) -> Error(StoreFailed)
    Ok([]) -> Error(NothingToPull)
    Ok([piece, ..]) -> Ok(piece)
  }
}

/// The Piece that has waited longest in a Blue Bin of the step just upstream.
/// Inside a Branch a Work Station pulls from its own Branch; the trunk feeds
/// every Branch, and the Work Station after the Branches may take any of them
/// until the Assembly exists (F8).
fn next_upstream_piece(
  connection: sqlight.Connection,
  station: Station,
) -> Result(Source, FlowError) {
  let decoder = {
    use id <- decode.field(0, decode.string)
    use reference <- decode.field(1, decode.string)
    use demand <- decode.field(2, decode.string)
    use station_id <- decode.field(3, decode.string)
    decode.success(Source(
      id:,
      reference:,
      demand:,
      station_id: Some(station_id),
    ))
  }
  let found =
    sqlight.query(
      "select p.id, p.reference, d.label, p.station_id
       from piece p
       join demand d on d.id = p.demand_id
       join work_station w on w.id = p.station_id
       where p.state = 'in_bin'
         and w.position = (select max(position) from work_station
                           where position < ?1)
         and (?2 is null or w.branch is null or w.branch = ?2)
       order by p.since, p.rowid
       limit 1",
      on: connection,
      with: [
        sqlight.int(station.position),
        sqlight.nullable(sqlight.text, station.branch),
      ],
      expecting: decoder,
    )
  case found {
    Error(_) -> Error(StoreFailed)
    Ok([]) -> Error(NothingToPull)
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

/// Spend the oldest Kanban of the Work Station. With none, the pull breaks a
/// rule: it needs a confirmed reason, and becomes a Deviation (F6).
fn spend_kanban(
  connection: sqlight.Connection,
  station: Station,
  source: Source,
  reason: Option(String),
) -> Result(Option(Rule), FlowError) {
  let oldest =
    sqlight.query(
      "select id from kanban where station_id = ?1
       order by created_at, rowid limit 1",
      on: connection,
      with: [sqlight.text(station.id)],
      expecting: decode.at([0], decode.string),
    )

  case oldest {
    Error(_) -> Error(StoreFailed)
    Ok([kanban, ..]) -> {
      use _ <- result.try(
        write(connection, "delete from kanban where id = ?1", [
          sqlight.text(kanban),
        ]),
      )
      Ok(None)
    }
    Ok([]) ->
      record_deviation(
        connection,
        PullWithoutKanban,
        station.id,
        source.id,
        reason,
      )
  }
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

/// Record a broken rule with the one-line reason the Person gave (F31). With
/// no reason, nothing is written and the caller is asked to confirm first.
fn record_deviation(
  connection: sqlight.Connection,
  rule: Rule,
  station_id: String,
  piece_id: String,
  reason: Option(String),
) -> Result(Option(Rule), FlowError) {
  case option.map(reason, string.trim) {
    None | Some("") -> Error(NeedsConfirmation(rule))
    Some(reason) -> {
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
      use _ <- result.try(record_event(
        connection,
        "deviation",
        Some(piece_id),
        json.object([
          #("rule", json.string(rule_name(rule))),
          #("station", json.string(station_id)),
          #("reason", json.string(reason)),
        ]),
      ))
      Ok(Some(rule))
    }
  }
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
