import bluebin/assignment
import bluebin/db
import bluebin/demand.{type Demand, Demand}
import bluebin/flow
import bluebin/heijunka
import bluebin/value_stream
import gleam/dynamic/decode
import gleam/json
import gleam/list
import gleam/option.{None, Some}
import gleam/string
import gleeunit
import sqlight

pub fn main() -> Nil {
  gleeunit.main()
}

fn a_demand(
  pieces_asked: Int,
  pieces_produced: Int,
  working_days_total: Int,
  working_days_elapsed: Int,
) -> Demand {
  Demand(
    id: "d-test",
    label: "Test",
    client: "Client",
    due_on: "2026-12-31",
    pieces_asked:,
    pieces_produced:,
    working_days_total:,
    working_days_elapsed:,
  )
}

pub fn takt_time_is_working_time_over_pieces_test() {
  // 10 working days of 7 hours for 10 Pieces: one Piece every 7 hours.
  assert demand.takt_time_hours(a_demand(10, 0, 10, 0)) == 7.0
  assert demand.takt_time_hours(a_demand(20, 0, 10, 0)) == 3.5
}

pub fn takt_time_of_a_demand_asking_nothing_is_zero_test() {
  assert demand.takt_time_hours(a_demand(0, 0, 10, 0)) == 0.0
}

pub fn takt_gap_is_zero_when_the_demand_is_on_its_takt_test() {
  assert demand.takt_gap(a_demand(10, 5, 10, 5)) == 0.0
}

pub fn takt_gap_is_negative_when_the_demand_is_behind_test() {
  // Eight days spent out of ten, so the Takt Time asked for 8 Pieces.
  assert demand.takt_gap(a_demand(10, 3, 10, 8)) == -5.0
}

pub fn takt_gap_is_positive_when_the_demand_is_ahead_test() {
  assert demand.takt_gap(a_demand(10, 7, 10, 5)) == 2.0
}

pub fn an_andon_rises_a_whole_piece_behind_test() {
  assert demand.takt_gap(a_demand(10, 9, 20, 19)) == -0.5
  assert demand.andon(a_demand(10, 9, 20, 19)) == False
  assert demand.andon(a_demand(10, 3, 10, 8)) == True
}

pub fn the_value_stream_takt_combines_every_demand_test() {
  // Two Demands, one Piece every 7 hours each: together one every 3.5 hours.
  let demands = [a_demand(10, 0, 10, 0), a_demand(10, 0, 10, 0)]
  assert demand.value_stream_takt_hours(demands) == 3.5
  assert demand.value_stream_takt_hours([a_demand(0, 0, 10, 0)]) == 0.0
}

pub fn behind_count_counts_only_the_demands_with_an_andon_test() {
  let demands = [a_demand(10, 3, 10, 8), a_demand(10, 5, 10, 5)]
  assert demand.behind_count(demands) == 1
}

fn with_seeded_database(run: fn(sqlight.Connection) -> a) -> a {
  use connection <- db.with_connection_at(":memory:")
  let assert Ok(Nil) = db.prepare(connection)
  run(connection)
}

/// v4 is the last schema before Sub-Pieces, as bluebin.app had it.
fn with_database_at_version_4(run: fn(sqlight.Connection) -> a) -> a {
  use connection <- db.with_connection_at(":memory:")
  let assert Ok(Nil) = db.migrate_to(connection, 4)
  exec(
    connection,
    "insert into demand values ('d-old', 'Old', 'Client', '2026-01-01', '2026-12-31', 1, 'active');
     insert into piece (id, demand_id, reference, state) values ('p-old', 'd-old', 'US-1', 'in_flow');
     insert into stream_step (position, name) values (1, 'From the Backlog'), (2, 'Step 2');",
  )
  run(connection)
}

fn count(connection: sqlight.Connection, sql: String) -> Int {
  let decoder = {
    use value <- decode.field(0, decode.int)
    decode.success(value)
  }
  let assert Ok([value]) =
    sqlight.query(sql, on: connection, with: [], expecting: decoder)
  value
}

pub fn the_seed_fills_the_value_stream_test() {
  use connection <- with_seeded_database()
  assert count(connection, "select count(*) from demand") == 3
  assert count(connection, "select count(*) from work_station") == 9
  assert count(
      connection,
      "select count(*) from work_station w
       where w.blue_bins < (select count(*) from piece p
                            where p.station_id = w.id and p.state = 'in_bin')",
    )
    == 0
}

pub fn the_seed_runs_once_test() {
  use connection <- with_seeded_database()
  let assert Ok(Nil) = db.prepare(connection)
  assert count(connection, "select count(*) from demand") == 3
  assert count(connection, "select count(*) from work_station") == 9
}

/// Row counts of every table, plus the step names and Piece states, so two
/// databases with the same seed give the same fingerprint.
fn fingerprint(connection: sqlight.Connection) -> List(Int) {
  [
    "demand", "piece", "flow_event", "person", "work_station", "station_person",
    "kanban", "rework", "deviation", "piece_pass", "stream_step",
  ]
  |> list.map(fn(table) { count(connection, "select count(*) from " <> table) })
  |> list.append([
    count(
      connection,
      "select count(*) from stream_step where name like 'Step %'",
    ),
    count(connection, "select count(*) from piece where state = 'produced'"),
  ])
}

