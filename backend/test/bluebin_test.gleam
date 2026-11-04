import bluebin/db
import bluebin/demand.{type Demand, Demand}
import bluebin/flow
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

// --- Takt Time and Takt Gap, the arithmetic of the roof (F1, F2, F11) ---

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
  // Twice as many Pieces in the same time halves the Takt Time.
  assert demand.takt_time_hours(a_demand(20, 0, 10, 0)) == 3.5
}

pub fn takt_time_of_a_demand_asking_nothing_is_zero_test() {
  assert demand.takt_time_hours(a_demand(0, 0, 10, 0)) == 0.0
}

pub fn takt_gap_is_zero_when_the_demand_is_on_its_takt_test() {
  // Half the working time spent, half the Pieces in production.
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
  // Half a Piece late is late, but not a whole Piece late: no Andon yet.
  assert demand.takt_gap(a_demand(10, 9, 20, 19)) == -0.5
  assert demand.andon(a_demand(10, 9, 20, 19)) == False
  assert demand.andon(a_demand(10, 3, 10, 8)) == True
}

pub fn the_value_stream_takt_combines_every_demand_test() {
  // Two Demands, one Piece every 7 hours each: together one every 3.5 hours.
  let demands = [a_demand(10, 0, 10, 0), a_demand(10, 0, 10, 0)]
  assert demand.value_stream_takt_hours(demands) == 3.5
  // A Demand that asks for nothing has no Takt Time and must not count.
  assert demand.value_stream_takt_hours([a_demand(0, 0, 10, 0)]) == 0.0
}

pub fn behind_count_counts_only_the_demands_with_an_andon_test() {
  let demands = [a_demand(10, 3, 10, 8), a_demand(10, 5, 10, 5)]
  assert demand.behind_count(demands) == 1
}

// --- Schema, migration and seed, against a real in-memory database ---

fn with_seeded_database(run: fn(sqlight.Connection) -> a) -> a {
  use connection <- db.with_connection_at(":memory:")
  let assert Ok(Nil) = db.prepare(connection)
  run(connection)
}

/// A database as bluebin.app had it before Sub-Pieces: migrated to v4 only,
/// with whole Pieces in the Branches.
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
  // No Work Station holds more parked Pieces than the Blue Bins it declares.
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

/// The invariant of F7, read straight from the database: a Work Station never
/// holds more Kanbans than it has empty Blue Bins.
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

// --- Pull, finish and deliver: the rules of the Kanban (F7, F24, F6, F9) ---

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
  let assert Ok(flowed) = flow.pull(connection, "ws-conception", None)
  assert flowed.piece == "US-2"
  assert flowed.deviation == None
  assert flowed.kanbans_sent_to == ["ws-analysis"]
  assert kanbans(connection, "ws-conception") == 0
  assert state_of(connection, "p-billing-2") == "in_flow"
  assert kanbans_over_empty_blue_bins(connection) == 0
}

pub fn the_first_work_station_pulls_out_of_the_backlog_test() {
  use connection <- with_seeded_database()
  let backlog =
    count(connection, "select count(*) from piece where state = 'backlog'")

  let assert Ok(flowed) = flow.pull(connection, "ws-analysis", None)
  // Nothing sits upstream of the first Work Station, so no Kanban goes back.
  assert flowed.kanbans_sent_to == []
  assert kanbans(connection, "ws-analysis") == 0
  assert count(connection, "select count(*) from piece where state = 'backlog'")
    == backlog - 1
}

// --- The Split: each Branch pulls its own Sub-Piece (CONTEXT.md) ---

pub fn each_branch_pulls_its_own_sub_piece_at_the_split_test() {
  use connection <- with_seeded_database()
  // US-9 waits in Tech Conception's Blue Bin. iOS pulls first...
  let assert Ok(ios) = flow.pull(connection, "ws-ios", None)
  assert ios.piece == "US-9 · iOS"
  // ...and the Piece stays in the Blue Bin, so Web can still pull its part.
  assert state_of(connection, "p-checkout-9") == "in_bin"
  assert ios.kanbans_sent_to == []

  let assert Ok(web) = flow.pull(connection, "ws-web", None)
  assert web.piece == "US-9 · Web"
  // A Branch never pulls the same Piece twice.
  assert flow.pull(connection, "ws-web", Some("again"))
    == Error(flow.NothingToPull)
}

