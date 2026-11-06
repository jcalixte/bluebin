import bluebin/andon
import bluebin/assignment
import bluebin/calendar
import bluebin/db
import bluebin/demand
import bluebin/flow
import bluebin/heijunka
import bluebin/live
import bluebin/measures
import bluebin/spa
import bluebin/value_stream
import bluebin/workspace
import gleam/bytes_tree
import gleam/dynamic/decode
import gleam/erlang/process
import gleam/http
import gleam/http/request
import gleam/http/response
import gleam/int
import gleam/json
import gleam/list
import gleam/option.{None}
import gleam/result
import gleam/string
import mist
import simplifile
import sqlight
import wisp
import wisp/wisp_mist

pub fn main() {
  wisp.configure_logger()

  let assert Ok(Nil) = simplifile.create_directory_all(db.workspaces_directory)
  let assert Ok(hub) = live.start()

  let api =
    fn(request) { handle_request(request, hub) }
    |> wisp_mist.handler(wisp.random_string(64))

  // The event stream holds its socket open, so it goes to mist directly and
  // never through wisp, which expects a response it can send and close.
  let assert Ok(_) =
    fn(request) {
      case request.path_segments(request) {
        ["api", "events"] ->
          case workspace.from_request(request) {
            Ok(workspace) -> live.stream(request, hub, workspace)
            Error(Nil) ->
              response.new(401)
              |> response.set_body(mist.Bytes(bytes_tree.new()))
          }
        _ -> api(request)
      }
    }
    |> mist.new
    |> mist.bind("0.0.0.0")
    |> mist.port(8000)
    |> mist.start

  process.sleep_forever()
}

/// Holds the built SPA in the image; absent in dev, where Vite serves it.
const static_directory = "static"

pub fn handle_request(request: wisp.Request, hub: live.Hub) -> wisp.Response {
  // Before the log, so each page load writes one line per API call, not per asset.
  use <- spa.serve(request, from: static_directory)
  use <- wisp.log_request(request)
  use <- wisp.rescue_crashes

  case wisp.path_segments(request) {
    // Open: the container healthcheck has no identity.
    ["api", "health"] -> {
      use <- wisp.require_method(request, http.Get)
      wisp.ok()
    }
    _ -> {
      use workspace <- require_workspace(request)
      let database = db.workspace_path(workspace)
      case db.ready(database) {
        Error(_) -> wisp.internal_server_error()
        Ok(Nil) -> {
          use <- announce_change(request, hub, workspace)
          route(request, database)
        }
      }
    }
  }
}

fn require_workspace(
  request: wisp.Request,
  next: fn(String) -> wisp.Response,
) -> wisp.Response {
  case workspace.from_request(request) {
    Ok(workspace) -> next(workspace)
    Error(Nil) -> wisp.response(401)
  }
}

fn route(request: wisp.Request, database: String) -> wisp.Response {
  case wisp.path_segments(request) {
    ["api", "demands"] -> {
      use <- wisp.require_method(request, http.Get)
      demands(database)
    }
    ["api", "value-stream"] -> {
      use <- wisp.require_method(request, http.Get)
      value_stream(database)
    }
    ["api", "backlog"] -> {
      use <- wisp.require_method(request, http.Get)
      backlog(database)
    }
    ["api", "backlog", "urgent"] -> {
      use <- wisp.require_method(request, http.Post)
      make_urgent(request, database)
    }
    ["api", "pull"] -> {
      use <- wisp.require_method(request, http.Post)
      pull(request, database)
    }
    ["api", "finish"] -> {
      use <- wisp.require_method(request, http.Post)
      finish(request, database)
    }
    ["api", "deliver"] -> {
      use <- wisp.require_method(request, http.Post)
      deliver(request, database)
    }
    ["api", "rework"] -> {
      use <- wisp.require_method(request, http.Post)
      raise_rework(request, database)
    }
    ["api", "rework", "repair"] -> {
      use <- wisp.require_method(request, http.Post)
      repair_rework(request, database)
    }
    ["api", "andons"] -> {
      use <- wisp.require_method(request, http.Get)
      andons(database)
    }
    ["api", "andon"] -> {
      use <- wisp.require_method(request, http.Post)
      raise_andon(request, database)
    }
    ["api", "andon", "close"] -> {
      use <- wisp.require_method(request, http.Post)
      close_andon(request, database)
    }
    ["api", "assign"] -> {
      use <- wisp.require_method(request, http.Post)
      assign(request, database)
    }
    ["api", "people"] -> {
      use <- wisp.require_method(request, http.Get)
      people(database)
    }
    ["api", "people", person, "next"] -> {
      use <- wisp.require_method(request, http.Get)
      next_thing(person, database)
    }
    ["api", "steps", position] -> {
      use <- wisp.require_method(request, http.Put)
      rename_step(request, position, database)
    }
    ["api", "measures"] -> {
      use <- wisp.require_method(request, http.Get)
      measures_of(request, database)
    }
    ["api", "calendar"] ->
      case request.method {
        http.Put -> save_calendar(request, database)
        _ -> {
          use <- wisp.require_method(request, http.Get)
          working_calendar(database)
        }
      }
    ["api", "reset"] -> {
      use <- wisp.require_method(request, http.Post)
      reset(database)
    }
    _ -> wisp.not_found()
  }
}