pub fn the_demo_reset_puts_back_the_seed_test() {
  use connection <- with_seeded_database()
  let seeded = fingerprint(connection)
  let assert Ok(_) = flow.pull(connection, "ws-web", None, None)
  let assert Ok(_) = value_stream.rename_step(connection, 2, "Design")
  exec(connection, "delete from kanban; delete from deviation;")
  assert fingerprint(connection) != seeded
  let assert Ok(Nil) = db.reset(connection)
  assert fingerprint(connection) == seeded
  assert kanbans_over_empty_blue_bins(connection) == 0
}

/// Invariant F7 (DESIGN.md): always 0.
fn kanbans_over_empty_blue_bins(connection: sqlight.Connection) -> Int {
  count(
    connection,
    "select count(*) from work_station w
     where (select count(*) from kanban k where k.station_id = w.id)
         > w.blue_bins - (select count(*) from piece p
                          where p.station_id = w.id and p.state = 'in_bin')",
  )
}

pub fn a_work_station_never_holds_more_kanbans_than_empty_blue_bins_test() {
  use connection <- with_seeded_database()
  assert kanbans_over_empty_blue_bins(connection) == 0
}

pub fn a_piece_in_a_blue_bin_names_its_work_station_test() {
  use connection <- with_seeded_database()
  assert count(
      connection,
      "select count(*) from piece
       where state = 'in_bin' and station_id is null",
    )
    == 0
  // The seed parks US-9 in the trunk and three Sub-Pieces in the Branches.
  assert count(connection, "select count(*) from piece where state = 'in_bin'")
    == 4
}

fn exec(connection: sqlight.Connection, sql: String) -> Nil {
  let assert Ok(Nil) = sqlight.exec(sql, connection)
  Nil
}

