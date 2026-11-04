import bluebin/db
import bluebin/demand
import bluebin/flow
import bluebin/value_stream
import gleam/dynamic/decode
import gleam/erlang/process
import gleam/http
import gleam/int
import gleam/json
import gleam/list
import gleam/option.{None}
import gleam/result
import gleam/string
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
    ["api", "pull"] -> {
      use <- wisp.require_method(request, http.Post)
      pull(request)
    }
    ["api", "finish"] -> {
      use <- wisp.require_method(request, http.Post)
      finish(request)
    }
    ["api", "deliver"] -> {
      use <- wisp.require_method(request, http.Post)
      deliver(request)
    }
    ["api", "rework"] -> {
      use <- wisp.require_method(request, http.Post)
      raise_rework(request)
    }
    ["api", "rework", "repair"] -> {
      use <- wisp.require_method(request, http.Post)
      repair_rework(request)
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

// --- The three flow actions: pull, finish, deliver (F7, F24, F6, F9, F30) ---

/// `{"station": "ws-web", "reason": "…"}` — the reason is given only to
/// confirm a warned pull, and makes it a Deviation.
fn pull(request: wisp.Request) -> wisp.Response {
  use body <- wisp.require_json(request)
  let decoder = {
    use station <- decode.field("station", decode.string)
    use person <- decode.optional_field(
      "person",
      None,
      decode.optional(decode.string),
    )
    use reason <- decode.optional_field(
      "reason",
      None,
      decode.optional(decode.string),
    )
    decode.success(#(station, person, reason))
  }

  case decode.run(body, decoder) {
    Error(_) ->
      wisp.bad_request("expected a body like {\"station\": \"ws-web\"}")
    Ok(#(station, person, reason)) ->
      flow_response(
        db.with_connection(fn(connection) {
          flow.pull(connection, station, person, reason)
        }),
      )
  }
}

/// `{"station": "ws-web", "piece": "p-checkout-8", "reason": "…"}`
fn finish(request: wisp.Request) -> wisp.Response {
  use body <- wisp.require_json(request)
  let decoder = {
    use station <- decode.field("station", decode.string)
    use piece <- decode.field("piece", decode.string)
    use reason <- decode.optional_field(
      "reason",
      None,
      decode.optional(decode.string),
    )
    decode.success(#(station, piece, reason))
  }

  case decode.run(body, decoder) {
    Error(_) ->
      wisp.bad_request(
        "expected a body like {\"station\": \"ws-web\", \"piece\": \"p-checkout-8\"}",
      )
    Ok(#(station, piece, reason)) ->
      flow_response(
        db.with_connection(fn(connection) {
          flow.finish(connection, station, piece, reason)
        }),
      )
  }
}

/// `{"piece": "p-checkout-9"}` — production pulls the Piece out of the last
/// Blue Bin of the chain.
fn deliver(request: wisp.Request) -> wisp.Response {
  use body <- wisp.require_json(request)
  let decoder = decode.field("piece", decode.string, decode.success)

  case decode.run(body, decoder) {
    Error(_) ->
      wisp.bad_request("expected a body like {\"piece\": \"p-checkout-9\"}")
    Ok(piece) ->
      flow_response(
        db.with_connection(fn(connection) { flow.deliver(connection, piece) }),
      )
  }
}

/// One shape for the three actions: what moved, or what the Person must
/// confirm first with a reason (F6, F9, F31).
fn flow_response(result: Result(flow.Flowed, flow.FlowError)) -> wisp.Response {
  case result {
    Ok(flowed) ->
      json_body(
        [
          #("piece", json.string(flowed.piece)),
          #("demand", json.string(flowed.demand)),
          #(
            "deviations",
            json.array(flowed.deviations, fn(rule) {
              json.string(flow.rule_name(rule))
            }),
          ),
          #("kanbansSentTo", json.array(flowed.kanbans_sent_to, json.string)),
        ],
        200,
      )
    Error(flow.NeedsConfirmation(rules)) ->
      json_body(
        [
          #(
            "confirm",
            json.string(list.map(rules, flow.rule_name) |> string.join(" ")),
          ),
          #(
            "rules",
            json.array(rules, fn(rule) { json.string(flow.rule_name(rule)) }),
          ),
          #(
            "message",
            json.string(list.map(rules, flow.rule_warning) |> string.join(" ")),
          ),
        ],
        409,
      )
    Error(flow.NothingToPull) ->
      json_body(
        [
          #("error", json.string("nothing_to_pull")),
          #(
            "message",
            json.string(
              "No Piece waits upstream of this Work Station, so there is nothing to pull.",
            ),
          ),
        ],
        409,
      )
    Error(flow.NothingToAssemble) ->
      json_body(
        [
          #("error", json.string("nothing_to_assemble")),
          #(
            "message",
            json.string(
              "No Piece has every Sub-Piece waiting in the last Blue Bin of its Branch, so there is nothing to assemble.",
            ),
          ),
        ],
        409,
      )
    Error(flow.PieceNotHere) ->
      json_body(
        [
          #("error", json.string("piece_not_here")),
          #(
            "message",
            json.string("This Piece is no longer where the action expects it."),
          ),
        ],
        409,
      )
    Error(flow.NotUpstream) ->
      json_body(
        [
          #("error", json.string("not_upstream")),
          #(
            "message",
            json.string(
              "A Piece never moves backward: the defect belongs to a Work Station it already crossed.",
            ),
          ),
        ],
        409,
      )
    Error(flow.EmptyDescription) ->
      wisp.bad_request("a Rework says in one line what the defect is")
    Error(flow.UnknownRework) ->
      json_body(
        [
          #("error", json.string("unknown_rework")),
          #("message", json.string("This Rework is already repaired.")),
        ],
        409,
      )
    Error(flow.UnknownStation) -> wisp.not_found()
    Error(flow.StoreFailed) -> wisp.internal_server_error()
  }
}