/// `from` and `to` are days, both included; the last 7 days by default.
fn measures_of(request: wisp.Request, database: String) -> wisp.Response {
  let query = wisp.get_query(request)
  let day = fn(key, default) {
    list.key_find(query, key) |> result.unwrap(default)
  }
  let result =
    db.with_connection_at(database, fn(connection) {
      use #(week_ago, today) <- result.try(
        sqlight.query(
          "select date('now', '-6 day'), date('now')",
          on: connection,
          with: [],
          expecting: {
            use from <- decode.field(0, decode.string)
            use to <- decode.field(1, decode.string)
            decode.success(#(from, to))
          },
        )
        |> result.replace_error(measures.StoreFailed)
        |> result.try(fn(rows) {
          list.first(rows) |> result.replace_error(measures.StoreFailed)
        }),
      )
      measures.load(connection, day("from", week_ago), day("to", today))
    })

  case result {
    Ok(found) ->
      wisp.json_response(json.to_string(measures.to_json(found)), 200)
    Error(measures.InvalidPeriod) ->
      wisp.bad_request(
        "expected ?from=2026-10-30&to=2026-11-05, with from on or before to",
      )
    Error(measures.StoreFailed) -> wisp.internal_server_error()
  }
}

fn working_calendar(database: String) -> wisp.Response {
  case db.with_connection_at(database, calendar.load) {
    Ok(found) ->
      wisp.json_response(json.to_string(calendar.to_json(found)), 200)
    Error(_) -> wisp.internal_server_error()
  }
}

fn save_calendar(request: wisp.Request, database: String) -> wisp.Response {
  use body <- wisp.require_json(request)
  case decode.run(body, calendar.decoder()) {
    Error(_) ->
      wisp.bad_request(
        "expected a body like {\"days\": [1, 2, 3, 4, 5], \"start\": \"09:00\", \"end\": \"16:00\", \"holidays\": [{\"day\": \"2026-12-25\", \"label\": \"Christmas\"}]}",
      )
    Ok(wanted) ->
      case
        db.with_connection_at(database, fn(connection) {
          use _ <- result.try(calendar.save(connection, wanted))
          calendar.load(connection)
          |> result.replace_error(calendar.StoreFailed)
        })
      {
        Ok(saved) ->
          wisp.json_response(json.to_string(calendar.to_json(saved)), 200)
        Error(calendar.Invalid(message)) -> wisp.bad_request(message)
        Error(calendar.StoreFailed) -> wisp.internal_server_error()
      }
  }
}

fn reset(database: String) -> wisp.Response {
  case db.with_connection_at(database, db.reset) {
    Ok(Nil) -> wisp.no_content()
    Error(_) -> wisp.internal_server_error()
  }
}

/// Every write that succeeds changes what the open screens show, so the rule
/// lives here once and a new endpoint cannot forget it.
fn announce_change(
  request: wisp.Request,
  hub: live.Hub,
  workspace: String,
  next: fn() -> wisp.Response,
) -> wisp.Response {
  let response = next()
  case request.method, response.status {
    http.Get, _ | http.Head, _ -> Nil
    _, status if status >= 200 && status < 300 ->
      case wisp.path_segments(request) {
        ["api", ..action] ->
          live.announce(hub, workspace, string.join(action, "/"))
        _ -> Nil
      }
    _, _ -> Nil
  }
  response
}

fn demands(database: String) -> wisp.Response {
  let result =
    db.with_connection_at(database, fn(connection) {
      demand.list_active(connection)
    })

  case result {
    Ok(demands) -> wisp.json_response(demand.to_json(demands), 200)
    Error(_) -> wisp.internal_server_error()
  }
}

