import bluebin/andon
import bluebin/assignment
import bluebin/calendar
import bluebin/db
import bluebin/demand
import bluebin/design
import bluebin/flow
import bluebin/heijunka
import bluebin/line
import bluebin/lines
import bluebin/live
import bluebin/measures
import bluebin/spa
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
        ["api", "events"] -> events(request, hub, lines.first)
        ["api", "lines", line, "events"] -> events(request, hub, line)
        _ -> api(request)
      }
    }
    |> mist.new
    |> mist.bind("0.0.0.0")
    |> mist.port(8000)
    |> mist.start

  process.sleep_forever()
}

fn events(
  request: request.Request(mist.Connection),
  hub: live.Hub,
  line: String,
) -> response.Response(mist.ResponseData) {
  let empty = fn(status) {
    response.new(status) |> response.set_body(mist.Bytes(bytes_tree.new()))
  }
  case workspace.from_request(request), lines.is_id(line) {
    Error(Nil), _ -> empty(401)
    Ok(_), False -> empty(404)
    Ok(workspace), True ->
      live.stream(request, hub, lines.channel(workspace, line))
  }
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
    segments -> {
      use workspace <- require_workspace(request)
      case segments {
        ["api", "lines"] ->
          case request.method {
            http.Post -> create_line(request, workspace)
            _ -> {
              use <- wisp.require_method(request, http.Get)
              list_lines(workspace)
            }
          }
        ["api", "lines", line] -> {
          use <- wisp.require_method(request, http.Put)
          rename_line(request, workspace, line)
        }
        ["api", "lines", line, ..rest] ->
          in_line(request, hub, workspace, line, ["api", ..rest])
        // The routes of the first Line, as before an account could
        // own several: scripts and an SPA still open during a deploy use them.
        ["api", ..] -> in_line(request, hub, workspace, lines.first, segments)
        _ -> wisp.not_found()
      }
    }
  }
}

/// `segments` is the path inside the Line, `["api", "demands"]` for
/// both `/api/demands` and `/api/lines/<id>/demands`.
fn in_line(
  request: wisp.Request,
  hub: live.Hub,
  workspace: String,
  line: String,
  segments: List(String),
) -> wisp.Response {
  case lines.database(workspace, line) {
    Error(lines.UnknownLine) -> wisp.not_found()
    Error(_) -> wisp.internal_server_error()
    Ok(database) -> {
      use <- announce_change(
        request,
        hub,
        lines.channel(workspace, line),
        segments,
      )
      route(request, segments, database)
    }
  }
}

fn list_lines(workspace: String) -> wisp.Response {
  case lines.list(workspace) {
    Ok(found) ->
      wisp.json_response(json.to_string(json.array(found, line_json)), 200)
    Error(_) -> wisp.internal_server_error()
  }
}

fn create_line(request: wisp.Request, workspace: String) -> wisp.Response {
  use name <- require_line_name(request)
  line_response(lines.create(workspace, name), 201)
}

fn rename_line(
  request: wisp.Request,
  workspace: String,
  line: String,
) -> wisp.Response {
  use name <- require_line_name(request)
  line_response(lines.rename(workspace, line, name), 200)
}

fn require_line_name(
  request: wisp.Request,
  next: fn(String) -> wisp.Response,
) -> wisp.Response {
  use body <- wisp.require_json(request)
  case decode.run(body, decode.field("name", decode.string, decode.success)) {
    Ok(name) -> next(name)
    Error(_) -> wisp.bad_request("expected a body like {\"name\": \"Mobile\"}")
  }
}

fn line_response(
  result: Result(lines.Line, lines.LineError),
  status: Int,
) -> wisp.Response {
  case result {
    Ok(line) -> wisp.json_response(json.to_string(line_json(line)), status)
    Error(lines.EmptyName) -> wisp.bad_request("a Line needs a name")
    Error(lines.NameTooLong) ->
      wisp.bad_request(
        "a Line name stays under "
        <> int.to_string(lines.max_name_length)
        <> " characters",
      )
    Error(lines.UnknownLine) -> wisp.not_found()
    Error(lines.StoreFailed) -> wisp.internal_server_error()
  }
}

