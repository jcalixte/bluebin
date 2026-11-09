//// The Simulation on Node, whose `node:sqlite` stands in for sql.js. A
//// dependency compiles to JavaScript even when it calls Erlang only, and
//// fails at the call: these tests are the guard.

import gleam/list
import gleam/string
import gleeunit
import simulation

pub fn main() -> Nil {
  gleeunit.main()
}

pub fn every_read_of_the_demo_line_answers_test() {
  let assert Ok(Nil) = simulation.start(True)
  [
    "/api/demands", "/api/andons", "/api/line", "/api/backlog",
    "/api/team-members", "/api/team-members/pe-ines/next", "/api/design",
    "/api/labels", "/api/calendar", "/api/measures", "/api/line-changes",
    "/api/measures/weeks",
  ]
  |> list.each(fn(path) {
    assert simulation.call("GET", path, "", "pe-ines").0 == 200
  })
}

pub fn a_team_member_does_the_flow_test() {
  let assert Ok(Nil) = simulation.start(True)
  let pull = "{\"station\": \"ws-analysis\"}"
  assert simulation.call("POST", "/api/pull", pull, "pe-ines").0 == 200
  assert simulation.call("POST", "/api/andon", pull, "pe-ines").0 == 204
}

pub fn a_team_member_acts_only_as_themselves_test() {
  let assert Ok(Nil) = simulation.start(True)
  let as_bob = "{\"station\": \"ws-analysis\", \"teamMember\": \"pe-bob\"}"
  assert simulation.call("POST", "/api/pull", as_bob, "pe-ines").0 == 403
  assert simulation.call("PUT", "/api/design", "{}", "pe-ines").0 == 403
}

pub fn an_empty_start_leaves_one_team_member_test() {
  let assert Ok(Nil) = simulation.start(False)
  let #(status, body) = simulation.call("GET", "/api/team-members", "", "")
  assert status == 200
  assert string.contains(body, "Team Member 1")
}
