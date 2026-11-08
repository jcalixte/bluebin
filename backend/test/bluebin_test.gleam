import bluebin/andon
import bluebin/assignment
import bluebin/calendar
import bluebin/db
import bluebin/demand.{type Demand, Demand}
import bluebin/flow
import bluebin/heijunka
import bluebin/line
import bluebin/measures
import gleam/dynamic/decode
import gleam/int
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
  pieces_deployed: Int,
  working_days_total: Int,
  working_days_elapsed: Int,
) -> Demand {
  Demand(
    id: "d-test",
    label: "Test",
    client: "Client",
    due_on: "2026-12-31",
    pieces_asked:,
    pieces_deployed:,
    working_days_total:,
    working_days_elapsed:,
    hours_per_day: 7.0,
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

pub fn the_line_takt_combines_every_demand_test() {
  // Two Demands, one Piece every 7 hours each: together one every 3.5 hours.
  let demands = [a_demand(10, 0, 10, 0), a_demand(10, 0, 10, 0)]
  assert demand.line_takt_hours(demands) == 3.5
  assert demand.line_takt_hours([a_demand(0, 0, 10, 0)]) == 0.0
}

pub fn behind_count_counts_only_the_demands_with_an_andon_test() {
  let demands = [a_demand(10, 3, 10, 8), a_demand(10, 5, 10, 5)]
  assert demand.behind_count(demands) == 1
}

fn with_seeded_database(run: fn(sqlight.Connection) -> a) -> a {
  use connection <- db.with_connection_at(":memory:")
  let assert Ok(Nil) = db.prepare(connection, db.Demo)
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

pub fn the_seed_fills_the_line_test() {
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
  let assert Ok(Nil) = db.prepare(connection, db.Demo)
  assert count(connection, "select count(*) from demand") == 3
  assert count(connection, "select count(*) from work_station") == 9
}

/// Row counts of every table, plus the step names and Piece states, so two
/// databases with the same seed give the same fingerprint.
fn fingerprint(connection: sqlight.Connection) -> List(Int) {
  [
    "demand", "piece", "flow_event", "team_member", "work_station",
    "station_team_member", "kanban", "rework", "deviation", "piece_pass",
    "line_step",
  ]
  |> list.map(fn(table) { count(connection, "select count(*) from " <> table) })
  |> list.append([
    count(connection, "select count(*) from line_step where name like 'Step %'"),
    count(connection, "select count(*) from piece where state = 'deployed'"),
  ])
}

pub fn the_demo_reset_puts_back_the_seed_test() {
  use connection <- with_seeded_database()
  let seeded = fingerprint(connection)
  let assert Ok(_) = flow.pull(connection, "ws-web", None, None)
  let assert Ok(_) = line.rename_step(connection, 2, "Design")
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
      "select count(*) from flow_event
       where kind = 'piece_assembled' and piece_id = 'p-offline-4'",
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

  let assert Ok(flowed) = flow.deploy(connection, "p-billing-3", hold: False)
  assert flowed.kanbans_sent_to == ["ws-uat"]
  assert state_of(connection, "p-billing-3") == "deployed"
  assert kanbans_over_empty_blue_bins(connection) == 0
}

pub fn only_the_last_work_station_deploys_test() {
  use connection <- with_seeded_database()
  assert flow.deploy(connection, "p-checkout-9", hold: False)
    == Error(flow.PieceNotHere)
}

pub fn every_action_writes_one_flow_event_test() {
  use connection <- with_seeded_database()
  let pieces = "select count(*) from flow_event where kind like 'piece_%'"
  let before = count(connection, pieces)
  let assert Ok(_) = flow.pull(connection, "ws-web", None, None)
  let assert Ok(_) = flow.finish(connection, "ws-web", "p-checkout-9-web", None)
  assert count(connection, pieces) == before + 2
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
  // A pause for Rework is a real loss of capacity: it counts in the
  // suggested Blue Bins (DESIGN.md R11).
  assert count(
      connection,
      "select count(*) from flow_event
       where kind = 'piece_paused' and piece_id = 'p-checkout-9-ios'
         and json_extract(payload, '$.cause') = 'rework'",
    )
    == 1
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
  // Karim is a Team Member of iOS, not of Web.
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
         and team_member_id = 'pe-karim'",
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
  let assert Ok(payload) = line.load(connection)
  let text = json.to_string(payload)
  assert string.contains(text, "\"firstPassYield\"")
  assert string.contains(text, "\"reworkHours\"")
  assert string.contains(text, "\"firstPassYield\":0.91")
  // Three hours of Rework stand against iOS, the Work Station that made it.
  assert string.contains(text, "\"reworkHours\":3.0")

  exec(connection, "delete from piece_pass where station_id = 'ws-uat'")
  let assert Ok(empty) = line.load(connection)
  assert string.contains(json.to_string(empty), "\"firstPassYield\":null")
}

fn assignee(
  connection: sqlight.Connection,
  table: String,
  id: String,
) -> String {
  let assert Ok([team_member]) =
    sqlight.query(
      "select coalesce(assignee, '') from " <> table <> " where id = ?1",
      on: connection,
      with: [sqlight.text(id)],
      expecting: decode.at([0], decode.string),
    )
  team_member
}

fn next_of(
  connection: sqlight.Connection,
  team_member: String,
) -> assignment.Next {
  let assert Ok(view) = assignment.load(connection, team_member)
  view.next
}

pub fn a_team_member_repairs_their_rework_before_pulling_test() {
  use connection <- with_seeded_database()
  // Alice holds the seeded Rework.
  assert flow.pull(connection, "ws-ios", Some("pe-alice"), None)
    == Error(flow.ReworkFirst)
  assert kanbans(connection, "ws-ios") == 1
  // Karim, also of iOS, has free hands.
  let assert Ok(_) = flow.pull(connection, "ws-ios", Some("pe-karim"), None)
  assert kanbans(connection, "ws-ios") == 0
}

pub fn a_new_piece_waits_behind_the_one_in_hand_test() {
  use connection <- with_seeded_database()
  // In the seed, Bob holds US-8's Web part: finishing beats starting.
  let assert Ok(_) = flow.pull(connection, "ws-web", Some("pe-bob"), None)
  assert state_of(connection, "p-checkout-8-web") == "in_flow"
  assert state_of(connection, "p-checkout-9-web") == "paused"
  assert count(
      connection,
      "select count(*) from flow_event
       where kind = 'piece_paused' and piece_id = 'p-checkout-9-web'
         and json_extract(payload, '$.cause') = 'held'",
    )
    == 1

  let assert Ok(_) = flow.finish(connection, "ws-web", "p-checkout-8-web", None)
  assert state_of(connection, "p-checkout-9-web") == "in_flow"
  assert count(
      connection,
      "select count(*) from flow_event
       where kind in ('piece_paused', 'piece_resumed')
         and piece_id = 'p-checkout-9-web'",
    )
    == 2
  assert count(
      connection,
      "select count(*) from flow_event
       where kind = 'piece_paused' and piece_id = 'p-checkout-8-web'",
    )
    == 0
}

fn pieces_of(
  connection: sqlight.Connection,
  team_member: String,
  station: String,
  state: String,
) -> Int {
  count(
    connection,
    "select count(*) from piece where assignee = '" <> team_member <> "'
       and station_id = '" <> station <> "' and state = '" <> state <> "'",
  )
}

pub fn a_new_piece_upstream_waits_behind_the_one_downstream_test() {
  use connection <- with_seeded_database()
  // Marc takes US-2 from Analysis into Tech Conception, downstream.
  let assert Ok(_) = flow.finish(connection, "ws-analysis", "p-billing-2", None)
  let assert Ok(_) =
    flow.pull(connection, "ws-conception", Some("pe-marc"), None)
  assert state_of(connection, "p-billing-2") == "in_flow"

  let assert Ok(_) = flow.pull(connection, "ws-analysis", Some("pe-marc"), None)
  assert state_of(connection, "p-billing-2") == "in_flow"
  assert pieces_of(connection, "pe-marc", "ws-analysis", "paused") == 1

  let assert Ok(_) =
    flow.finish(connection, "ws-conception", "p-billing-2", None)
  assert pieces_of(connection, "pe-marc", "ws-analysis", "in_flow") == 1
}

pub fn a_new_piece_downstream_goes_before_the_one_upstream_test() {
  use connection <- with_seeded_database()
  // A Piece for Tech Conception, while Marc still holds US-2 in Analysis.
  let assert Ok(_) = flow.pull(connection, "ws-analysis", None, None)
  let assert Ok([ready]) =
    sqlight.query(
      "select id from piece
        where station_id = 'ws-analysis' and state = 'in_flow'
          and assignee is null",
      on: connection,
      with: [],
      expecting: decode.at([0], decode.string),
    )
  let assert Ok(_) = flow.finish(connection, "ws-analysis", ready, None)
  assert state_of(connection, "p-billing-2") == "in_flow"

  let assert Ok(_) =
    flow.pull(connection, "ws-conception", Some("pe-marc"), None)
  assert pieces_of(connection, "pe-marc", "ws-conception", "in_flow") == 1
  assert state_of(connection, "p-billing-2") == "paused"
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

pub fn a_piece_in_hand_goes_to_another_team_member_of_the_work_station_test() {
  use connection <- with_seeded_database()
  let assert Ok(handed) =
    flow.reassign(
      connection,
      flow.PieceAssignment,
      "p-checkout-8-web",
      "pe-lila",
    )
  assert handed.team_member == "Lila"
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

pub fn without_a_kanban_a_team_member_helps_downstream_test() {
  use connection <- with_seeded_database()
  // Web's Kanban is spent and QA Web's Blue Bins are full: QA Web holds up
  // the flow in front of Lila.
  exec(
    connection,
    "delete from kanban where station_id = 'ws-web';
     update work_station set blue_bins = 0 where id = 'ws-web'",
  )
  let assert assignment.HelpDownstream(station_id: "ws-qa-web", ..) =
    next_of(connection, "pe-lila")
}

pub fn a_work_station_stopped_by_its_rework_gets_help_only_from_the_two_test() {
  use connection <- with_seeded_database()
  // Everyone has free hands and no Kanban; QA iOS waits on rw-1, which
  // Alice repairs.
  exec(connection, "delete from kanban; update piece set assignee = null")
  // QA iOS found the defect, iOS made it: both Help the Rework (F19).
  let assert assignment.HelpTheRework(
    rework: "rw-1",
    piece: "US-4 · iOS",
    assignee: "Alice",
    station_id: "ws-qa-ios",
    ..,
  ) = next_of(connection, "pe-yasmine")
  let assert assignment.HelpTheRework(rework: "rw-1", ..) =
    next_of(connection, "pe-karim")
  // A third Work Station is not sent to QA iOS (F22).
  list.each(["pe-marc", "pe-sofia", "pe-ines"], fn(team_member) {
    let assert False = case next_of(connection, team_member) {
      assignment.HelpDownstream(station_id: "ws-qa-ios", ..) -> True
      assignment.HelpTheRework(..) -> True
      _ -> False
    }
  })

  // Once Karim helps, his next thing is the help itself.
  let assert Ok(_) = flow.help_the_rework(connection, "rw-1", "pe-karim")
  let assert assignment.Helping(rework: "rw-1", assignee: "Alice", ..) =
    next_of(connection, "pe-karim")
}

pub fn the_holder_of_a_piece_under_rework_helps_its_repair_test() {
  use connection <- with_seeded_database()
  // In the seed, Yasmine holds US-4 at QA iOS while Alice repairs it.
  let assert assignment.HelpTheRework(rework: "rw-1", assignee: "Alice", ..) =
    next_of(connection, "pe-yasmine")
  // Once repaired, she finishes it.
  let assert Ok(_) = flow.repair_rework(connection, "rw-1")
  let assert assignment.Continue(assignment.Transform(id: "p-offline-4-ios", ..)) =
    next_of(connection, "pe-yasmine")
}

pub fn nobody_is_sent_to_help_a_rework_nobody_repairs_test() {
  use connection <- with_seeded_database()
  exec(
    connection,
    "delete from kanban; update piece set assignee = null;
     update rework set assignee = null",
  )
  let assert False = case next_of(connection, "pe-yasmine") {
    assignment.HelpTheRework(..) -> True
    _ -> False
  }
}

pub fn with_nothing_to_take_or_help_a_team_member_waits_test() {
  use connection <- with_seeded_database()
  // Tom's Kanban at QA Web has no Piece upstream, and nothing downstream of
  // his Work Stations holds up the flow.
  assert next_of(connection, "pe-tom") == assignment.Wait
  assert assignment.load(connection, "pe-nobody")
    == Error(assignment.UnknownTeamMember)
}

pub fn the_team_member_payload_carries_the_shape_the_screen_reads_test() {
  use connection <- with_seeded_database()
  let assert Ok(view) = assignment.load(connection, "pe-alice")
  let text =
    json.to_string(assignment.to_json(view, json.preprocessed_array([])))
  assert string.contains(text, "\"next\":{\"kind\":\"continue\"")
  assert string.contains(text, "\"kind\":\"rework\",\"id\":\"rw-1\"")
  assert string.contains(text, "\"priorityLists\":[{\"station\":\"ws-ios\"")
  let assert Ok(team_members) = assignment.team_members(connection)
  // Nearest to Deployment first.
  assert list.contains(
    team_members,
    assignment.TeamMember(id: "pe-marc", name: "Marc", stations: [
      "Tech Conception", "Analysis",
    ]),
  )
}

pub fn the_demands_payload_carries_the_takt_numbers_test() {
  use connection <- with_seeded_database()
  let assert Ok(demands) = demand.list_active(connection)
  assert list.length(demands) == 3
  assert list.all(demands, fn(one) { demand.takt_time_hours(one) >. 0.0 })

  let assert Ok(working) = calendar.load(connection)
  let payload = demand.to_json(demands, working, 20_763)
  assert payload != "[]"
  assert string.contains(payload, "\"forecastOn\":")
  assert string.contains(payload, "\"forecastLateDays\":")
}

pub fn the_line_payload_lists_every_work_station_test() {
  use connection <- with_seeded_database()
  let assert Ok(payload) = line.load(connection)
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
  let assert Ok(steps) = line.list_steps(connection)
  assert list.length(steps) == 5
  let assert [first, ..] = steps
  assert first.name == "From the Backlog"
}

pub fn a_step_can_be_renamed_test() {
  use connection <- with_seeded_database()
  let assert Ok(step) = line.rename_step(connection, 2, "  Design  ")
  assert step.name == "Design"
  let assert Ok(steps) = line.list_steps(connection)
  assert list.contains(steps, line.Step(position: 2, name: "Design"))
}

pub fn a_rename_is_dated_in_the_flow_event_log_test() {
  use connection <- with_seeded_database()
  let before = count(connection, "select count(*) from flow_event")
  let assert Ok(_) = line.rename_step(connection, 2, "  Design ")
  assert count(connection, "select count(*) from flow_event") == before + 1
  assert count(
      connection,
      "select count(*) from flow_event
       where kind = 'step_renamed' and json_valid(payload)
         and payload ->> '$.name' = 'Design'",
    )
    == 1
  assert count(
      connection,
      "select count(*) from line_step
       where position = 2 and renamed_at is not null",
    )
    == 1
}

pub fn a_step_never_loses_its_name_test() {
  use connection <- with_seeded_database()
  assert line.rename_step(connection, 2, "   ") == Error(line.EmptyName)
  let assert Ok(steps) = line.list_steps(connection)
  assert list.contains(steps, line.Step(position: 2, name: "Step 2"))
}

pub fn a_step_name_stays_short_enough_for_a_wall_tv_test() {
  use connection <- with_seeded_database()
  let too_long = string.repeat("a", line.max_name_length + 1)
  assert line.rename_step(connection, 2, too_long) == Error(line.NameTooLong)
  let longest = string.repeat("a", line.max_name_length)
  let assert Ok(step) = line.rename_step(connection, 2, longest)
  assert step.name == longest
}

pub fn renaming_a_step_that_does_not_exist_is_refused_test() {
  use connection <- with_seeded_database()
  assert line.rename_step(connection, 99, "Nowhere") == Error(line.UnknownStep)
}

pub fn a_quote_in_a_name_is_stored_as_typed_test() {
  use connection <- with_seeded_database()
  let assert Ok(step) = line.rename_step(connection, 2, "Dev's turn")
  assert step.name == "Dev's turn"
}

/// Days of 7 hours; today is the first day left.
fn heijunka_demand(id: String, due_on: String, days_left: Int) -> Demand {
  Demand(..a_demand(10, 0, 10, 11 - days_left), id:, label: id, due_on:)
}

fn waiting(
  id: String,
  demand: String,
  arrived: Int,
  urgent: option.Option(Int),
) -> heijunka.Waiting {
  heijunka.Waiting(id:, reference: id, demand:, arrived:, urgent:)
}

fn ids(sequence: List(heijunka.Placed)) -> List(String) {
  list.map(sequence, fn(placed) { placed.piece.id })
}

pub fn the_heijunka_sequence_takes_the_earliest_slot_first_test() {
  let demands = [
    heijunka_demand("a", "2026-12-01", 10),
    heijunka_demand("b", "2026-12-31", 10),
  ]
  // 70 h left. a: 2 Pieces, slots 17.5 h and 52.5 h. b: 4 Pieces, slots
  // 8.75 h, 26.25 h, 43.75 h and 61.25 h.
  let sequence =
    heijunka.sequence(
      [
        waiting("a1", "a", 1, None),
        waiting("a2", "a", 2, None),
        waiting("b1", "b", 3, None),
        waiting("b2", "b", 4, None),
        waiting("b3", "b", 5, None),
        waiting("b4", "b", 6, None),
      ],
      demands,
    )
  assert ids(sequence) == ["b1", "a1", "b2", "b3", "a2", "b4"]
}

/// Regression: absolute slots (n Takt Times after the start) put every Piece
/// of a late Demand ahead of the others, in one block.
pub fn a_late_demand_gets_more_slots_but_stays_mixed_test() {
  let demands = [
    heijunka_demand("late", "2026-11-12", 5),
    heijunka_demand("soon", "2026-11-18", 11),
    heijunka_demand("later", "2026-12-02", 25),
  ]
  let pieces =
    list.flatten([
      list.map([1, 2, 3, 4, 5], fn(i) { #("late", i) }),
      list.map([1, 2, 3], fn(i) { #("soon", i) }),
      list.map([1, 2, 3, 4, 5, 6], fn(i) { #("later", i) }),
    ])
    |> list.index_map(fn(piece, arrived) {
      let #(demand, i) = piece
      waiting(demand <> int.to_string(i), demand, arrived, None)
    })
  assert ids(heijunka.sequence(pieces, demands))
    == [
      "late1", "late2", "soon1", "later1", "late3", "late4", "late5", "soon2",
      "later2", "soon3", "later3", "later4", "later5", "later6",
    ]
}

pub fn the_heijunka_sequence_ends_a_tie_first_in_first_out_test() {
  let demands = [
    heijunka_demand("a", "2026-12-01", 10),
    heijunka_demand("b", "2026-12-01", 10),
  ]
  let sequence =
    heijunka.sequence(
      [waiting("b1", "b", 2, None), waiting("a1", "a", 1, None)],
      demands,
    )
  assert ids(sequence) == ["a1", "b1"]
}

pub fn urgent_pieces_lead_the_heijunka_sequence_in_their_order_test() {
  let demands = [heijunka_demand("a", "2026-12-01", 10)]
  let sequence =
    heijunka.sequence(
      [
        waiting("a1", "a", 1, None),
        waiting("a2", "a", 2, Some(2)),
        waiting("a3", "a", 3, Some(1)),
      ],
      demands,
    )
  assert ids(sequence) == ["a3", "a2", "a1"]
}

pub fn a_reorder_shows_what_each_demand_gains_and_loses_test() {
  let demands = [
    heijunka_demand("a", "2026-12-01", 10),
    Demand(..heijunka_demand("b", "2026-12-31", 10), pieces_asked: 20),
  ]
  let before =
    heijunka.sequence(
      [waiting("a1", "a", 1, None), waiting("b2", "b", 2, None)],
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
  // A pull further down the Line is no release.
  let assert Ok(_) = flow.pull(connection, "ws-web", None, None)
  assert released_today(connection) == before + weekday
}

pub fn a_day_is_on_plan_within_one_piece_of_gap_test() {
  let cell = heijunka.MixCell(day: "2026-11-02", planned: 0.0, real: 2)
  assert heijunka.on_plan(cell) == False
  assert heijunka.on_plan(heijunka.MixCell(..cell, planned: 1.2)) == True
}

/// Every hour of every day is Working Time, so a test never depends on the
/// clock it runs at.
const always_working =
  calendar.Calendar(
    days: [0, 1, 2, 3, 4, 5, 6],
    start: 0,
    end: 1440,
    holidays: [],
  )

fn andons_now(connection: sqlight.Connection) -> List(andon.Andon) {
  let assert Ok(now) = db.now(connection)
  let assert Ok(found) = andon.andons(connection, always_working, now)
  found
}

pub fn an_andon_stops_the_work_station_until_its_team_leader_closes_it_test() {
  use connection <- with_seeded_database()
  let assert Ok(Nil) = flow.raise_andon(connection, "ws-web", Some("pe-lila"))
  let assert [andon.Stop(station_id: "ws-web", raised_by: Some("Lila"), ..)] =
    andons_now(connection)

  assert flow.close_andon(connection, "ws-web", "pe-lila")
    == Error(flow.NotTeamLeader)
  let assert Ok(Nil) = flow.close_andon(connection, "ws-web", "pe-bob")
  assert andons_now(connection) == []
  assert flow.close_andon(connection, "ws-web", "pe-bob") == Error(flow.NoAndon)
  assert count(
      connection,
      "select count(*) from flow_event
        where kind in ('andon_raised', 'andon_closed')",
    )
    == 2
}

pub fn andon_time_is_the_stop_inside_the_period_test() {
  use connection <- with_seeded_database()
  exec(
    connection,
    "insert into andon (station_id, raised_at, closed_at) values
       ('ws-web', '2026-09-30T23:00:00Z', '2026-10-01T01:00:00Z'),
       ('ws-web', '2026-10-01T10:00:00Z', '2026-10-01T11:30:00Z'),
       ('ws-web', '2026-10-02T10:00:00Z', '2026-10-02T11:00:00Z'),
       ('ws-ios', '2026-10-01T11:00:00Z', '2026-10-01T12:00:00Z')",
  )
  let assert Ok(found) = measures.load(connection, "2026-10-01", "2026-10-01")
  let assert Ok(web) = list.find(found.stations, fn(one) { one.id == "ws-web" })
  // 1 h after midnight of the first stop, and the whole 1 h 30 of the second.
  assert web.andon == 9000
  assert web.andons == 1
  let assert Ok(ios) = list.find(found.stations, fn(one) { one.id == "ws-ios" })
  assert ios.andon == 3600
  let assert Ok(other) =
    list.find(found.stations, fn(one) {
      one.id != "ws-web" && one.id != "ws-ios"
    })
  assert other.andon == 0
  // Web and iOS both stop from 11:00 to 11:30: that half hour counts once.
  assert found.andon == 9000 + 3600 - 1800
}

pub fn a_stopped_work_station_holds_one_andon_test() {
  use connection <- with_seeded_database()
  let assert Ok(Nil) = flow.raise_andon(connection, "ws-web", Some("pe-bob"))
  let assert Ok(Nil) = flow.raise_andon(connection, "ws-web", None)
  assert count(connection, "select count(*) from andon") == 1
}

pub fn a_team_member_not_of_the_work_station_is_not_recorded_as_raising_test() {
  use connection <- with_seeded_database()
  let assert Ok(Nil) = flow.raise_andon(connection, "ws-web", Some("pe-tom"))
  let assert [andon.Stop(raised_by: None, ..)] = andons_now(connection)
}

pub fn a_pull_during_an_andon_is_a_deviation_test() {
  use connection <- with_seeded_database()
  let assert Ok(True) = flow.can_pull(connection, "ws-web")
  let assert Ok(Nil) = flow.raise_andon(connection, "ws-web", None)
  let assert Ok(False) = flow.can_pull(connection, "ws-web")

  assert flow.pull(connection, "ws-web", None, None)
    == Error(flow.NeedsConfirmation([flow.PullDuringAndon]))
  let assert Ok(flowed) =
    flow.pull(connection, "ws-web", None, Some("the build is green again"))
  assert flowed.deviations == [flow.PullDuringAndon]
  assert count(
      connection,
      "select count(*) from deviation where rule = 'pull_during_andon'",
    )
    == 1
}

pub fn a_rework_waiting_an_hour_with_nobody_raises_an_andon_test() {
  use connection <- with_seeded_database()
  exec(
    connection,
    "update rework set assignee = null, started_at = null,
       opened_at = strftime('%Y-%m-%dT%H:%M:%SZ', 'now', '-30 minutes')",
  )
  assert andons_now(connection) == []

  exec(
    connection,
    "update rework
        set opened_at = strftime('%Y-%m-%dT%H:%M:%SZ', 'now', '-2 hours')",
  )
  let assert [andon.ReworkWaits(rework_id: "rw-1", station_id: "ws-ios", ..)] =
    andons_now(connection)
}

pub fn a_rework_in_repair_raises_no_andon_test() {
  use connection <- with_seeded_database()
  exec(
    connection,
    "update rework
        set opened_at = strftime('%Y-%m-%dT%H:%M:%SZ', 'now', '-2 days')",
  )
  // The seed gives rw-1 to Alice, who repairs it now.
  assert andons_now(connection) == []
}

pub fn the_wait_of_a_rework_counts_only_working_time_test() {
  use connection <- with_seeded_database()
  exec(
    connection,
    "update rework set assignee = null, started_at = null,
       opened_at = strftime('%Y-%m-%dT%H:%M:%SZ', 'now', '-2 hours')",
  )
  let assert Ok(now) = db.now(connection)
  let no_working_day =
    calendar.Calendar(days: [], start: 540, end: 960, holidays: [])
  assert andon.andons(connection, no_working_day, now) == Ok([])
}

pub fn an_assignment_with_no_event_for_a_working_day_is_stale_test() {
  use connection <- with_seeded_database()
  let assert Ok(now) = db.now(connection)
  let assert Ok(#(stale, active)) = andon.stale(connection, always_working, now)
  assert stale == []
  // Bob, Nina, Yasmine and Marc hold a Piece; Alice repairs rw-1.
  assert active == 5

  exec(
    connection,
    "update piece
        set since = strftime('%Y-%m-%dT%H:%M:%SZ', 'now', '-2 days')
      where id = 'p-checkout-8-web';
     update rework
        set started_at = strftime('%Y-%m-%dT%H:%M:%SZ', 'now', '-2 days')",
  )
  let assert Ok(#(stale, _)) = andon.stale(connection, always_working, now)
  assert stale
    == [andon.Stale("piece", "p-checkout-8-web"), andon.Stale("rework", "rw-1")]
}

pub fn a_new_event_freshens_a_stale_assignment_test() {
  use connection <- with_seeded_database()
  exec(
    connection,
    "update piece
        set since = strftime('%Y-%m-%dT%H:%M:%SZ', 'now', '-2 days')
      where id = 'p-checkout-8-web';
     insert into flow_event (kind, piece_id) values ('assignment_changed',
       'p-checkout-8-web')",
  )
  let assert Ok(now) = db.now(connection)
  let assert Ok(#([], _)) = andon.stale(connection, always_working, now)
}

pub fn capacity_is_the_average_touch_time_shared_by_the_team_members_test() {
  let station =
    measures.StationMeasure(
      id: "ws-web",
      name: "Web",
      branch: Some("Web"),
      position: 3,
      passes: [
        measures.Span(touch: 7200, stagnation: 0, stagnation_working: 0),
        measures.Span(touch: 14_400, stagnation: 0, stagnation_working: 0),
      ],
      replenishments: [],
      starvation: 0,
      starvation_working: 0,
      andon: 0,
      andon_working: 0,
      andons: 0,
      pulls: 2,
      deviations: 0,
    )
  // 3 hours a Piece on average, shared by 2 Team Members.
  assert andon.capacity_hours(station, 2) == Ok(1.5)
  assert andon.capacity_hours(station, 0) == Error(Nil)
  assert andon.capacity_hours(measures.StationMeasure(..station, passes: []), 2)
    == Error(Nil)
}

pub fn a_full_blue_bin_in_front_makes_a_bottleneck_test() {
  use connection <- with_seeded_database()
  // A Takt Time this long makes no Work Station slower than it.
  let assert Ok(found) = andon.bottlenecks(connection, 10_000.0)
  assert found == []

  exec(
    connection,
    "update piece set state = 'in_bin', station_id = 'ws-analysis',
       since = strftime('%Y-%m-%dT%H:%M:%SZ', 'now')
      where id in ('p-billing-3', 'p-billing-4')",
  )
  let assert Ok(found) = andon.bottlenecks(connection, 10_000.0)
  assert list.map(found, fn(one) { #(one.station_id, one.full_in_front) })
    == [#("ws-conception", True)]
}

pub fn a_work_station_slower_than_the_takt_time_is_a_bottleneck_test() {
  use connection <- with_seeded_database()
  // The seed history gives every Work Station some Touch Time per Piece.
  let assert Ok(found) = andon.bottlenecks(connection, 0.01)
  assert found != []
  assert list.all(found, fn(one) { one.slower })
}

pub fn the_next_thing_shows_only_the_andons_of_my_work_stations_test() {
  use connection <- with_seeded_database()
  let assert Ok(Nil) = flow.raise_andon(connection, "ws-web", None)
  let assert Ok(Nil) = flow.raise_andon(connection, "ws-ios", None)
  let mine = andon.of_stations(andons_now(connection), ["ws-web"])
  let assert [andon.Stop(station_id: "ws-web", ..)] = mine
}

/// A database of a version with no migration step is refused, never read.
pub fn a_database_of_another_schema_version_is_refused_test() {
  use connection <- db.with_connection_at(":memory:")
  exec(connection, "create table person (id text); pragma user_version = 15;")
  let assert Error(_) = db.prepare(connection, db.Demo)
  assert count(
      connection,
      "select count(*) from sqlite_master where name = 'demand'",
    )
    == 0
}

pub fn a_new_database_gets_the_schema_once_test() {
  use connection <- with_seeded_database()
  assert count(connection, "pragma user_version") == 3
  let assert Ok(Nil) = db.prepare(connection, db.Demo)
  assert count(connection, "select count(*) from line_label") == 1
  assert count(connection, "select count(*) from working_calendar") == 1
}

fn helpers(connection: sqlight.Connection) -> Int {
  count(connection, "select count(*) from helper")
}

fn help_left(connection: sqlight.Connection, cause: String) -> Int {
  count(connection, "select count(*) from flow_event
      where kind = 'helper_left'
        and json_extract(payload, '$.cause') = '" <> cause <> "'")
}

pub fn helpers_join_a_rework_and_its_repair_ends_their_help_test() {
  use connection <- with_seeded_database()
  // Karim holds US-9 at iOS; Alice repairs rw-1 on US-4, held by QA iOS.
  let assert Ok(_) = flow.pull(connection, "ws-ios", Some("pe-karim"), None)
  assert state_of(connection, "p-checkout-9-ios") == "in_flow"

  // Yasmine, of the Work Station that found the defect, helps: US-4 is in
  // her own hands, and stays active.
  let assert Ok(helped) = flow.help_the_rework(connection, "rw-1", "pe-yasmine")
  assert helped.piece == "US-4 · iOS"
  assert helped.assignee == "Alice"
  assert helped.paused == []
  assert state_of(connection, "p-offline-4-ios") == "in_flow"

  // Karim, of the Work Station that made it, helps: his US-9 pauses (F62).
  let assert Ok(helped) = flow.help_the_rework(connection, "rw-1", "pe-karim")
  assert helped.paused == ["US-9 · iOS"]
  assert state_of(connection, "p-checkout-9-ios") == "paused"
  assert count(
      connection,
      "select count(*) from flow_event
       where kind = 'piece_paused' and piece_id = 'p-checkout-9-ios'
         and json_extract(payload, '$.cause') = 'helping'",
    )
    == 1
  assert helpers(connection) == 2
  // Joining the same Rework again changes nothing.
  let assert Ok(again) = flow.help_the_rework(connection, "rw-1", "pe-karim")
  assert again.paused == []
  assert count(
      connection,
      "select count(*) from flow_event
                            where kind = 'helper_joined'",
    )
    == 2

  // The repair ends every help and resumes the Helpers' Pieces (F63).
  let assert Ok(_) = flow.repair_rework(connection, "rw-1")
  assert helpers(connection) == 0
  assert help_left(connection, "repaired") == 2
  assert state_of(connection, "p-checkout-9-ios") == "in_flow"
}

pub fn a_helper_stops_and_their_piece_resumes_test() {
  use connection <- with_seeded_database()
  let assert Ok(_) = flow.pull(connection, "ws-ios", Some("pe-karim"), None)
  let assert Ok(_) = flow.help_the_rework(connection, "rw-1", "pe-karim")
  assert state_of(connection, "p-checkout-9-ios") == "paused"

  let assert Ok(stopped) = flow.stop_helping(connection, "pe-karim")
  assert stopped.piece == "US-4 · iOS"
  assert stopped.resumed == Some("US-9 · iOS")
  assert state_of(connection, "p-checkout-9-ios") == "in_flow"
  assert help_left(connection, "stopped") == 1
  assert flow.stop_helping(connection, "pe-karim") == Error(flow.NotHelping)
}

pub fn only_the_two_work_stations_help_while_someone_repairs_test() {
  use connection <- with_seeded_database()
  // Lila is of Web, a third Work Station.
  assert flow.help_the_rework(connection, "rw-1", "pe-lila")
    == Error(flow.NotOfReworkStations)
  assert flow.help_the_rework(connection, "rw-1", "pe-alice")
    == Error(flow.RepairsItAlready)
  assert flow.help_the_rework(connection, "rw-unknown", "pe-karim")
    == Error(flow.UnknownRework)

  exec(connection, "update rework set assignee = null where id = 'rw-1'")
  assert flow.help_the_rework(connection, "rw-1", "pe-yasmine")
    == Error(flow.NobodyRepairs)
  assert helpers(connection) == 0
}

pub fn a_helper_helps_one_piece_and_their_own_rework_comes_first_test() {
  use connection <- with_seeded_database()
  // A second open Rework on another Piece, found by QA iOS.
  exec(
    connection,
    "insert into rework (id, piece_id, station_id, description, raised_by,
                         assignee, started_at)
     values ('rw-2', 'p-checkout-8-web', 'ws-ios', 'Broken', 'ws-qa-ios',
             'pe-alice', strftime('%Y-%m-%dT%H:%M:%SZ', 'now'))",
  )
  let assert Ok(_) = flow.help_the_rework(connection, "rw-1", "pe-karim")
  assert flow.help_the_rework(connection, "rw-2", "pe-karim")
    == Error(flow.HelpsAnotherPiece)

  // Karim takes rw-2: his own repair ends his help.
  let assert Ok(_) =
    flow.reassign(connection, flow.ReworkAssignment, "rw-2", "pe-karim")
  assert helpers(connection) == 0
  assert help_left(connection, "rework") == 1
  assert flow.help_the_rework(connection, "rw-1", "pe-karim")
    == Error(flow.ReworkFirst)
}

pub fn a_pull_by_a_helper_ends_the_help_test() {
  use connection <- with_seeded_database()
  let assert Ok(_) = flow.help_the_rework(connection, "rw-1", "pe-karim")
  let assert Ok(_) = flow.pull(connection, "ws-ios", Some("pe-karim"), None)
  assert helpers(connection) == 0
  assert help_left(connection, "pulled") == 1
  assert state_of(connection, "p-checkout-9-ios") == "in_flow"
}

pub fn a_version_2_database_migrates_to_version_3_test() {
  use connection <- with_seeded_database()
  let pieces = count(connection, "select count(*) from piece")
  let events = count(connection, "select count(*) from flow_event")
  let assert Ok([helper_sql]) =
    sqlight.query(
      "select sql from sqlite_master where name = 'helper'",
      on: connection,
      with: [],
      expecting: decode.at([0], decode.string),
    )
  exec(connection, "drop table helper; pragma user_version = 2;")

  let assert Ok(Nil) = db.prepare(connection, db.Demo)
  assert count(connection, "pragma user_version") == 3
  assert count(connection, "select count(*) from piece") == pieces
  assert count(connection, "select count(*) from flow_event") == events
  assert count(connection, "select count(*) from sqlite_master
        where name = 'helper' and sql = '" <> string.replace(
      helper_sql,
      "'",
      "''",
    ) <> "'") == 1
  let assert Ok(_) = flow.help_the_rework(connection, "rw-1", "pe-karim")

  // A version with no step is refused, not read.
  exec(connection, "pragma user_version = 1;")
  let assert Error(_) = db.prepare(connection, db.Demo)
}