fn value_stream(database: String) -> wisp.Response {
  let result =
    db.with_connection_at(database, fn(connection) {
      use stations <- result.try(value_stream.load(connection))
      use steps <- result.try(value_stream.list_steps(connection))
      use demands <- result.try(demand.list_active(connection))
      use calendar <- result.try(calendar.load(connection))
      use now <- result.try(andon.now(connection))
      use andons <- result.try(andon.andons(connection, calendar, now))
      use #(stale, active) <- result.try(andon.stale(connection, calendar, now))
      let takt = demand.value_stream_takt_hours(demands)
      use bottlenecks <- result.try(andon.bottlenecks(connection, takt))
      Ok(
        json.object([
          #("stations", stations),
          #("steps", value_stream.steps_json(steps)),
          #("taktTimeHours", json.float(takt)),
          #("demandsBehind", json.int(demand.behind_count(demands))),
          #("andons", andon.andons_json(andons)),
          #("stale", andon.stale_json(stale)),
          #("activeAssignments", json.int(active)),
          #("bottlenecks", andon.bottlenecks_json(bottlenecks)),
        ]),
      )
    })

  case result {
    Ok(body) -> wisp.json_response(json.to_string(body), 200)
    Error(_) -> wisp.internal_server_error()
  }
}

fn andons(database: String) -> wisp.Response {
  let result =
    db.with_connection_at(database, fn(connection) {
      use calendar <- result.try(calendar.load(connection))
      use now <- result.try(andon.now(connection))
      andon.andons(connection, calendar, now)
    })

  case result {
    Ok(found) ->
      wisp.json_response(json.to_string(andon.andons_json(found)), 200)
    Error(_) -> wisp.internal_server_error()
  }
}

fn raise_andon(request: wisp.Request, database: String) -> wisp.Response {
  use body <- wisp.require_json(request)
  let decoder = {
    use station <- decode.field("station", decode.string)
    use person <- decode.optional_field(
      "person",
      None,
      decode.optional(decode.string),
    )
    decode.success(#(station, person))
  }

  case decode.run(body, decoder) {
    Error(_) ->
      wisp.bad_request("expected a body like {\"station\": \"ws-web\"}")
    Ok(#(station, person)) ->
      andon_response(
        db.with_connection_at(database, fn(connection) {
          flow.raise_andon(connection, station, person)
        }),
      )
  }
}

fn close_andon(request: wisp.Request, database: String) -> wisp.Response {
  use body <- wisp.require_json(request)
  let decoder = {
    use station <- decode.field("station", decode.string)
    use person <- decode.field("person", decode.string)
    decode.success(#(station, person))
  }

  case decode.run(body, decoder) {
    Error(_) ->
      wisp.bad_request(
        "expected a body like {\"station\": \"ws-web\", \"person\": \"pe-bob\"}",
      )
    Ok(#(station, person)) ->
      andon_response(
        db.with_connection_at(database, fn(connection) {
          flow.close_andon(connection, station, person)
        }),
      )
  }
}

fn andon_response(result: Result(Nil, flow.FlowError)) -> wisp.Response {
  case result {
    Ok(Nil) -> wisp.no_content()
    Error(failure) -> flow_response(Error(failure))
  }
}

fn backlog(database: String) -> wisp.Response {
  let result =
    db.with_connection_at(database, fn(connection) {
      use backlog <- result.try(heijunka.load(connection))
      use mix <- result.try(heijunka.product_mix(connection, backlog.demands))
      Ok(heijunka.to_json(backlog, mix))
    })

  case result {
    Ok(body) -> wisp.json_response(json.to_string(body), 200)
    Error(_) -> wisp.internal_server_error()
  }
}

fn make_urgent(request: wisp.Request, database: String) -> wisp.Response {
  use body <- wisp.require_json(request)
  let decoder = {
    use piece <- decode.field("piece", decode.string)
    use reason <- decode.optional_field(
      "reason",
      None,
      decode.optional(decode.string),
    )
    decode.success(#(piece, reason))
  }

  case decode.run(body, decoder) {
    Error(_) ->
      wisp.bad_request("expected a body like {\"piece\": \"p-billing-3\"}")
    Ok(#(piece, reason)) ->
      flow_response(
        db.with_connection_at(database, fn(connection) {
          flow.make_urgent(connection, piece, reason)
        }),
      )
  }
}

fn pull(request: wisp.Request, database: String) -> wisp.Response {
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
        db.with_connection_at(database, fn(connection) {
          flow.pull(connection, station, person, reason)
        }),
      )
  }
}

fn finish(request: wisp.Request, database: String) -> wisp.Response {
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
        db.with_connection_at(database, fn(connection) {
          flow.finish(connection, station, piece, reason)
        }),
      )
  }
}

fn deliver(request: wisp.Request, database: String) -> wisp.Response {
  use body <- wisp.require_json(request)
  let decoder = decode.field("piece", decode.string, decode.success)

  case decode.run(body, decoder) {
    Error(_) ->
      wisp.bad_request("expected a body like {\"piece\": \"p-checkout-9\"}")
    Ok(piece) ->
      flow_response(
        db.with_connection_at(database, fn(connection) {
          flow.deliver(connection, piece)
        }),
      )
  }
}

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
    Error(flow.ReworkFirst) ->
      json_body(
        [
          #("error", json.string("rework_first")),
          #(
            "message",
            json.string(
              "This Person repairs a Rework first. Repair it, or hand it to another Person of the Work Station, before pulling a new Piece.",
            ),
          ),
        ],
        409,
      )
    Error(flow.NotOfStation) ->
      json_body(
        [
          #("error", json.string("not_of_station")),
          #(
            "message",
            json.string(
              "An Assignment goes only to a Person of the same Work Station.",
            ),
          ),
        ],
        409,
      )
    Error(flow.ReorderNeedsConfirmation(effects)) ->
      json_body(
        [
          #(
            "confirm",
            json.string(flow.rule_name(flow.ReorderHeijunkaSequence)),
          ),
          #(
            "message",
            json.string(flow.rule_warning(flow.ReorderHeijunkaSequence)),
          ),
          #("effects", heijunka.effects_json(effects)),
        ],
        409,
      )
    Error(flow.NotNextOfDemand) ->
      json_body(
        [
          #("error", json.string("not_next_of_demand")),
          #(
            "message",
            json.string(
              "Inside one Demand, Pieces leave the Backlog first-in, first-out. Only the next Piece of this Demand can be made urgent.",
            ),
          ),
        ],
        409,
      )
    Error(flow.NoAndon) ->
      json_body(
        [
          #("error", json.string("no_andon")),
          #("message", json.string("No Andon stops this Work Station.")),
        ],
        409,
      )
    Error(flow.NotTeamLeader) ->
      json_body(
        [
          #("error", json.string("not_team_leader")),
          #(
            "message",
            json.string(
              "Only the Team Leader of the Work Station closes its Andon.",
            ),
          ),
        ],
        409,
      )
    Error(flow.UnknownStation) -> wisp.not_found()
    Error(flow.StoreFailed) -> wisp.internal_server_error()
  }
}

