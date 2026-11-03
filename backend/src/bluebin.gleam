import bluebin/db
import bluebin/demand
import gleam/erlang/process
import gleam/http
import mist
import simplifile
import wisp
import wisp/wisp_mist

pub fn main() {
  wisp.configure_logger()

  let _ = simplifile.create_directory_all("data")
  let assert Ok(Nil) =
    db.with_connection(fn(connection) {
      let assert Ok(Nil) = db.migrate(connection)
      db.seed(connection)
    })

  let assert Ok(_) =
    handle_request
    |> wisp_mist.handler(wisp.random_string(64))
    |> mist.new
    |> mist.bind("0.0.0.0")
    |> mist.port(8000)
    |> mist.start

  process.sleep_forever()
}

fn handle_request(request: wisp.Request) -> wisp.Response {
  use <- wisp.log_request(request)
  use <- wisp.rescue_crashes()

  case wisp.path_segments(request) {
    ["api", "health"] -> {
      use <- wisp.require_method(request, http.Get)
      wisp.ok()
    }
    ["api", "demands"] -> {
      use <- wisp.require_method(request, http.Get)
      demands()
    }
    _ -> wisp.not_found()
  }
}

fn demands() -> wisp.Response {
  let result =
    db.with_connection(fn(connection) { demand.list_active(connection) })

  case result {
    Ok(demands) -> wisp.json_response(demand.to_json(demands), 200)
    Error(_) -> wisp.internal_server_error()
  }
}
