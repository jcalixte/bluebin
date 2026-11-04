import bluebin/db
import bluebin/demand
import bluebin/value_stream
import gleam/dynamic/decode
import gleam/erlang/process
import gleam/http
import gleam/int
import gleam/json
import gleam/result
import mist
import simplifile
import wisp
import wisp/wisp_mist

pub fn main() {
  wisp.configure_logger()

  let _ = simplifile.create_directory_all("data")
  let assert Ok(Nil) = db.with_connection(db.prepare)

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
  use <- wisp.rescue_crashes

  case wisp.path_segments(request) {
    ["api", "health"] -> {
      use <- wisp.require_method(request, http.Get)
      wisp.ok()
    }
    ["api", "demands"] -> {
      use <- wisp.require_method(request, http.Get)
      demands()
    }
    ["api", "value-stream"] -> {
      use <- wisp.require_method(request, http.Get)
      value_stream()
    }
    ["api", "steps", position] -> {
      use <- wisp.require_method(request, http.Put)
      rename_step(request, position)
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

fn value_stream() -> wisp.Response {
  let result =
    db.with_connection(fn(connection) {
      use stations <- result.try(value_stream.load(connection))
      use steps <- result.try(value_stream.list_steps(connection))
      use demands <- result.try(demand.list_active(connection))
      Ok(#(stations, steps, demands))
    })

  case result {
    Ok(#(stations, steps, demands)) ->
      wisp.json_response(
        json.to_string(
          json.object([
            #("stations", stations),
            #("steps", value_stream.steps_json(steps)),
            #(
              "taktTimeHours",
              json.float(demand.value_stream_takt_hours(demands)),
            ),
            #("demandsBehind", json.int(demand.behind_count(demands))),
          ]),
        ),
        200,
      )
    Error(_) -> wisp.internal_server_error()
  }
}

/// Rename one step of the chain. The body is `{"name": "…"}`.
fn rename_step(request: wisp.Request, position: String) -> wisp.Response {
  use body <- wisp.require_json(request)

  let parsed = {
    use position <- result.try(int.parse(position) |> result.replace_error(Nil))
    use name <- result.try(
      decode.run(body, decode.field("name", decode.string, decode.success))
      |> result.replace_error(Nil),
    )
    Ok(#(position, name))
  }

  case parsed {
    Error(Nil) -> wisp.bad_request("expected a body like {\"name\": \"Build\"}")
    Ok(#(position, name)) -> {
      let renamed =
        db.with_connection(fn(connection) {
          value_stream.rename_step(connection, position, name)
        })

      case renamed {
        Ok(step) ->
          wisp.json_response(
            json.to_string(
              json.object([
                #("position", json.int(step.position)),
                #("name", json.string(step.name)),
              ]),
            ),
            200,
          )
        Error(value_stream.EmptyName) -> wisp.bad_request("a step needs a name")
        Error(value_stream.NameTooLong) ->
          wisp.bad_request(
            "a step name stays under "
            <> int.to_string(value_stream.max_name_length)
            <> " characters",
          )
        Error(value_stream.UnknownStep) -> wisp.not_found()
        Error(value_stream.StoreFailed) -> wisp.internal_server_error()
      }
    }
  }
}