fn raise_rework(request: wisp.Request, database: String) -> wisp.Response {
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
        db.with_connection_at(database, fn(connection) {
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

fn repair_rework(request: wisp.Request, database: String) -> wisp.Response {
  use body <- wisp.require_json(request)
  let decoder = decode.field("rework", decode.string, decode.success)

  case decode.run(body, decoder) {
    Error(_) -> wisp.bad_request("expected a body like {\"rework\": \"rw-1\"}")
    Ok(rework) ->
      case
        db.with_connection_at(database, fn(connection) {
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

fn people(database: String) -> wisp.Response {
  case db.with_connection_at(database, assignment.people) {
    Ok(people) ->
      wisp.json_response(json.to_string(assignment.people_json(people)), 200)
    Error(_) -> wisp.internal_server_error()
  }
}

fn next_thing(person: String, database: String) -> wisp.Response {
  case
    db.with_connection_at(database, fn(connection) {
      use view <- result.try(assignment.load(connection, person))
      use andons <- result.try(
        {
          use calendar <- result.try(calendar.load(connection))
          use now <- result.try(andon.now(connection))
          andon.andons(connection, calendar, now)
        }
        |> result.replace_error(assignment.ReadFailed),
      )
      let mine =
        andon.of_stations(
          andons,
          list.map(view.lists, fn(one) { one.station_id }),
        )
      Ok(assignment.to_json(view, andon.andons_json(mine)))
    })
  {
    Ok(body) -> wisp.json_response(json.to_string(body), 200)
    Error(assignment.UnknownPerson) -> wisp.not_found()
    Error(assignment.ReadFailed) -> wisp.internal_server_error()
  }
}

fn assign(request: wisp.Request, database: String) -> wisp.Response {
  use body <- wisp.require_json(request)
  let decoder = {
    use kind <- decode.field("kind", decode.string)
    use id <- decode.field("id", decode.string)
    use person <- decode.field("person", decode.string)
    decode.success(#(kind, id, person))
  }
  let parsed = case decode.run(body, decoder) {
    Ok(#("piece", id, person)) -> Ok(#(flow.PieceAssignment, id, person))
    Ok(#("rework", id, person)) -> Ok(#(flow.ReworkAssignment, id, person))
    _ -> Error(Nil)
  }

  case parsed {
    Error(Nil) ->
      wisp.bad_request(
        "expected a body like {\"kind\": \"piece\", \"id\": \"p-checkout-8-web\", \"person\": \"pe-lila\"}",
      )
    Ok(#(kind, id, person)) ->
      case
        db.with_connection_at(database, fn(connection) {
          flow.reassign(connection, kind, id, person)
        })
      {
        Ok(reassigned) ->
          json_body(
            [
              #("piece", json.string(reassigned.piece)),
              #("person", json.string(reassigned.person)),
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

fn rename_step(
  request: wisp.Request,
  position: String,
  database: String,
) -> wisp.Response {
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
        db.with_connection_at(database, fn(connection) {
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
