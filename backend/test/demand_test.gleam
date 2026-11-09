import bluebin/calendar.{Calendar, Holiday}
import bluebin/db
import bluebin/demand.{type Demand, Demand, Forecast}
import bluebin/demand_code
import bluebin/design
import bluebin/flow
import bluebin/heijunka
import bluebin/measures
import gleam/dynamic/decode
import gleam/json
import gleam/list
import gleam/option.{None, Some}
import gleam/string
import sqlight

fn with_seeded_database(run: fn(sqlight.Connection) -> a) -> a {
  use connection <- db.with_connection_at(":memory:")
  let assert Ok(Nil) = db.prepare(connection, db.Demo)
  run(connection)
}

fn count(connection: sqlight.Connection, sql: String) -> Int {
  let assert Ok([value]) =
    sqlight.query(
      sql,
      on: connection,
      with: [],
      expecting: decode.at([0], decode.int),
    )
  value
}

fn text(connection: sqlight.Connection, sql: String) -> String {
  let assert Ok([value]) =
    sqlight.query(
      sql,
      on: connection,
      with: [],
      expecting: decode.at([0], decode.string),
    )
  value
}

fn exec(connection: sqlight.Connection, sql: String) -> Nil {
  let assert Ok(Nil) = sqlight.exec(sql, connection)
  Nil
}

fn today(connection: sqlight.Connection) -> String {
  text(connection, "select date('now')")
}

fn refused(result: Result(a, demand.CreateError), words: String) -> Bool {
  case result {
    Error(demand.Invalid(reason)) -> string.contains(reason, words)
    _ -> False
  }
}

pub fn a_new_demand_is_checked_before_anything_is_written_test() {
  use connection <- with_seeded_database()
  let due = today(connection)
  let create = fn(label, client, due_on, pieces) {
    demand.create(connection, label, client, due_on, pieces, None)
  }
  assert refused(create("  ", "Retail", due, 3), "label")
  assert refused(create(string.repeat("a", 61), "Retail", due, 3), "longer")
  assert refused(create("Search", " ", due, 3), "Client")
  assert refused(create("Search", "Retail", "2020-01-01", 3), "past")
  assert refused(create("Search", "Retail", "31/12/2026", 3), "2026-12-31")
  assert refused(create("Search", "Retail", "2026-02-30", 3), "2026-12-31")
  assert refused(create("Search", "Retail", due, 0), "1 to 200")
  assert refused(create("Search", "Retail", due, 201), "1 to 200")
  assert count(connection, "select count(*) from demand") == 3
  assert count(
      connection,
      "select count(*) from flow_event
      where kind = 'demand_entered'",
    )
    == 0
}