// --- Jidoka: raise a Rework, repair it (F12, F13) ---

/// `{"station": "ws-qa-ios", "piece": "p-offline-4-ios",
///   "madeBy": "ws-ios", "description": "…"}` — the Work Station that found
/// the defect names the one that made it.
fn raise_rework(request: wisp.Request) -> wisp.Response {
  use body <- wisp.require_json(request)
  let decoder = {
    use station <- decode.field("station", decode.string)
    use piece <- decode.field("piece", decode.string)
    use made_by <- decode.field("madeBy", decode.string)
    use description <- decode.field("description", decode.string)
    decode.success(#(station, piece, made_by, description))
  }

  case decode.run(body, decoder) {
    Error(_) ->
      wisp.bad_request(
        "expected a body like {\"station\": \"ws-qa-ios\", \"piece\": \"p-offline-4-ios\", \"madeBy\": \"ws-ios\", \"description\": \"…\"}",
      )
    Ok(#(station, piece, made_by, description)) ->
      case
        db.with_connection(fn(connection) {
          flow.raise_rework(connection, station, piece, made_by, description)
        })
      {
        Ok(raised) ->
          json_body(
            [
              #("id", json.string(raised.id)),
              #("piece", json.string(raised.piece)),
              #("demand", json.string(raised.demand)),
              #("assignee", json.nullable(raised.assignee, json.string)),
              #("paused", json.nullable(raised.paused, json.string)),
            ],
            200,
          )
        Error(failure) -> flow_response(Error(failure))
      }
  }
}

/// `{"rework": "rw-…"}` — the defect is repaired and the Rework closes.
fn repair_rework(request: wisp.Request) -> wisp.Response {
  use body <- wisp.require_json(request)
  let decoder = decode.field("rework", decode.string, decode.success)

  case decode.run(body, decoder) {
    Error(_) -> wisp.bad_request("expected a body like {\"rework\": \"rw-1\"}")
    Ok(rework) ->
      case
        db.with_connection(fn(connection) {
          flow.repair_rework(connection, rework)
        })
      {
        Ok(repaired) ->
          json_body(
            [
              #("piece", json.string(repaired.piece)),
              #("resumed", json.nullable(repaired.resumed, json.string)),
            ],
            200,
          )
        Error(failure) -> flow_response(Error(failure))
      }
  }
}

fn json_body(fields: List(#(String, json.Json)), status: Int) -> wisp.Response {
  wisp.json_response(json.to_string(json.object(fields)), status)
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
