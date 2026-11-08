//// The Simulation: one Line that lives only in the page. The browser runs
//// the API's own routes and guard on it, as the Team Member it picks.

import bluebin
import bluebin/access
import bluebin/db
import gleam/http
import gleam/http/request
import gleam/result
import sqlight
import wisp/simulate

/// The `node:sqlite` stand-in of the SPA keeps one in-memory database per
/// name, so every connection of the routes opens this same Line.
const database = "simulation"

/// The demo data, or one Work Station and one Team Member to rename.
pub fn start(demo: Bool) -> Result(Nil, String) {
  db.with_connection_at(database, fn(connection) {
    use _ <- result.try(db.prepare(connection, db.Demo))
    case demo {
      True -> db.reset(connection)
      False -> db.reset_empty(connection)
    }
  })
  |> result.map_error(fn(error: sqlight.Error) { error.message })
}

/// One API call inside the Line, as `team_member`, or as the owner when it
/// is empty. Answers the status and the body.
pub fn call(
  method: String,
  path: String,
  body: String,
  team_member: String,
) -> #(Int, String) {
  case http.parse_method(method) {
    Error(Nil) -> #(405, "")
    Ok(method) -> {
      let role = case team_member {
        "" -> access.Owner
        _ -> access.Member(team_member)
      }
      let response =
        simulate.request(method, path)
        |> simulate.string_body(body)
        |> request.set_header("content-type", "application/json")
        |> bluebin.simulate(role, database)
      #(response.status, simulate.read_body(response))
    }
  }
}
