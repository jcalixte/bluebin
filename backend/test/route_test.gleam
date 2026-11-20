import bluebin/db
import bluebin/flow
import bluebin/heijunka
import bluebin/line
import bluebin/route
import gleam/dynamic/decode
import gleam/list
import gleam/option.{None, Some}
import gleam/string
import sqlight

fn with_seeded_database(run: fn(sqlight.Connection) -> a) -> a {
  use connection <- db.with_connection_at(":memory:")
  let assert Ok(Nil) = db.prepare(connection, db.Demo)
  run(connection)
}

fn exec(connection: sqlight.Connection, sql: String) -> Nil {
  let assert Ok(Nil) = sqlight.exec(sql, connection)
  Nil
}

fn state_of(connection: sqlight.Connection, piece: String) -> String {
  let assert Ok([state]) =
    sqlight.query(
      "select state from piece where id = ?1",
      on: connection,
      with: [sqlight.text(piece)],
      expecting: decode.at([0], decode.string),
    )
  state
}

fn next_out(connection: sqlight.Connection) -> heijunka.Placed {
  let assert Ok(heijunka.Backlog(sequence: [next, ..], ..)) =
    heijunka.load(connection)
  next
}

pub fn a_piece_that_skips_the_first_work_station_leaves_the_backlog_later_test() {
  use connection <- with_seeded_database()
  // Tech Conception has nothing in the Blue Bin of Analysis.
  assert flow.pull(connection, "ws-conception", None, None)
    == Error(flow.NothingToPull)

  let next = next_out(connection)
  let assert Ok(Nil) = route.change(connection, next.piece.id, ["ws-analysis"])
  let assert Ok(pulled) = flow.pull(connection, "ws-conception", None, None)
  assert pulled.piece == next.piece.reference
  assert pulled.kanbans_sent_to == []

  // Analysis pulls the next Piece that goes through it instead.
  let after = next_out(connection)
  let assert Ok(at_analysis) = flow.pull(connection, "ws-analysis", None, None)
  assert at_analysis.piece == after.piece.reference
}

pub fn a_piece_that_skips_a_branch_splits_into_the_others_test() {
  use connection <- with_seeded_database()
  // CHK-9 waits in Tech Conception's Blue Bin: its route no longer changes.
  assert route.change(connection, "p-checkout-9", ["ws-web", "ws-qa-web"])
    == Error(route.NotInBacklog)
  exec(
    connection,
    "update piece set skips = '[\"ws-qa-web\",\"ws-web\"]'
      where id = 'p-checkout-9'",
  )

  assert flow.pull(connection, "ws-web", None, None)
    == Error(flow.NothingToPull)
  let assert Ok(_) = flow.pull(connection, "ws-ios", None, None)
  let assert Ok(android) = flow.pull(connection, "ws-android", None, None)
  assert android.kanbans_sent_to == ["ws-conception"]
  assert state_of(connection, "p-checkout-9") == "split"

  let why = Some("route test")
  let assert Ok(_) = flow.finish(connection, "ws-ios", "p-checkout-9-ios", why)
  let assert Ok(_) =
    flow.finish(connection, "ws-android", "p-checkout-9-android", why)
  // CHK-8 · iOS waited longer in the Blue Bin of iOS.
  let assert Ok(older) = flow.pull(connection, "ws-qa-ios", None, why)
  assert older.piece == "CHK-8 · iOS"
  let assert Ok(at_qa) = flow.pull(connection, "ws-qa-ios", None, why)
  assert at_qa.piece == "CHK-9 · iOS"
  let assert Ok(_) = flow.pull(connection, "ws-qa-android", None, why)
  let assert Ok(_) =
    flow.finish(connection, "ws-qa-ios", "p-checkout-9-ios", why)
  let assert Ok(_) =
    flow.finish(connection, "ws-qa-android", "p-checkout-9-android", why)

  let assert Ok(whole) = flow.pull(connection, "ws-uat", None, why)
  assert whole.piece == "CHK-9"
  assert list.sort(whole.kanbans_sent_to, string.compare)
    == ["ws-qa-android", "ws-qa-ios"]
  // QA Web never saw it, so it did not make its defect.
  assert flow.raise_rework(
      connection,
      "ws-uat",
      "p-checkout-9",
      "ws-qa-web",
      "Layout",
    )
    == Error(flow.NotUpstream)
}

pub fn a_piece_deploys_from_the_last_work_station_of_its_route_test() {
  use connection <- with_seeded_database()
  assert flow.deploy(connection, "p-checkout-9", hold: False)
    == Error(flow.PieceNotHere)
  assert deploys_here(connection, "ws-conception") == [False]

  let branches =
    "[\"ws-android\",\"ws-ios\",\"ws-qa-android\",\"ws-qa-ios\",\"ws-qa-web\",\"ws-uat\",\"ws-web\"]"
  exec(
    connection,
    "update piece set skips = '" <> branches <> "' where id = 'p-checkout-9'",
  )
  assert deploys_here(connection, "ws-conception") == [True]
  let assert Ok(deployed) = flow.deploy(connection, "p-checkout-9", hold: False)
  assert deployed.kanbans_sent_to == ["ws-conception"]
}

pub fn a_route_must_keep_the_assembly_test() {
  use connection <- with_seeded_database()
  let next = next_out(connection)
  let assert Error(route.Invalid(reason)) =
    route.change(connection, next.piece.id, ["ws-uat"])
  assert string.starts_with(reason, "UAT assembles")
  let assert Ok(Nil) = route.change(connection, next.piece.id, [])
  assert next_out(connection).piece.skips == []
}

fn deploys_here(connection: sqlight.Connection, station: String) -> List(Bool) {
  let assert Ok(stations) = line.load(connection)
  let assert Ok(found) = list.find(stations, fn(one) { one.id == station })
  found.blue_bins
  |> list.filter(fn(bin) { bin.id != None })
  |> list.map(fn(bin) { bin.deploys_here })
}