fn line_json(line: lines.Line) -> json.Json {
  json.object([
    #("id", json.string(line.id)),
    #("name", json.string(line.name)),
  ])
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

fn route(
  request: wisp.Request,
  segments: List(String),
  database: String,
) -> wisp.Response {
  case segments {
    ["api", "demands"] ->
      case request.method {
        http.Post -> create_demand(request, database)
        _ -> {
          use <- wisp.require_method(request, http.Get)
          demands(database)
        }
      }
    ["api", "line"] -> {
      use <- wisp.require_method(request, http.Get)
      line_view(database)
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
    ["api", "people"] ->
      case request.method {
        http.Post -> add_team_member(request, database)
        _ -> {
          use <- wisp.require_method(request, http.Get)
          team_members(database)
        }
      }
    ["api", "design"] ->
      case request.method {
        http.Put -> save_design(request, database)
        _ -> {
          use <- wisp.require_method(request, http.Get)
          design_of(database)
        }
      }
    ["api", "labels"] -> {
      use <- wisp.require_method(request, http.Get)
      labels(database)
    }
    ["api", "people", team_member, "next"] -> {
      use <- wisp.require_method(request, http.Get)
      next_thing(team_member, database)
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
      reset(request, database)
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

fn design_of(database: String) -> wisp.Response {
  case db.with_connection_at(database, design.load) {
    Ok(#(found, held)) ->
      wisp.json_response(json.to_string(design.to_json(found, held)), 200)
    Error(Nil) -> wisp.internal_server_error()
  }
}

fn save_design(request: wisp.Request, database: String) -> wisp.Response {
  use body <- wisp.require_json(request)
  case decode.run(body, design.decoder()) {
    Error(_) ->
      wisp.bad_request(
        "expected the body of GET /api/design: {\"labels\", \"people\", \"steps\"}",
      )
    Ok(wanted) ->
      case
        db.with_connection_at(database, fn(connection) {
          use _ <- result.try(design.save(connection, wanted))
          design.load(connection) |> result.replace_error(design.StoreFailed)
        })
      {
        Ok(#(saved, held)) ->
          wisp.json_response(json.to_string(design.to_json(saved, held)), 200)
        Error(design.Invalid(reason)) -> wisp.bad_request(reason)
        Error(design.StoreFailed) -> wisp.internal_server_error()
      }
  }
}

fn add_team_member(request: wisp.Request, database: String) -> wisp.Response {
  use body <- wisp.require_json(request)
  case decode.run(body, decode.field("name", decode.string, decode.success)) {
    Error(_) -> wisp.bad_request("expected a body like {\"name\": \"Inès\"}")
    Ok(name) ->
      case
        db.with_connection_at(database, fn(connection) {
          design.add_team_member(connection, name)
        })
      {
        Ok(team_member) ->
          wisp.json_response(
            json.to_string(
              json.object([
                #("id", json.string(team_member.id)),
                #("name", json.string(team_member.name)),
              ]),
            ),
            201,
          )
        Error(design.Invalid(reason)) -> wisp.bad_request(reason)
        Error(design.StoreFailed) -> wisp.internal_server_error()
      }
  }
}

fn labels(database: String) -> wisp.Response {
  case db.with_connection_at(database, design.load_labels) {
    Ok(found) ->
      wisp.json_response(json.to_string(design.labels_json(found)), 200)
    Error(Nil) -> wisp.internal_server_error()
  }
}

/// `{"mode": "empty"}` starts from scratch; anything else, or no body at all
/// as the SPA sent before, puts back the demo data.
fn reset(request: wisp.Request, database: String) -> wisp.Response {
  let mode =
    wisp.read_body_bits(request)
    |> result.try(fn(body) {
      json.parse_bits(body, decode.field("mode", decode.string, decode.success))
      |> result.replace_error(Nil)
    })
  let run = case mode {
    Ok("empty") -> db.reset_empty
    _ -> db.reset
  }
  case db.with_connection_at(database, run) {
    Ok(Nil) -> wisp.no_content()
    Error(_) -> wisp.internal_server_error()
  }
}

/// Every write that succeeds changes what the open screens show, so the rule
/// lives here once and a new endpoint cannot forget it.
fn announce_change(
  request: wisp.Request,
  hub: live.Hub,
  channel: String,
  segments: List(String),
  next: fn() -> wisp.Response,
) -> wisp.Response {
  let response = next()
  case request.method, response.status {
    http.Get, _ | http.Head, _ -> Nil
    _, status if status >= 200 && status < 300 ->
      case segments {
        ["api", ..action] ->
          live.announce(hub, channel, string.join(action, "/"))
        _ -> Nil
      }
    _, _ -> Nil
  }
  response
}

fn demands(database: String) -> wisp.Response {
  let result =
    db.with_connection_at(database, fn(connection) {
      use demands <- result.try(demand.list_active(connection))
      use calendar <- result.try(calendar.load(connection))
      use now <- result.try(andon.now(connection))
      Ok(demand.to_json(demands, calendar, now / 86_400))
    })

  case result {
    Ok(body) -> wisp.json_response(body, 200)
    Error(_) -> wisp.internal_server_error()
  }
}

fn create_demand(request: wisp.Request, database: String) -> wisp.Response {
  use body <- wisp.require_json(request)
  let decoder = {
    use label <- decode.field("label", decode.string)
    use client <- decode.field("client", decode.string)
    use due_on <- decode.field("dueOn", decode.string)
    use pieces <- decode.field("pieces", decode.int)
    decode.success(#(label, client, due_on, pieces))
  }

  case decode.run(body, decoder) {
    Error(_) ->
      wisp.bad_request(
        "expected a body like {\"label\": \"Checkout redesign\", \"client\": \"Retail\", \"dueOn\": \"2026-12-31\", \"pieces\": 8}",
      )
    Ok(#(label, client, due_on, pieces)) ->
      case
        db.with_connection_at(database, fn(connection) {
          demand.create(connection, label, client, due_on, pieces)
        })
      {
        Ok(id) -> json_body([#("id", json.string(id))], 201)
        Error(demand.Invalid(reason)) -> wisp.bad_request(reason)
        Error(demand.StoreFailed) -> wisp.internal_server_error()
      }
  }
}

fn line_view(database: String) -> wisp.Response {
  let result =
    db.with_connection_at(database, fn(connection) {
      use stations <- result.try(line.load(connection))
      use steps <- result.try(line.list_steps(connection))
      use demands <- result.try(demand.list_active(connection))
      use calendar <- result.try(calendar.load(connection))
      use now <- result.try(andon.now(connection))
      use andons <- result.try(andon.andons(connection, calendar, now))
      use #(stale, active) <- result.try(andon.stale(connection, calendar, now))
      let takt = demand.line_takt_hours(demands)
      use bottlenecks <- result.try(andon.bottlenecks(connection, takt))
      Ok(
        json.object([
          #("stations", stations),
          #("steps", line.steps_json(steps)),
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
    use team_member <- decode.optional_field(
      "person",
      None,
      decode.optional(decode.string),
    )
    decode.success(#(station, team_member))
  }

  case decode.run(body, decoder) {
    Error(_) ->
      wisp.bad_request("expected a body like {\"station\": \"ws-web\"}")
    Ok(#(station, team_member)) ->
      andon_response(
        db.with_connection_at(database, fn(connection) {
          flow.raise_andon(connection, station, team_member)
        }),
      )
  }
}

fn close_andon(request: wisp.Request, database: String) -> wisp.Response {
  use body <- wisp.require_json(request)
  let decoder = {
    use station <- decode.field("station", decode.string)
    use team_member <- decode.field("person", decode.string)
    decode.success(#(station, team_member))
  }

  case decode.run(body, decoder) {
    Error(_) ->
      wisp.bad_request(
        "expected a body like {\"station\": \"ws-web\", \"person\": \"pe-bob\"}",
      )
    Ok(#(station, team_member)) ->
      andon_response(
        db.with_connection_at(database, fn(connection) {
          flow.close_andon(connection, station, team_member)
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
    use team_member <- decode.optional_field(
      "person",
      None,
      decode.optional(decode.string),
    )
    use reason <- decode.optional_field(
      "reason",
      None,
      decode.optional(decode.string),
    )
    decode.success(#(station, team_member, reason))
  }

  case decode.run(body, decoder) {
    Error(_) ->
      wisp.bad_request("expected a body like {\"station\": \"ws-web\"}")
    Ok(#(station, team_member, reason)) ->
      flow_response(
        db.with_connection_at(database, fn(connection) {
          flow.pull(connection, station, team_member, reason)
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
              "This Team Member repairs a Rework first. Repair it, or hand it to another Team Member of the Work Station, before pulling a new Piece.",
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
              "An Assignment goes only to a Team Member of the same Work Station.",
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

fn team_members(database: String) -> wisp.Response {
  case db.with_connection_at(database, assignment.team_members) {
    Ok(team_members) ->
      wisp.json_response(
        json.to_string(assignment.team_members_json(team_members)),
        200,
      )
    Error(_) -> wisp.internal_server_error()
  }
}

fn next_thing(team_member: String, database: String) -> wisp.Response {
  case
    db.with_connection_at(database, fn(connection) {
      use view <- result.try(assignment.load(connection, team_member))
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
    Error(assignment.UnknownTeamMember) -> wisp.not_found()
    Error(assignment.ReadFailed) -> wisp.internal_server_error()
  }
}

fn assign(request: wisp.Request, database: String) -> wisp.Response {
  use body <- wisp.require_json(request)
  let decoder = {
    use kind <- decode.field("kind", decode.string)
    use id <- decode.field("id", decode.string)
    use team_member <- decode.field("person", decode.string)
    decode.success(#(kind, id, team_member))
  }
  let parsed = case decode.run(body, decoder) {
    Ok(#("piece", id, team_member)) ->
      Ok(#(flow.PieceAssignment, id, team_member))
    Ok(#("rework", id, team_member)) ->
      Ok(#(flow.ReworkAssignment, id, team_member))
    _ -> Error(Nil)
  }

  case parsed {
    Error(Nil) ->
      wisp.bad_request(
        "expected a body like {\"kind\": \"piece\", \"id\": \"p-checkout-8-web\", \"person\": \"pe-lila\"}",
      )
    Ok(#(kind, id, team_member)) ->
      case
        db.with_connection_at(database, fn(connection) {
          flow.reassign(connection, kind, id, team_member)
        })
      {
        Ok(reassigned) ->
          json_body(
            [
              #("piece", json.string(reassigned.piece)),
              #("person", json.string(reassigned.team_member)),
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
          line.rename_step(connection, position, name)
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
        Error(line.EmptyName) -> wisp.bad_request("a step needs a name")
        Error(line.NameTooLong) ->
          wisp.bad_request(
            "a step name stays under "
            <> int.to_string(line.max_name_length)
            <> " characters",
          )
        Error(line.UnknownStep) -> wisp.not_found()
        Error(line.StoreFailed) -> wisp.internal_server_error()
      }
    }
  }
}
