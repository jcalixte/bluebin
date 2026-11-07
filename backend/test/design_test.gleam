import bluebin/db
import bluebin/design.{
  type Design, type Station, type Step, Design, Invalid, Station, Step,
}
import gleam/dict
import gleam/dynamic/decode
import gleam/json
import gleam/list
import gleam/option.{None, Some}
import gleam/string
import sqlight

fn with_seeded_database(run: fn(sqlight.Connection) -> a) -> a {
  use connection <- db.with_connection_at(":memory:")
  let assert Ok(Nil) = db.prepare(connection)
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

fn current(connection: sqlight.Connection) -> Design {
  let assert Ok(#(found, _)) = design.load(connection)
  found
}

fn kanbans_of(connection: sqlight.Connection, station: String) -> Int {
  count(
    connection,
    "select count(*) from kanban where station_id = '" <> station <> "'",
  )
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

fn changes(connection: sqlight.Connection) -> Int {
  count(
    connection,
    "select count(*) from flow_event where kind = 'line_changed'",
  )
}

fn change_station(
  wanted: Design,
  id: String,
  change: fn(Station) -> Station,
) -> Design {
  Design(
    ..wanted,
    steps: list.map(wanted.steps, fn(step) {
      Step(
        ..step,
        stations: list.map(step.stations, fn(station) {
          case station.id == Some(id) {
            True -> change(station)
            False -> station
          }
        }),
      )
    }),
  )
}

fn release_step() -> Step {
  Step(name: "Release", stations: [
    Station(
      id: None,
      name: "Release",
      branch: None,
      blue_bins: 2,
      team_leader: "pe-ines",
      team_members: ["pe-ines"],
    ),
  ])
}

fn trunk(name: String) -> Step {
  Step(name:, stations: [
    Station(
      id: None,
      name:,
      branch: None,
      blue_bins: 1,
      team_leader: "pe-ines",
      team_members: ["pe-ines"],
    ),
  ])
}

fn split(name: String, branches: List(String)) -> Step {
  Step(
    name:,
    stations: list.map(branches, fn(branch) {
      Station(
        id: None,
        name: name <> " " <> branch,
        branch: Some(branch),
        blue_bins: 1,
        team_leader: "pe-ines",
        team_members: ["pe-ines"],
      )
    }),
  )
}

fn refused(result: Result(a, design.DesignError), words: String) -> Bool {
  case result {
    Error(Invalid(reason)) -> string.contains(reason, words)
    _ -> False
  }
}

pub fn a_split_between_two_trunk_steps_is_a_valid_shape_test() {
  assert design.check_structure([
      trunk("Analysis"),
      split("Build", ["Web", "iOS"]),
      split("QA", ["iOS", "Web"]),
      trunk("UAT"),
    ])
    == Ok(Nil)
}

pub fn the_first_step_cannot_be_a_split_test() {
  let assert Error(_) =
    design.check_structure([split("Build", ["Web", "iOS"]), trunk("UAT")])
}

pub fn the_branches_need_an_assembly_after_them_test() {
  let assert Error(_) =
    design.check_structure([trunk("Analysis"), split("Build", ["Web", "iOS"])])
}

pub fn a_split_needs_two_branches_test() {
  let assert Error(_) =
    design.check_structure([trunk("A"), split("Build", ["Web"]), trunk("B")])
}

pub fn two_branches_cannot_share_a_name_test() {
  let assert Error(_) =
    design.check_structure([
      trunk("A"),
      split("Build", ["Web", "Web"]),
      trunk("B"),
    ])
}

pub fn nested_splits_are_refused_test() {
  let assert Error(_) =
    design.check_structure([
      trunk("A"),
      split("Build", ["Web", "iOS"]),
      split("QA", ["Web", "iOS", "Android"]),
      trunk("B"),
    ])
}

pub fn an_empty_line_is_refused_test() {
  let assert Error(_) = design.check_structure([])
}

pub fn the_seed_design_shows_the_work_held_test() {
  use connection <- with_seeded_database()
  let assert Ok(#(found, held)) = design.load(connection)
  assert list.map(found.steps, fn(step) { list.length(step.stations) })
    == [1, 1, 3, 3, 1]
  let json = design.to_json(found, held, [], 0.0, dict.new()) |> json.to_string
  assert string.contains(json, "\"labels\":{\"demand\":\"Feature\"")
}

pub fn saving_the_same_design_changes_nothing_test() {
  use connection <- with_seeded_database()
  let before = current(connection)
  let assert Ok(after) = design.save(connection, before)
  assert after == before
  assert changes(connection) == 0
}

pub fn the_order_of_the_team_members_is_not_a_change_test() {
  use connection <- with_seeded_database()
  let wanted =
    current(connection)
    |> change_station("ws-analysis", fn(s) {
      Station(..s, team_members: list.reverse(s.team_members))
    })
  let assert Ok(_) = design.save(connection, wanted)
  assert changes(connection) == 0
}

pub fn a_new_work_station_gets_one_kanban_per_blue_bin_test() {
  use connection <- with_seeded_database()
  let before = current(connection)
  let assert Ok(after) =
    design.save(
      connection,
      Design(..before, steps: list.append(before.steps, [release_step()])),
    )
  let assert Ok(Step(stations: [Station(id: Some(id), ..)], ..)) =
    list.last(after.steps)
  assert kanbans_of(connection, id) == 2
  assert kanbans_over_empty_blue_bins(connection) == 0
  assert count(
      connection,
      "select count(*) from flow_event
        where kind = 'line_changed'
          and json_extract(payload, '$.change') = 'station_added'",
    )
    == 1
}

pub fn an_empty_work_station_can_go_and_takes_its_kanbans_back_test() {
  use connection <- with_seeded_database()
  let before = current(connection)
  let assert Ok(_) =
    design.save(
      connection,
      Design(..before, steps: list.append(before.steps, [release_step()])),
    )
  let assert Ok(after) = design.save(connection, before)
  assert list.length(after.steps) == 5
  assert count(connection, "select count(*) from work_station") == 9
  assert count(
      connection,
      "select count(*) from flow_event where kind = 'kanban_spent'
        and json_extract(payload, '$.station') not in (select id from work_station)",
    )
    == 2
}

pub fn a_work_station_that_holds_work_cannot_go_test() {
  use connection <- with_seeded_database()
  let before = current(connection)
  let wanted = Design(..before, steps: list.drop(before.steps, 1))
  assert refused(design.save(connection, wanted), "holds work")
  assert count(connection, "select count(*) from work_station") == 9
}

pub fn work_stations_that_hold_work_keep_their_order_test() {
  use connection <- with_seeded_database()
  let before = current(connection)
  let assert [first, second, ..rest] = before.steps
  let wanted = Design(..before, steps: [second, first, ..rest])
  assert refused(design.save(connection, wanted), "keep their order")
}

pub fn a_branch_that_holds_work_keeps_its_name_test() {
  use connection <- with_seeded_database()
  let wanted =
    current(connection)
    |> change_station("ws-web", fn(s) { Station(..s, branch: Some("Webapp")) })
    |> change_station("ws-qa-web", fn(s) {
      Station(..s, branch: Some("Webapp"))
    })
  assert refused(design.save(connection, wanted), "Branch cannot change")
}

pub fn more_blue_bins_send_kanbans_and_fewer_take_them_back_test() {
  use connection <- with_seeded_database()
  let before = kanbans_of(connection, "ws-uat")
  let assert Ok(_) =
    design.save(
      connection,
      current(connection)
        |> change_station("ws-uat", fn(s) { Station(..s, blue_bins: 3) }),
    )
  assert kanbans_of(connection, "ws-uat") == before + 2
  assert kanbans_over_empty_blue_bins(connection) == 0

  let assert Ok(_) =
    design.save(
      connection,
      current(connection)
        |> change_station("ws-uat", fn(s) { Station(..s, blue_bins: 1) }),
    )
  assert kanbans_of(connection, "ws-uat") == before
  assert kanbans_over_empty_blue_bins(connection) == 0
}

pub fn a_blue_bin_that_holds_a_piece_cannot_go_test() {
  use connection <- with_seeded_database()
  let wanted =
    current(connection)
    |> change_station("ws-conception", fn(s) { Station(..s, blue_bins: 1) })
  let assert Ok(_) = design.save(connection, wanted)
  let wanted =
    current(connection)
    |> change_station("ws-conception", fn(s) { Station(..s, blue_bins: 0) })
  let assert Error(Invalid(_)) = design.save(connection, wanted)
}

pub fn a_team_member_with_work_in_hand_stays_in_the_work_station_test() {
  use connection <- with_seeded_database()
  let wanted =
    current(connection)
    |> change_station("ws-analysis", fn(s) {
      Station(..s, team_members: ["pe-ines"], team_leader: "pe-ines")
    })
  assert refused(design.save(connection, wanted), "work in hand")
}

pub fn the_team_leader_is_one_of_the_team_members_test() {
  use connection <- with_seeded_database()
  let wanted =
    current(connection)
    |> change_station("ws-uat", fn(s) { Station(..s, team_leader: "pe-tom") })
  assert refused(design.save(connection, wanted), "Team Leader")
}

pub fn a_refused_change_writes_nothing_test() {
  use connection <- with_seeded_database()
  let before = current(connection)
  let wanted =
    Design(
      ..before,
      steps: list.append(before.steps, [release_step()]),
      labels: design.Labels("Epic", "Epics", "Story", "Stories"),
    )
    |> change_station("ws-uat", fn(s) { Station(..s, team_leader: "pe-tom") })
  let assert Error(Invalid(_)) = design.save(connection, wanted)
  assert current(connection) == before
  assert changes(connection) == 0
}

pub fn labels_are_free_for_each_line_test() {
  use connection <- with_seeded_database()
  let before = current(connection)
  let labels = design.Labels("Epic", "Epics", "Story", "Stories")
  let assert Ok(_) = design.save(connection, Design(..before, labels:))
  assert design.load_labels(connection) == Ok(labels)
  assert changes(connection) == 1
}

pub fn the_demo_reset_puts_back_the_labels_test() {
  use connection <- with_seeded_database()
  let before = current(connection)
  let labels = design.Labels("Epic", "Epics", "Story", "Stories")
  let assert Ok(_) = design.save(connection, Design(..before, labels:))
  let assert Ok(Nil) = db.reset(connection)
  assert design.load_labels(connection) == Ok(before.labels)
}

pub fn a_new_team_member_can_join_a_work_station_test() {
  use connection <- with_seeded_database()
  let assert Ok(team_member) = design.add_team_member(connection, "  Zoé ")
  assert team_member.name == "Zoé"
  let wanted =
    current(connection)
    |> change_station("ws-uat", fn(s) {
      Station(
        ..s,
        team_members: [team_member.id, ..s.team_members],
        team_leader: team_member.id,
      )
    })
  let assert Ok(_) = design.save(connection, wanted)
  assert count(connection, "select count(*) from work_station
        where id = 'ws-uat' and team_leader = '" <> team_member.id <> "'") == 1
  assert refused(design.add_team_member(connection, " "), "name")
}

fn without_team_member(wanted: Design, id: String) -> Design {
  let wanted =
    Design(
      ..wanted,
      team_members: list.filter(wanted.team_members, fn(team_member) {
        team_member.id != id
      }),
    )
  Design(
    ..wanted,
    steps: list.map(wanted.steps, fn(step) {
      Step(
        ..step,
        stations: list.map(step.stations, fn(station) {
          Station(
            ..station,
            team_members: list.filter(station.team_members, fn(team_member) {
              team_member != id
            }),
          )
        }),
      )
    }),
  )
}

pub fn a_team_member_with_no_work_in_hand_can_go_test() {
  use connection <- with_seeded_database()
  let wanted = current(connection) |> without_team_member("pe-karim")
  let assert Ok(saved) = design.save(connection, wanted)
  assert !list.any(saved.team_members, fn(team_member) {
    team_member.id == "pe-karim"
  })
  assert current(connection) == saved
  assert count(
      connection,
      "select count(*) from station_team_member where team_member_id = 'pe-karim'",
    )
    == 0
  // The row stays, so the history keeps the name.
  assert count(
      connection,
      "select count(*) from team_member
        where id = 'pe-karim' and name = 'Karim' and removed_at is not null",
    )
    == 1
  assert count(
      connection,
      "select count(*) from flow_event where kind = 'line_changed'
        and payload ->> 'change' = 'team_member_removed'",
    )
    == 1
}

pub fn a_removed_team_member_cannot_stay_in_a_work_station_test() {
  use connection <- with_seeded_database()
  let before = current(connection)
  let wanted =
    Design(
      ..before,
      team_members: list.filter(before.team_members, fn(team_member) {
        team_member.id != "pe-karim"
      }),
    )
  assert refused(design.save(connection, wanted), "not in the Line any more")
  assert current(connection) == before
}

pub fn a_team_member_with_work_in_hand_cannot_go_test() {
  use connection <- with_seeded_database()
  let wanted = current(connection) |> without_team_member("pe-marc")
  assert refused(design.save(connection, wanted), "work in hand")
}