pub fn a_new_demand_puts_its_pieces_in_the_backlog_test() {
  use connection <- with_seeded_database()
  let assert Ok(id) =
    demand.create(
      connection,
      "  Search  ",
      "Retail",
      today(connection),
      3,
      None,
    )
  assert text(connection, "select label || '/' || state || '/' || started_on
      from demand where id = '" <> id <> "'") == "Search/active/"
    <> today(connection)
  let assert Ok(references) =
    sqlight.query(
      "select reference from piece
        where demand_id = ?1 and state = 'backlog' and parent_id is null
          and entered_at is not null and urgent is null
        order by rowid",
      on: connection,
      with: [sqlight.text(id)],
      expecting: decode.at([0], decode.string),
    )
  assert references == ["SEA-1", "SEA-2", "SEA-3"]
  assert count(connection, "select count(*) from flow_event
      where kind = 'demand_entered'
        and json_extract(payload, '$.demand') = '" <> id <> "'") == 1

  let assert Ok(backlog) = heijunka.load(connection)
  assert list.count(backlog.sequence, fn(placed) { placed.demand.id == id })
    == 3
}

pub fn the_proposed_code_takes_the_initials_of_the_demand_label_test() {
  assert demand_code.propose("Checkout redesign", []) == "CR"
  assert demand_code.propose("  offline   mode for the field app ", [])
    == "OMFT"
  assert demand_code.propose("Billing", []) == "BIL"
  assert demand_code.propose("Évolution 2026", []) == "VOL"
  assert demand_code.propose("X", []) == "XD"
  assert demand_code.propose("2026", []) == "DM"
  assert demand_code.propose("Checkout redesign", ["CR", "CRA"]) == "CRB"
}

pub fn a_demand_code_has_two_to_four_letters_test() {
  assert demand_code.check(" chk ") == Ok("CHK")
  let assert Error(_) = demand_code.check("C")
  let assert Error(_) = demand_code.check("CHECK")
  let assert Error(_) = demand_code.check("Q3")
  let assert Error(_) = demand_code.check("C-K")
}

fn references_of(
  connection: sqlight.Connection,
  demand: String,
) -> List(String) {
  let assert Ok(references) =
    sqlight.query(
      "select reference from piece where demand_id = ?1 order by rowid",
      on: connection,
      with: [sqlight.text(demand)],
      expecting: decode.at([0], decode.string),
    )
  references
}

pub fn a_demand_takes_the_code_it_is_given_test() {
  use connection <- with_seeded_database()
  let assert Ok(id) =
    demand.create(
      connection,
      "Search",
      "Retail",
      today(connection),
      2,
      Some(" srch"),
    )
  assert references_of(connection, id) == ["SRCH-1", "SRCH-2"]
}

pub fn no_two_active_demands_have_the_same_code_test() {
  use connection <- with_seeded_database()
  let assert Error(demand.Invalid(reason)) =
    demand.create(
      connection,
      "Search",
      "Retail",
      today(connection),
      2,
      Some("CHK"),
    )
  assert reason == "CHK is already the code of \"Checkout redesign\"."
  let assert Error(demand.Invalid(_)) =
    demand.change_code(connection, "d-offline", "chk")

  // The proposal steps around a code in use, and a delivered Demand frees
  // its code.
  let assert Ok(id) =
    demand.create(connection, "Checkout", "Retail", today(connection), 1, None)
  assert references_of(connection, id) == ["CHE-1"]
  exec(
    connection,
    "update demand set state = 'delivered' where id = 'd-checkout'",
  )
  let assert Ok(Nil) = demand.change_code(connection, "d-offline", "CHK")
}

pub fn a_new_code_changes_every_reference_of_the_demand_test() {
  use connection <- with_seeded_database()
  let assert Ok(Nil) = demand.change_code(connection, "d-offline", "sync")
  let references = references_of(connection, "d-offline")
  assert list.contains(references, "SYNC-1")
  assert list.contains(references, "SYNC-10")
  assert list.contains(references, "SYNC-4 · iOS")
  assert !list.any(references, string.starts_with(_, "OFF"))
  assert references_of(connection, "d-checkout") |> list.contains("CHK-9")
  let assert Error(demand.Invalid(_)) =
    demand.change_code(connection, "d-unknown", "ZZ")
}

fn put_in_last_blue_bin(connection: sqlight.Connection, piece: String) -> Nil {
  exec(connection, "delete from kanban where station_id = 'ws-uat'")
  exec(connection, "update piece set state = 'in_bin', station_id = 'ws-uat'
     where id = '" <> piece <> "'")
}

pub fn the_last_deployed_piece_delivers_the_demand_test() {
  use connection <- with_seeded_database()
  let assert Ok(id) =
    demand.create(connection, "Search", "Retail", today(connection), 2, None)
  let pieces = "p-" <> string.drop_start(id, 2)
  let state = "select state from demand where id = '" <> id <> "'"
  let delivered =
    "select count(*) from flow_event where kind = 'demand_delivered'"

  put_in_last_blue_bin(connection, pieces <> "-1")
  let assert Ok(_) = flow.deploy(connection, pieces <> "-1", hold: False)
  assert text(connection, state) == "active"
  assert count(connection, delivered) == 0

  put_in_last_blue_bin(connection, pieces <> "-2")
  let assert Ok(_) = flow.deploy(connection, pieces <> "-2", hold: False)
  assert text(connection, state) == "delivered"
  assert count(connection, delivered) == 1
  let assert Ok(active) = demand.list_active(connection)
  assert !list.any(active, fn(one) { one.id == id })
}

pub fn a_piece_of_an_unfinished_demand_does_not_deliver_it_test() {
  use connection <- with_seeded_database()
  put_in_last_blue_bin(connection, "p-billing-3")
  let assert Ok(_) = flow.deploy(connection, "p-billing-3", hold: False)
  assert text(connection, "select state from demand where id = 'd-billing'")
    == "active"
}

pub fn deploying_a_piece_releases_it_at_the_same_moment_test() {
  use connection <- with_seeded_database()
  put_in_last_blue_bin(connection, "p-billing-3")
  let assert Ok(_) = flow.deploy(connection, "p-billing-3", hold: False)
  assert count(
      connection,
      "select count(*) from piece where id = 'p-billing-3'
         and released_at is not null and released_at = deployed_at",
    )
    == 1
  assert count(
      connection,
      "select count(*) from flow_event
        where kind = 'piece_released' and piece_id = 'p-billing-3'",
    )
    == 1
}

pub fn a_piece_deployed_with_hold_waits_for_its_release_test() {
  use connection <- with_seeded_database()
  let assert Ok(id) =
    demand.create(connection, "Search", "Retail", today(connection), 1, None)
  let piece = "p-" <> string.drop_start(id, 2) <> "-1"
  put_in_last_blue_bin(connection, piece)
  let assert Ok(flowed) = flow.deploy(connection, piece, hold: True)
  // The Piece left the Line: its Blue Bin is free, so UAT gets a Kanban.
  assert flowed.kanbans_sent_to == ["ws-uat"]
  assert count(
      connection,
      "select count(*) from piece where id = '" <> piece <> "'
         and state = 'deployed' and deployed_at is not null
         and released_at is null",
    )
    == 1
  assert count(
      connection,
      "select count(*) from flow_event where kind = 'piece_released'
         and piece_id = '" <> piece <> "'",
    )
    == 0
  assert text(connection, "select state from demand where id = '" <> id <> "'")
    == "active"
  let assert Ok([held]) = flow.held_for_release(connection)
  assert held.id == piece
  assert held.demand == id
}

pub fn releasing_the_held_pieces_delivers_the_demand_test() {
  use connection <- with_seeded_database()
  let assert Ok(id) =
    demand.create(connection, "Search", "Retail", today(connection), 2, None)
  let pieces = "p-" <> string.drop_start(id, 2)
  put_in_last_blue_bin(connection, pieces <> "-1")
  let assert Ok(_) = flow.deploy(connection, pieces <> "-1", hold: True)
  put_in_last_blue_bin(connection, pieces <> "-2")
  let assert Ok(_) = flow.deploy(connection, pieces <> "-2", hold: True)

  let assert Ok(2) = flow.release(connection, [pieces <> "-1", pieces <> "-2"])
  assert count(
      connection,
      "select count(*) from flow_event where kind = 'piece_released'
         and piece_id like '" <> pieces <> "-%'",
    )
    == 2
  assert text(connection, "select state from demand where id = '" <> id <> "'")
    == "delivered"
  assert flow.held_for_release(connection) == Ok([])
}

pub fn only_a_piece_held_for_release_can_be_released_test() {
  use connection <- with_seeded_database()
  let assert Ok(id) =
    demand.create(connection, "Search", "Retail", today(connection), 2, None)
  let pieces = "p-" <> string.drop_start(id, 2)
  put_in_last_blue_bin(connection, pieces <> "-1")
  let assert Ok(_) = flow.deploy(connection, pieces <> "-1", hold: True)
  assert flow.release(connection, [pieces <> "-1", pieces <> "-2"])
    == Error(flow.PieceNotHere)
  let assert Ok([_]) = flow.held_for_release(connection)
  let assert Ok(1) = flow.release(connection, [pieces <> "-1"])
  assert flow.release(connection, [pieces <> "-1"]) == Error(flow.PieceNotHere)
}

pub fn a_demand_is_delivered_at_the_release_of_its_last_piece_test() {
  use connection <- with_seeded_database()
  let assert Ok(id) =
    demand.create(connection, "Search", "Retail", today(connection), 2, None)
  let pieces = "p-" <> string.drop_start(id, 2)
  put_in_last_blue_bin(connection, pieces <> "-1")
  let assert Ok(_) = flow.deploy(connection, pieces <> "-1", hold: False)
  // The first Piece is held: deployed, not released yet.
  exec(connection, "update piece set released_at = null
     where id = '" <> pieces <> "-1'")

  put_in_last_blue_bin(connection, pieces <> "-2")
  let assert Ok(_) = flow.deploy(connection, pieces <> "-2", hold: False)
  assert text(connection, "select state from demand where id = '" <> id <> "'")
    == "active"
  assert count(
      connection,
      "select count(*) from flow_event where kind = 'demand_delivered'",
    )
    == 0
}

/// Friday 2026-11-06, day 20_763 since 1970-01-01.
const friday = 20_763

fn office() -> calendar.Calendar {
  Calendar(days: [1, 2, 3, 4, 5], start: 9 * 60, end: 16 * 60, holidays: [])
}

fn a_demand(asked: Int, deployed: Int, elapsed: Int, due_on: String) -> Demand {
  Demand(
    id: "d-test",
    code: "TST",
    label: "Test",
    client: "Client",
    due_on:,
    pieces_asked: asked,
    pieces_deployed: deployed,
    working_days_total: 20,
    working_days_elapsed: elapsed,
    hours_per_day: 7.0,
  )
}

pub fn days_count_from_1970_test() {
  assert calendar.day_number("1970-01-01") == Ok(0)
  assert calendar.day_number("2026-11-06") == Ok(friday)
  assert calendar.day_text(friday) == "2026-11-06"
  let assert Ok(leap) = calendar.day_number("2028-02-29")
  assert calendar.day_text(leap) == "2028-02-29"
  assert calendar.day_text(leap + 1) == "2028-03-01"
}

pub fn the_forecast_follows_the_pace_so_far_test() {
  // 4 Pieces in 8 working days: the 6 left need 12 more.
  let late = a_demand(10, 4, 8, "2026-11-20")
  assert demand.remaining_working_days(late) == Some(12)
  assert demand.forecast(late, office(), friday)
    == Some(Forecast(on: "2026-11-24", late_days: 2))
  assert demand.forecast(a_demand(10, 4, 8, "2026-11-24"), office(), friday)
    == Some(Forecast(on: "2026-11-24", late_days: 0))
  assert demand.forecast(a_demand(10, 4, 8, "2026-12-01"), office(), friday)
    == Some(Forecast(on: "2026-11-24", late_days: -5))
}

pub fn the_remaining_working_days_round_up_test() {
  // 3 Pieces in 2 days: 7 left need 4.7 days, so 5.
  assert demand.remaining_working_days(a_demand(10, 3, 2, "2026-12-31"))
    == Some(5)
  // A Piece deployed on a day off still gives a pace.
  assert demand.remaining_working_days(a_demand(2, 1, 0, "2026-12-31"))
    == Some(1)
}

pub fn the_forecast_skips_holidays_test() {
  let assert Ok(index) = calendar.day_number("2026-11-23")
  let bridge =
    Calendar(..office(), holidays: [
      Holiday(day: "2026-11-23", label: "Bridge", index:),
    ])
  assert demand.forecast(a_demand(10, 4, 8, "2026-11-20"), bridge, friday)
    == Some(Forecast(on: "2026-11-25", late_days: 2))
}

pub fn no_forecast_before_the_first_piece_or_years_away_test() {
  assert demand.forecast(a_demand(10, 0, 8, "2026-11-20"), office(), friday)
    == None
  assert demand.forecast(a_demand(10, 1, 1000, "2026-11-20"), office(), friday)
    == None
}

/// On time is judged at the Release: Late was deployed before its due date
/// but released after it.
pub fn the_on_time_share_counts_the_demands_delivered_in_the_period_test() {
  use connection <- with_seeded_database()
  exec(
    connection,
    "insert into demand values
       ('d-early', 'Early', 'A', '2026-09-01', '2026-10-10', 1, 'delivered', 'EA'),
       ('d-late', 'Late', 'B', '2026-09-01', '2026-10-03', 1, 'delivered', 'LA'),
       ('d-before', 'Before', 'C', '2026-08-01', '2026-09-30', 1, 'delivered', 'BE');
     insert into piece
       (id, demand_id, reference, state, deployed_at, released_at) values
       ('p-early', 'd-early', 'EA-1', 'deployed',
        '2026-10-09T15:00:00Z', '2026-10-10T15:00:00Z'),
       ('p-late', 'd-late', 'LA-1', 'deployed',
        '2026-10-02T10:00:00Z', '2026-10-05T10:00:00Z'),
       ('p-before', 'd-before', 'BE-1', 'deployed',
        '2026-09-20T10:00:00Z', '2026-09-20T10:00:00Z');",
  )
  let assert Ok(found) = measures.load(connection, "2026-10-01", "2026-10-31")
  assert found.delivered == 2
  assert found.on_time == 1
  assert string.contains(
    json.to_string(measures.to_json(found)),
    "\"onTime\":{\"delivered\":2,\"onTime\":1}",
  )
}

pub fn an_empty_start_keeps_one_work_station_and_the_calendar_test() {
  use connection <- with_seeded_database()
  exec(
    connection,
    "insert into holiday (day, label) values ('2026-12-25', 'Christmas');
     update working_calendar set days = '1234';
     update line_label set piece = 'Story', pieces = 'Stories';",
  )
  let assert Ok(Nil) = db.reset_empty(connection)

  assert count(connection, "select count(*) from demand") == 0
  assert count(connection, "select count(*) from piece") == 0
  assert count(connection, "select count(*) from rework") == 0
  assert count(
      connection,
      "select count(*) from flow_event
      where kind != 'kanban_sent'",
    )
    == 0
  assert count(connection, "select count(*) from holiday") == 1
  assert text(connection, "select days from working_calendar") == "1234"
  assert text(connection, "select piece from line_label") == "Story"
  assert text(connection, "select group_concat(name) from line_step")
    == "From the Backlog"

  let assert Ok(#(found, _)) = design.load(connection)
  let assert [team_member] = found.team_members
  assert team_member.name == "Team Member 1"
  let assert [design.Step(stations: [station], ..)] = found.steps
  assert station.name == "Work Station 1"
  assert station.blue_bins == 1
  assert station.branch == None
  assert station.team_leader == team_member.id
  assert station.team_members == [team_member.id]
  assert count(connection, "select count(*) from kanban") == 1
  assert count(
      connection,
      "select count(*) from flow_event
      where kind = 'kanban_sent'",
    )
    == 1

  // A later migration must not fill it with the demo data again.
  let assert Ok(Nil) = db.prepare(connection, db.Demo)
  assert count(connection, "select count(*) from demand") == 0

  let assert Ok(_) =
    demand.create(connection, "Search", "Retail", today(connection), 2, None)
  let assert Ok(id) = option.to_result(station.id, Nil)
  let assert Ok(pulled) = flow.pull(connection, id, None, None)
  assert pulled.piece == "SEA-1"
}

pub fn the_demo_reset_follows_an_empty_start_test() {
  use connection <- with_seeded_database()
  let assert Ok(Nil) = db.reset_empty(connection)
  let assert Ok(Nil) = db.reset(connection)
  assert count(connection, "select count(*) from demand") == 3
  assert count(connection, "select count(*) from work_station") == 9
  assert count(connection, "select count(*) from team_member") == 10
}