fn kanbans(connection: sqlight.Connection, station: String) -> Int {
  count(
    connection,
    "select count(*) from kanban where station_id = '" <> station <> "'",
  )
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

pub fn a_pull_spends_a_kanban_and_sends_one_upstream_test() {
  use connection <- with_seeded_database()
  // Tech Conception holds a Kanban; Analysis has a Piece to finish first.
  let assert Ok(_) = flow.finish(connection, "ws-analysis", "p-billing-2", None)
  let assert Ok(flowed) = flow.pull(connection, "ws-conception", None, None)
  assert flowed.piece == "US-2"
  assert flowed.deviations == []
  assert flowed.kanbans_sent_to == ["ws-analysis"]
  assert kanbans(connection, "ws-conception") == 0
  assert state_of(connection, "p-billing-2") == "in_flow"
  assert kanbans_over_empty_blue_bins(connection) == 0
}

pub fn the_first_work_station_pulls_out_of_the_backlog_test() {
  use connection <- with_seeded_database()
  let backlog =
    count(connection, "select count(*) from piece where state = 'backlog'")

  let assert Ok(flowed) = flow.pull(connection, "ws-analysis", None, None)
  assert flowed.kanbans_sent_to == []
  assert kanbans(connection, "ws-analysis") == 0
  assert count(connection, "select count(*) from piece where state = 'backlog'")
    == backlog - 1
}

pub fn each_branch_pulls_its_own_sub_piece_at_the_split_test() {
  use connection <- with_seeded_database()
  // The seed parks US-9 in Tech Conception's Blue Bin.
  let assert Ok(ios) = flow.pull(connection, "ws-ios", None, None)
  assert ios.piece == "US-9 · iOS"
  assert state_of(connection, "p-checkout-9") == "in_bin"
  assert ios.kanbans_sent_to == []

  let assert Ok(web) = flow.pull(connection, "ws-web", None, None)
  assert web.piece == "US-9 · Web"
  assert flow.pull(connection, "ws-web", None, Some("again"))
    == Error(flow.NothingToPull)
}

pub fn the_piece_leaves_the_trunk_when_the_last_branch_pulls_test() {
  use connection <- with_seeded_database()
  let assert Ok(_) = flow.pull(connection, "ws-web", None, None)
  let assert Ok(_) = flow.pull(connection, "ws-ios", None, None)
  assert kanbans(connection, "ws-conception") == 1

  let assert Ok(android) = flow.pull(connection, "ws-android", None, None)
  assert android.kanbans_sent_to == ["ws-conception"]
  assert kanbans(connection, "ws-conception") == 2
  assert state_of(connection, "p-checkout-9") == "split"
  assert count(
      connection,
      "select count(*) from piece where parent_id = 'p-checkout-9'
       and state = 'in_flow'",
    )
    == 3
  assert kanbans_over_empty_blue_bins(connection) == 0
}

pub fn a_branch_pulls_inside_itself_test() {
  use connection <- with_seeded_database()
  assert kanbans(connection, "ws-qa-ios") == 0
  // The seeded Rework raised by QA iOS is still open.
  assert flow.pull(connection, "ws-qa-ios", None, None)
    == Error(
      flow.NeedsConfirmation([
        flow.PullWithAnOpenRework,
        flow.PullWithoutKanban,
      ]),
    )
  assert state_of(connection, "p-checkout-8-ios") == "in_bin"
  assert flow.pull(connection, "ws-qa-ios", None, Some("   "))
    == Error(
      flow.NeedsConfirmation([
        flow.PullWithAnOpenRework,
        flow.PullWithoutKanban,
      ]),
    )

  let assert Ok(flowed) =
    flow.pull(connection, "ws-qa-ios", None, Some("Blocking the demo"))
  assert flowed.piece == "US-8 · iOS"
  assert flowed.deviations
    == [flow.PullWithAnOpenRework, flow.PullWithoutKanban]
  assert flowed.kanbans_sent_to == ["ws-ios"]
  assert count(
      connection,
      "select count(*) from deviation
       where rule = 'pull_without_kanban' and station_id = 'ws-qa-ios'
         and reason = 'Blocking the demo'",
    )
    == 1
}

pub fn the_assembly_waits_for_every_sub_piece_test() {
  use connection <- with_seeded_database()
  // US-4: Web and Android parts wait in QA, the iOS part is still in hand.
  assert flow.pull(connection, "ws-uat", None, None)
    == Error(flow.NothingToAssemble)
  assert state_of(connection, "p-offline-4-web") == "in_bin"
}

pub fn the_assembly_joins_the_sub_pieces_and_sends_each_branch_a_kanban_test() {
  use connection <- with_seeded_database()
  let assert Ok(_) =
    flow.finish(connection, "ws-qa-ios", "p-offline-4-ios", None)

  let assert Ok(flowed) = flow.pull(connection, "ws-uat", None, None)
  assert flowed.piece == "US-4"
  assert list.sort(flowed.kanbans_sent_to, string.compare)
    == ["ws-qa-android", "ws-qa-ios", "ws-qa-web"]
  assert state_of(connection, "p-offline-4") == "in_flow"
  assert count(
      connection,
      "select count(*) from piece where parent_id = 'p-offline-4'
       and state = 'assembled' and station_id is null",
    )
    == 3
  assert kanbans(connection, "ws-uat") == 0
  assert kanbans_over_empty_blue_bins(connection) == 0
  assert count(
      connection,
      "select count(*) from flow_event where kind = 'piece_assembled'",
    )
    == 1
}

pub fn finishing_a_piece_puts_it_in_a_blue_bin_test() {
  use connection <- with_seeded_database()
  let assert Ok(flowed) =
    flow.finish(connection, "ws-analysis", "p-billing-2", None)
  assert flowed.piece == "US-2"
  assert flowed.deviations == []
  assert state_of(connection, "p-billing-2") == "in_bin"
  assert kanbans_over_empty_blue_bins(connection) == 0
}

pub fn a_second_piece_in_a_blue_bin_is_warned_then_recorded_test() {
  use connection <- with_seeded_database()
  exec(
    connection,
    "update work_station set blue_bins = 0 where id = 'ws-analysis'",
  )

  assert flow.finish(connection, "ws-analysis", "p-billing-2", None)
    == Error(flow.NeedsConfirmation([flow.SecondPieceInABlueBin]))
  assert state_of(connection, "p-billing-2") == "in_flow"

  let assert Ok(flowed) =
    flow.finish(
      connection,
      "ws-analysis",
      "p-billing-2",
      Some("UAT asked for it today"),
    )
  assert flowed.deviations == [flow.SecondPieceInABlueBin]
  assert state_of(connection, "p-billing-2") == "in_bin"
}

pub fn a_piece_the_work_station_does_not_hold_cannot_be_finished_test() {
  use connection <- with_seeded_database()
  assert flow.finish(connection, "ws-web", "p-billing-2", None)
    == Error(flow.PieceNotHere)
  assert flow.pull(connection, "ws-nowhere", None, None)
    == Error(flow.UnknownStation)
}

pub fn delivering_sends_a_kanban_back_to_the_last_work_station_test() {
  use connection <- with_seeded_database()
  exec(connection, "delete from kanban where station_id = 'ws-uat'")
  exec(
    connection,
    "update piece set state = 'in_bin', station_id = 'ws-uat'
     where id = 'p-billing-3'",
  )

  let assert Ok(flowed) = flow.deliver(connection, "p-billing-3")
  assert flowed.kanbans_sent_to == ["ws-uat"]
  assert state_of(connection, "p-billing-3") == "produced"
  assert kanbans_over_empty_blue_bins(connection) == 0
}

pub fn only_the_last_work_station_delivers_to_production_test() {
  use connection <- with_seeded_database()
  assert flow.deliver(connection, "p-checkout-9") == Error(flow.PieceNotHere)
}

pub fn every_action_writes_one_flow_event_test() {
  use connection <- with_seeded_database()
  let before = count(connection, "select count(*) from flow_event")
  let assert Ok(_) = flow.pull(connection, "ws-web", None, None)
  let assert Ok(_) = flow.finish(connection, "ws-web", "p-checkout-9-web", None)
  assert count(connection, "select count(*) from flow_event") == before + 2
}

pub fn the_reset_keeps_the_names_of_the_steps_test() {
  use connection <- with_database_at_version_4()
  let assert Ok(_) = value_stream.rename_step(connection, 2, "Design")
  let assert Ok(Nil) = db.prepare(connection)
  assert count(connection, "select count(*) from demand") == 3
  assert count(
      connection,
      "select count(*) from piece where parent_id is not null",
    )
    == 6
  let assert Ok(steps) = value_stream.list_steps(connection)
  assert list.contains(steps, value_stream.Step(position: 2, name: "Design"))
}

pub fn a_rework_goes_to_its_author_and_pauses_their_piece_test() {
  use connection <- with_seeded_database()
  // In the seed, Alice made US-4's iOS part.
  let assert Ok(_) = flow.repair_rework(connection, "rw-1")
  let assert Ok(_) = flow.pull(connection, "ws-ios", Some("pe-alice"), None)
  assert state_of(connection, "p-checkout-9-ios") == "in_flow"

  let assert Ok(raised) =
    flow.raise_rework(
      connection,
      "ws-qa-ios",
      "p-offline-4-ios",
      "ws-ios",
      "  The retry banner never goes away  ",
    )
  assert raised.piece == "US-4 · iOS"
  assert raised.assignee == Some("Alice")
  assert raised.paused == Some("US-9 · iOS")
  assert state_of(connection, "p-checkout-9-ios") == "paused"
  assert count(
      connection,
      "select count(*) from rework
       where station_id = 'ws-ios' and raised_by = 'ws-qa-ios'
         and assignee = 'pe-alice' and started_at is not null
         and description = 'The retry banner never goes away'",
    )
    == 1
  assert state_of(connection, "p-offline-4-ios") == "in_flow"

  let assert Ok(repaired) = flow.repair_rework(connection, raised.id)
  assert repaired.resumed == Some("US-9 · iOS")
  assert state_of(connection, "p-checkout-9-ios") == "in_flow"
  assert flow.repair_rework(connection, raised.id) == Error(flow.UnknownRework)
}

pub fn a_defect_belongs_to_a_work_station_the_piece_crossed_test() {
  use connection <- with_seeded_database()
  // UAT is downstream of QA iOS.
  assert flow.raise_rework(
      connection,
      "ws-qa-ios",
      "p-offline-4-ios",
      "ws-uat",
      "Broken",
    )
    == Error(flow.NotUpstream)
  // US-4's iOS part never went through Web.
  assert flow.raise_rework(
      connection,
      "ws-qa-ios",
      "p-offline-4-ios",
      "ws-web",
      "Broken",
    )
    == Error(flow.NotUpstream)
  assert flow.raise_rework(
      connection,
      "ws-qa-ios",
      "p-offline-4-ios",
      "ws-ios",
      "   ",
    )
    == Error(flow.EmptyDescription)
  // UAT is downstream of iOS but does not hold US-4's iOS part.
  assert flow.raise_rework(
      connection,
      "ws-uat",
      "p-offline-4-ios",
      "ws-ios",
      "Broken",
    )
    == Error(flow.PieceNotHere)
  assert count(connection, "select count(*) from rework") == 1
}

pub fn the_work_station_that_found_a_defect_does_not_pull_test() {
  use connection <- with_seeded_database()
  // Give QA iOS a Kanban, so only the open Rework stands in the way (F14).
  exec(
    connection,
    "insert into kanban (id, station_id) values ('kb-qa-ios-1', 'ws-qa-ios')",
  )
  assert flow.pull(connection, "ws-qa-ios", None, None)
    == Error(flow.NeedsConfirmation([flow.PullWithAnOpenRework]))
  assert kanbans(connection, "ws-qa-ios") == 1

  let assert Ok(flowed) =
    flow.pull(connection, "ws-qa-ios", None, Some("The Client waits"))
  assert flowed.deviations == [flow.PullWithAnOpenRework]
  assert count(
      connection,
      "select count(*) from deviation
       where rule = 'pull_with_an_open_rework' and station_id = 'ws-qa-ios'",
    )
    == 1
}

pub fn a_repaired_rework_lets_the_work_station_pull_again_test() {
  use connection <- with_seeded_database()
  exec(
    connection,
    "insert into kanban (id, station_id) values ('kb-qa-ios-1', 'ws-qa-ios')",
  )
  let assert Ok(_) = flow.repair_rework(connection, "rw-1")

  let assert Ok(flowed) = flow.pull(connection, "ws-qa-ios", None, None)
  assert flowed.deviations == []
  assert count(
      connection,
      "select count(*) from flow_event where kind = 'rework_repaired'",
    )
    == 1
}

pub fn finishing_a_piece_records_who_transformed_it_test() {
  use connection <- with_seeded_database()
  // Karim is a Person of iOS, not of Web.
  let assert Ok(_) = flow.pull(connection, "ws-ios", Some("pe-karim"), None)
  let assert Ok(_) = flow.pull(connection, "ws-web", Some("pe-karim"), None)
  assert count(
      connection,
      "select count(*) from piece where id = 'p-checkout-9-ios'
       and assignee = 'pe-karim'",
    )
    == 1
  assert count(
      connection,
      "select count(*) from piece where id = 'p-checkout-9-web'
       and assignee is null",
    )
    == 1

  let assert Ok(_) = flow.finish(connection, "ws-ios", "p-checkout-9-ios", None)
  assert count(
      connection,
      "select count(*) from piece_pass
       where piece_id = 'p-checkout-9-ios' and station_id = 'ws-ios'
         and person_id = 'pe-karim'",
    )
    == 1
}

pub fn a_rework_on_an_assembled_piece_finds_its_author_in_the_branch_test() {
  use connection <- with_seeded_database()
  let assert Ok(_) =
    flow.finish(connection, "ws-qa-ios", "p-offline-4-ios", None)
  let assert Ok(_) = flow.pull(connection, "ws-uat", None, None)

  let assert Ok(raised) =
    flow.raise_rework(
      connection,
      "ws-uat",
      "p-offline-4",
      "ws-ios",
      "The iOS build crashes on launch",
    )
  // The pass that counts is the one of the Sub-Piece, made by Alice.
  assert raised.assignee == Some("Alice")
}

pub fn the_payload_carries_the_first_pass_yield_and_the_rework_time_test() {
  use connection <- with_seeded_database()
  // 12 passes at iOS, one reworked: (12 - 1) / 12 = 0.91…
  assert count(
      connection,
      "select count(*) from piece_pass where station_id = 'ws-ios'",
    )
    == 12
  let assert Ok(payload) = value_stream.load(connection)
  let text = json.to_string(payload)
  assert string.contains(text, "\"firstPassYield\"")
  assert string.contains(text, "\"reworkHours\"")
  assert string.contains(text, "\"firstPassYield\":0.91")
  // Three hours of Rework stand against iOS, the Work Station that made it.
  assert string.contains(text, "\"reworkHours\":3.0")

  exec(connection, "delete from piece_pass where station_id = 'ws-uat'")
  let assert Ok(empty) = value_stream.load(connection)
  assert string.contains(json.to_string(empty), "\"firstPassYield\":null")
}

fn assignee(
  connection: sqlight.Connection,
  table: String,
  id: String,
) -> String {
  let assert Ok([person]) =
    sqlight.query(
      "select coalesce(assignee, '') from " <> table <> " where id = ?1",
      on: connection,
      with: [sqlight.text(id)],
      expecting: decode.at([0], decode.string),
    )
  person
}

fn next_of(connection: sqlight.Connection, person: String) -> assignment.Next {
  let assert Ok(view) = assignment.load(connection, person)
  view.next
}

pub fn a_person_repairs_their_rework_before_pulling_test() {
  use connection <- with_seeded_database()
  // Alice holds the seeded Rework.
  assert flow.pull(connection, "ws-ios", Some("pe-alice"), None)
    == Error(flow.ReworkFirst)
  assert kanbans(connection, "ws-ios") == 1
  // Karim, also of iOS, has free hands.
  let assert Ok(_) = flow.pull(connection, "ws-ios", Some("pe-karim"), None)
  assert kanbans(connection, "ws-ios") == 0
}

pub fn taking_a_new_piece_puts_the_current_one_down_test() {
  use connection <- with_seeded_database()
  // In the seed, Bob holds US-8's Web part.
  let assert Ok(_) = flow.pull(connection, "ws-web", Some("pe-bob"), None)
  assert state_of(connection, "p-checkout-9-web") == "in_flow"
  assert state_of(connection, "p-checkout-8-web") == "paused"

  let assert Ok(_) = flow.finish(connection, "ws-web", "p-checkout-9-web", None)
  assert state_of(connection, "p-checkout-8-web") == "in_flow"
  assert count(
      connection,
      "select count(*) from flow_event
       where kind in ('piece_paused', 'piece_resumed')
         and piece_id = 'p-checkout-8-web'",
    )
    == 2
}

pub fn a_second_rework_waits_behind_the_first_test() {
  use connection <- with_seeded_database()
  let assert Ok(raised) =
    flow.raise_rework(
      connection,
      "ws-qa-ios",
      "p-offline-4-ios",
      "ws-ios",
      "The retry banner never goes away",
    )
  // Alice is already repairing rw-1.
  assert raised.assignee == Some("Alice")
  assert count(
      connection,
      "select count(*) from rework where id = '" <> raised.id <> "'
       and started_at is null",
    )
    == 1

  let assert Ok(repaired) = flow.repair_rework(connection, "rw-1")
  assert repaired.resumed == None
  assert count(
      connection,
      "select count(*) from rework where id = '" <> raised.id <> "'
       and started_at is not null",
    )
    == 1
}

pub fn a_piece_in_hand_goes_to_another_person_of_the_work_station_test() {
  use connection <- with_seeded_database()
  let assert Ok(handed) =
    flow.reassign(
      connection,
      flow.PieceAssignment,
      "p-checkout-8-web",
      "pe-lila",
    )
  assert handed.person == "Lila"
  assert assignee(connection, "piece", "p-checkout-8-web") == "pe-lila"
  // Karim is not of Web.
  assert flow.reassign(
      connection,
      flow.PieceAssignment,
      "p-checkout-8-web",
      "pe-karim",
    )
    == Error(flow.NotOfStation)
  assert assignee(connection, "piece", "p-checkout-8-web") == "pe-lila"
  // US-9 sits in a Blue Bin, in nobody's hands.
  assert flow.reassign(
      connection,
      flow.PieceAssignment,
      "p-checkout-9",
      "pe-marc",
    )
    == Error(flow.PieceNotHere)
}

pub fn a_rework_handed_over_pauses_the_taker_and_frees_the_giver_test() {
  use connection <- with_seeded_database()
  let assert Ok(_) = flow.pull(connection, "ws-ios", Some("pe-karim"), None)
  assert state_of(connection, "p-checkout-9-ios") == "in_flow"

  let assert Ok(_) =
    flow.reassign(connection, flow.ReworkAssignment, "rw-1", "pe-karim")
  assert assignee(connection, "rework", "rw-1") == "pe-karim"
  assert state_of(connection, "p-checkout-9-ios") == "paused"
  assert flow.pull(connection, "ws-ios", Some("pe-karim"), None)
    == Error(flow.ReworkFirst)

  let assert Ok(_) =
    flow.reassign(
      connection,
      flow.PieceAssignment,
      "p-checkout-9-ios",
      "pe-alice",
    )
  assert state_of(connection, "p-checkout-9-ios") == "in_flow"
  assert count(
      connection,
      "select count(*) from flow_event where kind = 'assignment_changed'",
    )
    == 2
}

pub fn the_priority_list_puts_rework_before_kanbans_test() {
  use connection <- with_seeded_database()
  let assert Ok(items) = assignment.priority_list(connection, "ws-ios")
  let assert [assignment.ReworkItem(id: "rw-1", ..), assignment.KanbanItem(..)] =
    items
}

pub fn the_next_thing_is_the_active_assignment_test() {
  use connection <- with_seeded_database()
  let assert assignment.Continue(assignment.Repair(id: "rw-1", active: True, ..)) =
    next_of(connection, "pe-alice")
  let assert assignment.Continue(assignment.Transform(
    id: "p-checkout-8-web",
    active: True,
    ..,
  )) = next_of(connection, "pe-bob")
}

pub fn free_hands_take_the_top_kanban_test() {
  use connection <- with_seeded_database()
  assert next_of(connection, "pe-lila")
    == assignment.TakeKanban(station_id: "ws-web", station: "Web")
}

pub fn a_rework_nobody_repairs_comes_before_any_kanban_test() {
  use connection <- with_seeded_database()
  exec(connection, "update rework set assignee = null")
  let assert assignment.TakeRework(id: "rw-1", ..) =
    next_of(connection, "pe-karim")
}

pub fn without_a_kanban_a_person_helps_downstream_test() {
  use connection <- with_seeded_database()
  // QA iOS waits on the seeded Rework it raised.
  exec(connection, "delete from kanban where station_id = 'ws-ios'")
  let assert assignment.HelpDownstream(station_id: "ws-qa-ios", ..) =
    next_of(connection, "pe-karim")
}

pub fn with_nothing_to_take_or_help_a_person_waits_test() {
  use connection <- with_seeded_database()
  // Tom's Kanban at QA Web has no Piece upstream, and nothing downstream of
  // his Work Stations holds up the flow.
  assert next_of(connection, "pe-tom") == assignment.Wait
  assert assignment.load(connection, "pe-nobody")
    == Error(assignment.UnknownPerson)
}

pub fn the_person_payload_carries_the_shape_the_screen_reads_test() {
  use connection <- with_seeded_database()
  let assert Ok(view) = assignment.load(connection, "pe-alice")
  let text = json.to_string(assignment.to_json(view))
  assert string.contains(text, "\"next\":{\"kind\":\"continue\"")
  assert string.contains(text, "\"kind\":\"rework\",\"id\":\"rw-1\"")
  assert string.contains(text, "\"priorityLists\":[{\"station\":\"ws-ios\"")
  let assert Ok(people) = assignment.people(connection)
  // Nearest to production first.
  assert list.contains(
    people,
    assignment.Person(id: "pe-marc", name: "Marc", stations: [
      "Tech Conception", "Analysis",
    ]),
  )
}

pub fn the_demands_payload_carries_the_takt_numbers_test() {
  use connection <- with_seeded_database()
  let assert Ok(demands) = demand.list_active(connection)
  assert list.length(demands) == 3
  assert list.all(demands, fn(one) { demand.takt_time_hours(one) >. 0.0 })

  let payload = demand.to_json(demands)
  assert payload != "[]"
}

pub fn the_value_stream_payload_lists_every_work_station_test() {
  use connection <- with_seeded_database()
  let assert Ok(payload) = value_stream.load(connection)
  let text = json.to_string(payload)

  let station_names = [
    "Analysis", "Tech Conception", "Web", "iOS", "Android", "QA Web", "QA iOS",
    "QA Android", "UAT",
  ]
  assert list.all(station_names, fn(name) { string.contains(text, name) })
  let seeded_open_rework = "Sync retries lose the last edit"
  assert string.contains(text, seeded_open_rework)
}

pub fn the_seed_names_every_step_test() {
  use connection <- with_seeded_database()
  let assert Ok(steps) = value_stream.list_steps(connection)
  assert list.length(steps) == 5
  let assert [first, ..] = steps
  assert first.name == "From the Backlog"
}

pub fn a_step_can_be_renamed_test() {
  use connection <- with_seeded_database()
  let assert Ok(step) = value_stream.rename_step(connection, 2, "  Design  ")
  assert step.name == "Design"
  let assert Ok(steps) = value_stream.list_steps(connection)
  assert list.contains(steps, value_stream.Step(position: 2, name: "Design"))
}

pub fn a_rename_is_dated_in_the_flow_event_log_test() {
  use connection <- with_seeded_database()
  let before = count(connection, "select count(*) from flow_event")
  let assert Ok(_) = value_stream.rename_step(connection, 2, "Design")
  assert count(connection, "select count(*) from flow_event") == before + 1
  assert count(
      connection,
      "select count(*) from stream_step
       where position = 2 and renamed_at is not null",
    )
    == 1
}

pub fn a_step_never_loses_its_name_test() {
  use connection <- with_seeded_database()
  assert value_stream.rename_step(connection, 2, "   ")
    == Error(value_stream.EmptyName)
  let assert Ok(steps) = value_stream.list_steps(connection)
  assert list.contains(steps, value_stream.Step(position: 2, name: "Step 2"))
}

pub fn a_step_name_stays_short_enough_for_a_wall_tv_test() {
  use connection <- with_seeded_database()
  let too_long = string.repeat("a", value_stream.max_name_length + 1)
  assert value_stream.rename_step(connection, 2, too_long)
    == Error(value_stream.NameTooLong)
  let longest = string.repeat("a", value_stream.max_name_length)
  let assert Ok(step) = value_stream.rename_step(connection, 2, longest)
  assert step.name == longest
}

pub fn renaming_a_step_that_does_not_exist_is_refused_test() {
  use connection <- with_seeded_database()
  assert value_stream.rename_step(connection, 99, "Nowhere")
    == Error(value_stream.UnknownStep)
}

pub fn a_quote_in_a_name_is_stored_as_typed_test() {
  use connection <- with_seeded_database()
  let assert Ok(step) = value_stream.rename_step(connection, 2, "Dev's turn")
  assert step.name == "Dev's turn"
}

fn heijunka_demand(id: String, due_on: String, pieces_asked: Int) -> Demand {
  // Ten working days of 7 hours: 10 Pieces is a Takt Time of 7 h, 20 of 3.5 h.
  Demand(..a_demand(pieces_asked, 0, 10, 0), id:, label: id, due_on:)
}

fn waiting(
  id: String,
  demand: String,
  arrived: Int,
  ordinal: Int,
  urgent: option.Option(Int),
) -> heijunka.Waiting {
  heijunka.Waiting(
    id:,
    reference: id,
    demand:,
    arrived:,
    ordinal:,
    working_days_before_start: 0,
    urgent:,
  )
}

fn ids(sequence: List(heijunka.Placed)) -> List(String) {
  list.map(sequence, fn(placed) { placed.piece.id })
}

pub fn the_heijunka_sequence_takes_the_earliest_slot_first_test() {
  let demands = [
    heijunka_demand("a", "2026-12-01", 10),
    heijunka_demand("b", "2026-12-31", 20),
  ]
  // Slots: a1 7 h, a2 14 h; b1 3.5 h, b2 7 h, b3 10.5 h. a1 and b2 tie on
  // the slot, and a is due first.
  let sequence =
    heijunka.sequence(
      [
        waiting("a1", "a", 1, 1, None),
        waiting("a2", "a", 2, 2, None),
        waiting("b1", "b", 3, 1, None),
        waiting("b2", "b", 4, 2, None),
        waiting("b3", "b", 5, 3, None),
      ],
      demands,
    )
  assert ids(sequence) == ["b1", "a1", "b2", "b3", "a2"]
}

pub fn the_heijunka_sequence_ends_a_tie_first_in_first_out_test() {
  let demands = [
    heijunka_demand("a", "2026-12-01", 10),
    heijunka_demand("b", "2026-12-01", 10),
  ]
  let sequence =
    heijunka.sequence(
      [waiting("b1", "b", 2, 1, None), waiting("a1", "a", 1, 1, None)],
      demands,
    )
  assert ids(sequence) == ["a1", "b1"]
}

pub fn urgent_pieces_lead_the_heijunka_sequence_in_their_order_test() {
  let demands = [heijunka_demand("a", "2026-12-01", 10)]
  let sequence =
    heijunka.sequence(
      [
        waiting("a1", "a", 1, 1, None),
        waiting("a2", "a", 2, 2, Some(2)),
        waiting("a3", "a", 3, 3, Some(1)),
      ],
      demands,
    )
  assert ids(sequence) == ["a3", "a2", "a1"]
}

pub fn a_reorder_shows_what_each_demand_gains_and_loses_test() {
  let demands = [
    heijunka_demand("a", "2026-12-01", 10),
    heijunka_demand("b", "2026-12-31", 20),
  ]
  let before =
    heijunka.sequence(
      [waiting("a1", "a", 1, 1, None), waiting("b2", "b", 2, 2, None)],
      demands,
    )
  let after = heijunka.make_urgent(before, "b2")
  assert ids(after) == ["b2", "a1"]
  let effects =
    heijunka.effects(before, after, 2.0)
    |> list.map(fn(effect) {
      #(effect.demand.id, effect.places, effect.hours, effect.takt_gap)
    })
  assert effects == [#("a", 1, 2.0, -0.3), #("b", -1, -2.0, 0.6)]
}

fn backlog_sequence(connection: sqlight.Connection) -> List(heijunka.Placed) {
  let assert Ok(backlog) = heijunka.load(connection)
  backlog.sequence
}

pub fn the_backlog_releases_the_head_of_the_heijunka_sequence_test() {
  use connection <- with_seeded_database()
  let assert [head, ..] = backlog_sequence(connection)
  let assert Ok(flowed) = flow.pull(connection, "ws-analysis", None, None)
  assert flowed.deviations == []
  assert state_of(connection, head.piece.id) == "in_flow"
}

/// The next Piece of the Demand whose next Piece comes last in the sequence.
fn last_demand_next_piece(sequence: List(heijunka.Placed)) -> heijunka.Placed {
  let assert Ok(last) = list.last(sequence)
  let assert Ok(placed) =
    list.find(sequence, fn(placed) { placed.demand.id == last.demand.id })
  placed
}

pub fn making_a_piece_urgent_is_warned_then_recorded_test() {
  use connection <- with_seeded_database()
  let sequence = backlog_sequence(connection)
  let target = last_demand_next_piece(sequence)

  let assert Error(flow.ReorderNeedsConfirmation(effects)) =
    flow.make_urgent(connection, target.piece.id, None)
  assert list.any(effects, fn(effect) {
    effect.demand.id == target.demand.id && effect.places < 0
  })
  assert list.any(effects, fn(effect) { effect.places > 0 })
  assert count(connection, "select count(*) from deviation") == 0

  let assert Ok(flowed) =
    flow.make_urgent(connection, target.piece.id, Some("Client demo today"))
  assert flowed.deviations == [flow.ReorderHeijunkaSequence]
  assert count(
      connection,
      "select count(*) from deviation
       where rule = 'reorder_heijunka_sequence' and station_id = 'ws-analysis'",
    )
    == 1
  let assert [head, ..] = backlog_sequence(connection)
  assert head.piece.id == target.piece.id

  let assert Ok(_) = flow.pull(connection, "ws-analysis", None, None)
  assert state_of(connection, target.piece.id) == "in_flow"
}

pub fn only_the_next_piece_of_a_demand_can_be_made_urgent_test() {
  use connection <- with_seeded_database()
  let sequence = backlog_sequence(connection)
  let target = last_demand_next_piece(sequence)
  let assert Ok(second) =
    sequence
    |> list.filter(fn(placed) {
      placed.demand.id == target.demand.id && placed.piece.id != target.piece.id
    })
    |> list.first
  assert flow.make_urgent(connection, second.piece.id, Some("why"))
    == Error(flow.NotNextOfDemand)
  assert flow.make_urgent(connection, "p-checkout-1", Some("why"))
    == Error(flow.PieceNotHere)
}

pub fn the_head_of_the_sequence_is_not_a_reorder_test() {
  use connection <- with_seeded_database()
  let assert [head, ..] = backlog_sequence(connection)
  let assert Ok(flowed) = flow.make_urgent(connection, head.piece.id, None)
  assert flowed.deviations == []
  assert !list.contains(
    heijunka.can_be_urgent(backlog_sequence(connection)),
    head.piece.id,
  )
}

fn released_today(connection: sqlight.Connection) -> Int {
  let assert Ok(backlog) = heijunka.load(connection)
  let assert Ok(mix) = heijunka.product_mix(connection, backlog.demands)
  mix
  |> list.flat_map(fn(row) { row.cells })
  |> list.map(fn(cell) { cell.real })
  |> list.fold(0, fn(total, real) { total + real })
}

pub fn the_product_mix_counts_each_piece_that_leaves_the_backlog_test() {
  use connection <- with_seeded_database()
  let before = released_today(connection)
  let weekday =
    count(connection, "select strftime('%w', 'now') not in ('0', '6')")
  let assert Ok(_) = flow.pull(connection, "ws-analysis", None, None)
  // A pull further down the Value Stream is no release.
  let assert Ok(_) = flow.pull(connection, "ws-web", None, None)
  assert released_today(connection) == before + weekday
}

pub fn a_day_is_on_plan_within_one_piece_of_gap_test() {
  let cell = heijunka.MixCell(day: "2026-11-02", planned: 0.0, real: 2)
  assert heijunka.on_plan(cell) == False
  assert heijunka.on_plan(heijunka.MixCell(..cell, planned: 1.2)) == True
}