pub fn the_piece_leaves_the_trunk_when_the_last_branch_pulls_test() {
  use connection <- with_seeded_database()
  let assert Ok(_) = flow.pull(connection, "ws-web", None)
  let assert Ok(_) = flow.pull(connection, "ws-ios", None)
  assert kanbans(connection, "ws-conception") == 1

  let assert Ok(android) = flow.pull(connection, "ws-android", None)
  // The Blue Bin is empty only now: Tech Conception gets its Kanban back.
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
  // QA iOS holds no Kanban; iOS has US-8's iOS part in a Blue Bin.
  assert kanbans(connection, "ws-qa-ios") == 0
  assert flow.pull(connection, "ws-qa-ios", None)
    == Error(flow.NeedsConfirmation(flow.PullWithoutKanban))
  // The warning changed nothing.
  assert state_of(connection, "p-checkout-8-ios") == "in_bin"
  assert flow.pull(connection, "ws-qa-ios", Some("   "))
    == Error(flow.NeedsConfirmation(flow.PullWithoutKanban))

  let assert Ok(flowed) =
    flow.pull(connection, "ws-qa-ios", Some("Blocking the demo"))
  assert flowed.piece == "US-8 · iOS"
  assert flowed.deviation == Some(flow.PullWithoutKanban)
  assert flowed.kanbans_sent_to == ["ws-ios"]
  assert count(
      connection,
      "select count(*) from deviation
       where rule = 'pull_without_kanban' and station_id = 'ws-qa-ios'
         and reason = 'Blocking the demo'",
    )
    == 1
}

// --- The Assembly: the Work Station after the Branches (F8) ---

pub fn the_assembly_waits_for_every_sub_piece_test() {
  use connection <- with_seeded_database()
  // US-4: Web and Android parts wait in QA, the iOS part is still in hand.
  assert flow.pull(connection, "ws-uat", None) == Error(flow.NothingToAssemble)
  assert state_of(connection, "p-offline-4-web") == "in_bin"
}

pub fn the_assembly_joins_the_sub_pieces_and_sends_each_branch_a_kanban_test() {
  use connection <- with_seeded_database()
  let assert Ok(_) =
    flow.finish(connection, "ws-qa-ios", "p-offline-4-ios", None)

  let assert Ok(flowed) = flow.pull(connection, "ws-uat", None)
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
  assert flowed.deviation == None
  assert state_of(connection, "p-billing-2") == "in_bin"
  assert kanbans_over_empty_blue_bins(connection) == 0
}

pub fn a_second_piece_in_a_blue_bin_is_warned_then_recorded_test() {
  use connection <- with_seeded_database()
  // Analysis with no Blue Bin left: its Piece has nowhere to wait.
  exec(
    connection,
    "update work_station set blue_bins = 0 where id = 'ws-analysis'",
  )

  assert flow.finish(connection, "ws-analysis", "p-billing-2", None)
    == Error(flow.NeedsConfirmation(flow.SecondPieceInABlueBin))
  assert state_of(connection, "p-billing-2") == "in_flow"

  let assert Ok(flowed) =
    flow.finish(
      connection,
      "ws-analysis",
      "p-billing-2",
      Some("UAT asked for it today"),
    )
  assert flowed.deviation == Some(flow.SecondPieceInABlueBin)
  assert state_of(connection, "p-billing-2") == "in_bin"
}

pub fn a_piece_the_work_station_does_not_hold_cannot_be_finished_test() {
  use connection <- with_seeded_database()
  assert flow.finish(connection, "ws-web", "p-billing-2", None)
    == Error(flow.PieceNotHere)
  assert flow.pull(connection, "ws-nowhere", None) == Error(flow.UnknownStation)
}

pub fn delivering_sends_a_kanban_back_to_the_last_work_station_test() {
  use connection <- with_seeded_database()
  // UAT ends the chain: it spent its Kanban and holds a finished Piece.
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
  let assert Ok(_) = flow.pull(connection, "ws-web", None)
  let assert Ok(_) = flow.finish(connection, "ws-web", "p-checkout-9-web", None)
  assert count(connection, "select count(*) from flow_event") == before + 2
}

pub fn the_reset_keeps_the_names_of_the_steps_test() {
  use connection <- with_database_at_version_4()
  let assert Ok(_) = value_stream.rename_step(connection, 2, "Design")
  let assert Ok(Nil) = db.prepare(connection)
  // The demo data is seeded again, and the team's own words stay.
  assert count(connection, "select count(*) from demand") == 3
  assert count(
      connection,
      "select count(*) from piece where parent_id is not null",
    )
    == 6
  let assert Ok(steps) = value_stream.list_steps(connection)
  assert list.contains(steps, value_stream.Step(position: 2, name: "Design"))
}

// --- The two read endpoints, through their real queries ---

pub fn the_demands_payload_carries_the_takt_numbers_test() {
  use connection <- with_seeded_database()
  let assert Ok(demands) = demand.list_active(connection)
  assert list.length(demands) == 3
  // Every active Demand has a Takt Time, so none of them asks for no Piece.
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
  // The seeded Rework is open, so it must reach the screen.
  assert string.contains(text, "Sync retries lose the last edit")
}

// --- Naming the steps of the chain (F41) ---

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
  // The name is stored trimmed, and what the API answers is what was stored.
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
  // One character shorter is accepted.
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
