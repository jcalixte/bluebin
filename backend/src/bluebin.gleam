import bluebin/access
import bluebin/accounts
import bluebin/andon
import bluebin/assignment
import bluebin/calendar
import bluebin/db
import bluebin/demand
import bluebin/design
import bluebin/flow
import bluebin/heijunka
import bluebin/holidays
import bluebin/invitations
import bluebin/line
import bluebin/lines
import bluebin/live
import bluebin/measures
import bluebin/spa
import bluebin/workspace
import envoy
import gleam/bool
import gleam/bytes_tree
import gleam/dynamic/decode
import gleam/erlang/process
import gleam/http
import gleam/http/request
import gleam/http/response
import gleam/int
import gleam/json
import gleam/list
import gleam/option.{type Option, None, Some}
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
  // Only behind authentik can the identity headers be trusted (ADR-0003).
  let sso = envoy.get("BLUEBIN_SSO") == Ok("on")
  case sso {
    True -> wisp.log_info("SSO on: an Account is made at its first sign-in")
    False -> wisp.log_info("SSO off: no Account is made")
  }
  let invite =
    envoy.get("AUTHENTIK_TOKEN")
    |> option.from_result
    |> invitations.invite(invitations.http_send)
  let context = Context(hub:, sso:, accounts: accounts.database, invite:)

  let api =
    fn(request) { handle_request(request, context) }
    |> wisp_mist.handler(wisp.random_string(64))

  // The event stream holds its socket open, so it goes to mist directly and
  // never through wisp, which expects a response it can send and close.
  let assert Ok(_) =
    fn(request) {
      case request.path_segments(request) {
        ["api", "events"] -> events(request, context, None, lines.first)
        ["api", "lines", line, "events"] -> events(request, context, None, line)
        ["api", "w", owner, "lines", line, "events"] ->
          events(request, context, Some(owner), line)
        ["api", "s", owner, "lines", line, "events"] ->
          look_events(request, context, owner, line)
        _ -> api(request)
      }
    }
    |> mist.new
    |> mist.bind("0.0.0.0")
    |> mist.port(8000)
    |> mist.start

  process.sleep_forever()
}

/// A Line the caller may not read answers `404`, like the API (F48).
fn events(
  request: request.Request(mist.Connection),
  context: Context,
  owner: Option(String),
  line: String,
) -> response.Response(mist.ResponseData) {
  {
    use caller <- result.try(
      caller_of(request, context) |> result.replace_error(401),
    )
    use workspace <- result.try(case owner {
      None -> Ok(caller)
      Some(owner) -> workspace.parse(owner) |> result.replace_error(404)
    })
    use <- bool.guard(!lines.is_id(line), Error(404))
    use role <- result.map(
      role_of(request, context, caller, workspace, line)
      |> result.replace_error(500),
    )
    #(workspace, role)
  }
  |> stream(request, context, line, _)
}

fn look_events(
  request: request.Request(mist.Connection),
  context: Context,
  owner: String,
  line: String,
) -> response.Response(mist.ResponseData) {
  {
    use workspace <- result.try(
      workspace.parse(owner) |> result.replace_error(404),
    )
    use role <- result.map(
      look_role(context, workspace, line) |> result.replace_error(500),
    )
    #(workspace, role)
  }
  |> stream(request, context, line, _)
}

fn stream(
  request: request.Request(mist.Connection),
  context: Context,
  line: String,
  found: Result(#(String, access.Role), Int),
) -> response.Response(mist.ResponseData) {
  let empty = fn(status) {
    response.new(status) |> response.set_body(mist.Bytes(bytes_tree.new()))
  }
  case found {
    Error(status) -> empty(status)
    Ok(#(workspace, role)) ->
      case access.allows(role, access.Read) {
        True ->
          live.stream(request, context.hub, lines.channel(workspace, line))
        False -> empty(404)
      }
  }
}

fn role_of(
  request: request.Request(body),
  context: Context,
  caller: String,
  workspace: String,
  line: String,
) -> Result(access.Role, Nil) {
  access.role(
    context.accounts,
    caller,
    signed_in_email(identity_of(request, context, caller)),
    workspace,
    line,
  )
}

fn signed_in_email(identity: Identity) -> Option(String) {
  case identity {
    SignedIn(email:, ..) -> Some(email)
    SignedOut | NoEmail -> None
  }
}

/// Holds the built SPA in the image; absent in dev, where Vite serves it.
const static_directory = "static"

pub type Context {
  Context(
    hub: live.Hub,
    sso: Bool,
    accounts: String,
    invite: invitations.Invite,
  )
}

pub fn handle_request(
  request: wisp.Request,
  context: Context,
) -> wisp.Response {
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
    ["api", "s", owner, "lines", line, ..rest] ->
      look(request, context, owner, line, ["api", ..rest])
    segments -> {
      use workspace <- require_workspace(request, context)
      case segments {
        ["api", "holidays", "countries"] -> {
          use <- wisp.require_method(request, http.Get)
          holidays.countries(holidays.http_fetch, in: holidays.directory)
          |> holiday_response
        }
        ["api", "holidays", year, country] -> {
          use <- wisp.require_method(request, http.Get)
          case
            holidays.public_holidays(
              year,
              country,
              holidays.http_fetch,
              in: holidays.directory,
            )
          {
            Ok(answer) -> holiday_response(answer)
            Error(Nil) -> wisp.bad_request("expected /api/holidays/2026/FR")
          }
        }
        ["api", "account"] ->
          case request.method {
            http.Put -> save_account(request, context, workspace)
            _ -> {
              use <- wisp.require_method(request, http.Get)
              account_of(request, context, workspace)
            }
          }
        ["api", "invitations"] -> {
          use <- wisp.require_method(request, http.Post)
          create_invitation(request, context, workspace)
        }
        ["api", "workspaces"] -> {
          use <- wisp.require_method(request, http.Get)
          list_workspaces(request, context, workspace)
        }
        ["api", "lines"] ->
          case request.method {
            http.Post -> create_line(request, workspace)
            _ -> {
              use <- wisp.require_method(request, http.Get)
              list_lines(workspace, start_of(context))
            }
          }
        ["api", "lines", line, ..rest] ->
          in_line(request, context, workspace, workspace, line, ["api", ..rest])
        ["api", "w", owner, "lines", line, ..rest] ->
          case workspace.parse(owner) {
            Ok(owner) ->
              in_line(request, context, workspace, owner, line, ["api", ..rest])
            Error(Nil) -> wisp.not_found()
          }
        // Legacy routes of the first Line: scripts and SPAs open during a
        // deploy still call them.
        ["api", ..] ->
          in_line(request, context, workspace, workspace, lines.first, segments)
        _ -> wisp.not_found()
      }
    }
  }
}

/// `segments` is the path inside the Line, `["api", "demands"]` for
/// `/api/demands`, `/api/lines/<id>/demands` and
/// `/api/w/<owner>/lines/<id>/demands`.
fn in_line(
  request: wisp.Request,
  context: Context,
  caller: String,
  workspace: String,
  line: String,
  segments: List(String),
) -> wisp.Response {
  case role_of(request, context, caller, workspace, line) {
    Error(Nil) -> wisp.internal_server_error()
    // A Private Line does not show it exists (F48).
    Ok(access.NoRole) -> wisp.not_found()
    Ok(role) -> {
      use <- guard(request.method, segments, role)
      open_line(
        request,
        context,
        identity_of(request, context, caller),
        role,
        workspace,
        line,
        segments,
      )
    }
  }
}

/// The role table refuses a route missing from it, and one the role may not
/// use (F48).
fn guard(
  method: http.Method,
  segments: List(String),
  role: access.Role,
  next: fn() -> wisp.Response,
) -> wisp.Response {
  case access.need(method, segments) {
    Error(refusal) -> refused(refusal)
    Ok(need) ->
      case access.allows(role, need) {
        False -> wisp.response(403)
        True -> next()
      }
  }
}

/// The routes of one Line as `role`, behind the same guard as the API, with
/// no Workspace and no Account: the Simulation runs them in the browser, on
/// its own Line that lives only in the page (`sim/`).
pub fn simulate(
  request: wisp.Request,
  role: access.Role,
  database: String,
) -> wisp.Response {
  let segments = wisp.path_segments(request)
  use <- guard(request.method, segments, role)
  let act_as = access.actor(role, _, fn(_) { False })
  route(request, request.method, segments, database, None, act_as)
}

/// authentik lets `/api/s/` through with no sign-in, so the request has no
/// identity and none is read (F53).
fn look(
  request: wisp.Request,
  context: Context,
  owner: String,
  line: String,
  segments: List(String),
) -> wisp.Response {
  case workspace.parse(owner) {
    Error(Nil) -> wisp.not_found()
    Ok(workspace) ->
      case look_role(context, workspace, line) {
        Error(Nil) -> wisp.internal_server_error()
        Ok(access.NoRole) -> wisp.not_found()
        Ok(role) ->
          case access.need(request.method, segments) {
            Ok(access.Read) ->
              open_line(
                request,
                context,
                SignedOut,
                role,
                workspace,
                line,
                segments,
              )
            Ok(_) -> wisp.response(403)
            Error(refusal) -> refused(refusal)
          }
      }
  }
}

fn refused(refusal: access.Refusal) -> wisp.Response {
  case refusal {
    access.NoSuchRoute -> wisp.not_found()
    access.WrongMethod(allowed:) -> wisp.method_not_allowed(allowed:)
  }
}

fn look_role(
  context: Context,
  workspace: String,
  line: String,
) -> Result(access.Role, Nil) {
  case context.sso {
    False -> Ok(access.NoRole)
    True -> access.anyone(context.accounts, workspace, line)
  }
}

fn open_line(
  request: wisp.Request,
  context: Context,
  identity: Identity,
  role: access.Role,
  workspace: String,
  line: String,
  segments: List(String),
) -> wisp.Response {
  case lines.database(workspace, line, start_of(context)) {
    Error(lines.UnknownLine) -> wisp.not_found()
    Error(_) -> wisp.internal_server_error()
    Ok(database) -> {
      use <- announce_change(
        request,
        context.hub,
        lines.channel(workspace, line),
        segments,
      )
      let linking = case identity {
        SignedIn(..) -> Some(Linking(context.accounts, workspace, line))
        SignedOut | NoEmail -> None
      }
      let act_as = fn(wanted) {
        access.actor(role, wanted, access.linked_elsewhere(
          context.accounts,
          signed_in_email(identity),
          workspace,
          line,
          _,
        ))
      }
      case request.method, segments {
        http.Put, ["api"] -> rename_line(request, workspace, line)
        http.Get, ["api"] -> line_name(workspace, line)
        _, ["api", "sharing"] ->
          share_line(request, context, identity, workspace, line)
        method, _ -> route(request, method, segments, database, linking, act_as)
      }
    }
  }
}

/// The Team Member a flow action acts as, or `Error` when the Account may
/// not act as the one in the request (F50).
type ActAs =
  fn(Option(String)) -> Result(Option(String), Nil)

fn not_yours() -> wisp.Response {
  wisp.response(403)
  |> wisp.string_body(
    "You act only as your own Team Member; the owner acts for those with no Account.",
  )
}

/// Sharing lives in `accounts.db`, so it needs SSO on (F52).
fn share_line(
  request: wisp.Request,
  context: Context,
  identity: Identity,
  workspace: String,
  line: String,
) -> wisp.Response {
  case identity {
    SignedOut ->
      wisp.response(403)
      |> wisp.string_body("A Line is shared only with sign-in on.")
    NoEmail -> wisp.response(401)
    SignedIn(..) -> {
      use shared <- require_body(
        request,
        decode.field("shared", decode.bool, decode.success),
        or: "expected a body like {\"shared\": true}",
      )
      case accounts.share(context.accounts, workspace, line, shared) {
        Ok(Nil) -> send_json(json.object([#("shared", json.bool(shared))]), 200)
        Error(Nil) -> wisp.internal_server_error()
      }
    }
  }
}

/// How the caller's own first Line starts, when this request makes it: empty
/// with SSO on, where the Simulation shows the demo data; from the demo data
/// with SSO off, as in dev and in the smoke test.
fn start_of(context: Context) -> db.Start {
  case context.sso {
    True -> db.Empty
    False -> db.Demo
  }
}

/// Where the Team Member links of a Line live. Only a signed-in owner with
/// SSO on links anyone (F52).
type Linking {
  Linking(accounts: String, workspace: String, line: String)
}

type Identity {
  SignedOut
  NoEmail
  SignedIn(uid: String, email: String)
}

/// With SSO off any client sends any header, so nobody is signed in and no
/// Account is made (F52).
fn identity_of(
  request: request.Request(body),
  context: Context,
  workspace: String,
) -> Identity {
  case context.sso, workspace == workspace.anonymous {
    False, _ | True, True -> SignedOut
    True, False ->
      case accounts.email_of(request) {
        Ok(email) -> SignedIn(uid: workspace, email:)
        Error(Nil) -> NoEmail
      }
  }
}

fn account_of(
  request: wisp.Request,
  context: Context,
  workspace: String,
) -> wisp.Response {
  case identity_of(request, context, workspace) {
    SignedOut -> send_json(json.object([#("signedIn", json.bool(False))]), 200)
    NoEmail -> wisp.response(401)
    SignedIn(uid:, email:) ->
      case accounts.sign_in(context.accounts, uid, email) {
        Ok(Some(account)) -> {
          show_name_in_lines(context, account)
          account_response(request, account, named: True)
        }
        Ok(None) -> {
          let #(first_name, last_name) = accounts.suggested_name(request)
          accounts.Account(email:, first_name:, last_name:)
          |> account_response(request, _, named: False)
        }
        Error(Nil) -> wisp.internal_server_error()
      }
  }
}

fn save_account(
  request: wisp.Request,
  context: Context,
  workspace: String,
) -> wisp.Response {
  case identity_of(request, context, workspace) {
    SignedOut -> wisp.response(403)
    NoEmail -> wisp.response(401)
    SignedIn(uid:, email:) -> {
      let decoder = {
        use first_name <- decode.field("firstName", decode.string)
        use last_name <- decode.field("lastName", decode.string)
        decode.success(#(first_name, last_name))
      }
      use #(first_name, last_name) <- require_body(
        request,
        decoder,
        or: "expected a body like {\"firstName\": \"Ada\", \"lastName\": \"Lovelace\"}",
      )
      case accounts.save(context.accounts, uid, email, first_name, last_name) {
        Ok(account) -> {
          show_name_in_lines(context, account)
          account_response(request, account, named: True)
        }
        Error(accounts.EmptyName) ->
          wisp.bad_request("a first and a last name are needed")
        Error(accounts.NameTooLong) ->
          wisp.bad_request(
            "a name stays under "
            <> int.to_string(accounts.max_name_length)
            <> " characters",
          )
        Error(accounts.StoreFailed) -> wisp.internal_server_error()
      }
    }
  }
}

/// The link holds from the Account's next sign-in: each Team Member that
/// has its email, in any Line of any Workspace, shows its name (F47).
fn show_name_in_lines(context: Context, account: accounts.Account) -> Nil {
  let name = accounts.full_name(account)
  accounts.links_of(context.accounts, account.email)
  |> result.unwrap([])
  |> list.each(fn(link) {
    let #(workspace, line, team_member) = link
    let renamed =
      lines.database(workspace, line, db.Empty)
      |> result.replace_error(Nil)
      |> result.try(fn(database) {
        db.with_connection_at(
          database,
          design.name_linked(_, [
            #(team_member, name),
          ]),
        )
        |> result.replace_error(Nil)
      })
    case renamed {
      Ok(True) ->
        live.announce(context.hub, lines.channel(workspace, line), "design")
      _ -> Nil
    }
  })
}

/// Called only for a signed-in Account, so SSO is on and the username
/// header is trusted.
fn account_response(
  request: wisp.Request,
  account: accounts.Account,
  named named: Bool,
) -> wisp.Response {
  json.object([
    #("signedIn", json.bool(True)),
    #("named", json.bool(named)),
    #("admin", json.bool(invitations.is_admin(request))),
    #("email", json.string(account.email)),
    #("firstName", json.string(account.first_name)),
    #("lastName", json.string(account.last_name)),
  ])
  |> send_json(200)
}

fn create_invitation(
  request: wisp.Request,
  context: Context,
  workspace: String,
) -> wisp.Response {
  case identity_of(request, context, workspace) {
    SignedOut -> wisp.response(403)
    NoEmail -> wisp.response(401)
    SignedIn(..) ->
      case invitations.is_admin(request) {
        False -> wisp.response(403)
        True ->
          case context.invite() {
            Ok(invitation) ->
              json.object([
                #("link", json.string(invitation.link)),
                #("expires", json.string(invitation.expires)),
              ])
              |> send_json(201)
            Error(invitations.NoToken) ->
              wisp.response(503)
              |> wisp.string_body(
                "AUTHENTIK_TOKEN is not set, so Bluebin cannot call authentik",
              )
            Error(invitations.Refused(status)) ->
              wisp.response(502)
              |> wisp.string_body(
                "authentik refused the invitation ("
                <> int.to_string(status)
                <> ")",
              )
            Error(_) ->
              wisp.response(502) |> wisp.string_body("authentik did not answer")
          }
      }
  }
}

/// Every Line the Account can open, by Workspace, its own first (F46).
fn list_workspaces(
  request: wisp.Request,
  context: Context,
  caller: String,
) -> wisp.Response {
  let email = signed_in_email(identity_of(request, context, caller))
  case access.workspaces(context.accounts, caller, email, start_of(context)) {
    Ok(workspaces) -> send_json(json.array(workspaces, workspace_json), 200)
    Error(Nil) -> wisp.internal_server_error()
  }
}

fn workspace_json(workspace: access.OpenWorkspace) -> json.Json {
  json.object([
    #("owner", json.string(workspace.owner)),
    #("name", json.nullable(workspace.name, json.string)),
    #("own", json.bool(workspace.own)),
    #("lines", json.array(workspace.lines, open_line_json)),
  ])
}

fn open_line_json(open: access.OpenLine) -> json.Json {
  let role = case open.role {
    access.Member(_) -> "member"
    access.Viewer -> "viewer"
    access.Owner | access.NoRole -> "owner"
  }
  json.object([
    #("id", json.string(open.line.id)),
    #("name", json.string(open.line.name)),
    #("shared", json.bool(open.shared)),
    #("role", json.string(role)),
    #("teamMember", json.nullable(open.team_member, json.string)),
  ])
}

fn list_lines(workspace: String, start: db.Start) -> wisp.Response {
  case lines.list(workspace, start) {
    Ok(found) -> send_json(json.array(found, line_json), 200)
    Error(_) -> wisp.internal_server_error()
  }
}

fn create_line(request: wisp.Request, workspace: String) -> wisp.Response {
  use name <- require_line_name(request)
  line_response(lines.create(workspace, name), 201)
}

fn line_name(workspace: String, line: String) -> wisp.Response {
  case lines.list(workspace, db.Empty) {
    Error(_) -> wisp.internal_server_error()
    Ok(found) ->
      case list.find(found, fn(one) { one.id == line }) {
        Ok(found) -> send_json(line_json(found), 200)
        Error(Nil) -> wisp.not_found()
      }
  }
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
  require_body(
    request,
    decode.field("name", decode.string, decode.success),
    or: "expected a body like {\"name\": \"Mobile\"}",
    then: next,
  )
}

fn line_response(
  result: Result(lines.Line, lines.LineError),
  status: Int,
) -> wisp.Response {
  case result {
    Ok(line) -> send_json(line_json(line), status)
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
  context: Context,
  next: fn(String) -> wisp.Response,
) -> wisp.Response {
  case caller_of(request, context) {
    Ok(workspace) -> next(workspace)
    Error(Nil) -> wisp.response(401)
  }
}

/// The caller's own Workspace. With SSO on, forward auth sets the uid on
/// every request it lets through signed in; one with no uid came through a
/// path authentik does not guard (`/api/s/`, a crafted `..`), so it gets
/// nothing, and never the `anonymous` Workspace.
fn caller_of(
  request: request.Request(body),
  context: Context,
) -> Result(String, Nil) {
  case workspace.from_request(request) {
    Ok(caller) if context.sso && caller == workspace.anonymous -> Error(Nil)
    found -> found
  }
}

/// `access.need` already refused every path and method missing here.
fn route(
  request: wisp.Request,
  method: http.Method,
  segments: List(String),
  database: String,
  linking: Option(Linking),
  act_as: ActAs,
) -> wisp.Response {
  case method, segments {
    http.Post, ["api", "demands"] -> create_demand(request, database)
    _, ["api", "demands"] -> demands(database)
    _, ["api", "demands", id, "code"] -> change_code(request, database, id)
    _, ["api", "line"] -> line_view(database)
    _, ["api", "backlog"] -> backlog(database)
    _, ["api", "backlog", "urgent"] -> make_urgent(request, database)
    _, ["api", "pull"] -> pull(request, database, act_as)
    _, ["api", "finish"] -> finish(request, database)
    _, ["api", "deploy"] -> deploy(request, database)
    _, ["api", "release"] -> release(request, database)
    _, ["api", "rework"] -> raise_rework(request, database)
    _, ["api", "rework", "repair"] -> repair_rework(request, database)
    _, ["api", "help"] -> help_the_rework(request, database, act_as)
    _, ["api", "help", "stop"] -> stop_helping(request, database, act_as)
    _, ["api", "andons"] -> andons(database)
    _, ["api", "andon"] -> raise_andon(request, database, act_as)
    _, ["api", "andon", "close"] -> close_andon(request, database, act_as)
    _, ["api", "assign"] -> assign(request, database, act_as)
    http.Post, ["api", "team-members"] -> add_team_member(request, database)
    _, ["api", "team-members"] -> team_members(database)
    http.Put, ["api", "design"] -> save_design(request, database, linking)
    _, ["api", "design"] -> design_of(database, linking)
    _, ["api", "labels"] -> labels(database)
    _, ["api", "team-members", team_member, "next"] ->
      next_thing(team_member, database)
    _, ["api", "steps", position] -> rename_step(request, position, database)
    _, ["api", "measures"] -> measures_of(request, database)
    http.Put, ["api", "calendar"] -> save_calendar(request, database)
    _, ["api", "calendar"] -> working_calendar(database)
    _, _ -> wisp.not_found()
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
    Ok(found) -> send_json(measures.to_json(found), 200)
    Error(measures.InvalidPeriod) ->
      wisp.bad_request(
        "expected ?from=2026-10-30&to=2026-11-05, with from on or before to",
      )
    Error(measures.StoreFailed) -> wisp.internal_server_error()
  }
}

fn holiday_response(answer: Result(String, holidays.Failure)) -> wisp.Response {
  case answer {
    Ok(body) ->
      wisp.json_response(body, 200)
      |> wisp.set_header("cache-control", "private, max-age=86400")
    Error(holidays.Refused(404)) -> wisp.not_found()
    Error(_) ->
      wisp.response(502)
      |> wisp.string_body("the public holiday service did not answer")
  }
}

fn working_calendar(database: String) -> wisp.Response {
  use connection <- read(database)
  calendar.load(connection) |> result.map(calendar.to_json)
}

fn save_calendar(request: wisp.Request, database: String) -> wisp.Response {
  use wanted <- require_body(
    request,
    calendar.decoder(),
    or: "expected a body like {\"days\": [1, 2, 3, 4, 5], \"start\": \"09:00\", \"end\": \"16:00\", \"holidays\": [{\"day\": \"2026-12-25\", \"label\": \"Christmas\"}]}",
  )
  case
    db.with_connection_at(database, fn(connection) {
      use _ <- result.try(calendar.save(connection, wanted))
      calendar.load(connection)
      |> result.replace_error(calendar.StoreFailed)
    })
  {
    Ok(saved) -> send_json(calendar.to_json(saved), 200)
    Error(calendar.Invalid(message)) -> wisp.bad_request(message)
    Error(calendar.StoreFailed) -> wisp.internal_server_error()
  }
}

fn design_of(database: String, linking: Option(Linking)) -> wisp.Response {
  case db.with_connection_at(database, design_json), links_of(linking) {
    Ok(to_json), Ok(links) -> send_json(to_json(links), 200)
    _, _ -> wisp.internal_server_error()
  }
}

/// The Design with the Takt Time of the Line and the suggested Blue Bins
/// (F55), waiting for the Account links.
fn design_json(
  connection: sqlight.Connection,
) -> Result(fn(List(accounts.Link)) -> json.Json, Nil) {
  use #(found, held) <- result.try(design.load(connection))
  use demands <- result.try(
    demand.list_active(connection) |> result.replace_error(Nil),
  )
  let takt = demand.line_takt_hours(demands)
  use suggestions <- result.try(
    measures.suggestions(connection, takt) |> result.replace_error(Nil),
  )
  Ok(fn(links) { design.to_json(found, held, links, takt, suggestions) })
}

fn links_of(linking: Option(Linking)) -> Result(List(accounts.Link), Nil) {
  case linking {
    None -> Ok([])
    Some(linking) ->
      accounts.links(linking.accounts, linking.workspace, linking.line)
  }
}

fn save_design(
  request: wisp.Request,
  database: String,
  linking: Option(Linking),
) -> wisp.Response {
  let decoder = {
    use wanted <- decode.then(design.decoder())
    use emails <- decode.then(accounts.emails_decoder())
    decode.success(#(wanted, emails))
  }
  use #(wanted, emails) <- require_body(
    request,
    decoder,
    or: "expected the body of GET /api/design: {\"labels\", \"teamMembers\", \"steps\"}",
  )
  case accounts.check_emails(emails) {
    Error(reason) -> wisp.bad_request(reason)
    Ok(emails) -> save_design_and_links(database, linking, wanted, emails)
  }
}

/// The links live outside the Line file (ADR-0004), so they are saved after
/// the Line's own transaction.
fn save_design_and_links(
  database: String,
  linking: Option(Linking),
  wanted: design.Design,
  emails: List(#(String, String)),
) -> wisp.Response {
  let saved =
    db.with_connection_at(database, fn(connection) {
      design.save(connection, wanted)
    })
  case saved {
    Error(design.Invalid(reason)) -> wisp.bad_request(reason)
    Error(design.StoreFailed) -> wisp.internal_server_error()
    Ok(saved) -> {
      let kept =
        list.map(saved.team_members, fn(team_member) { team_member.id })
      let linked = case linking {
        None -> Ok(Nil)
        Some(linking) ->
          accounts.save_links(
            linking.accounts,
            linking.workspace,
            linking.line,
            wanted: emails,
            kept:,
          )
      }
      case linked {
        Error(accounts.EmailTaken(email)) ->
          wisp.bad_request(accounts.email_taken(email))
        Error(accounts.LinkStoreFailed) -> wisp.internal_server_error()
        Ok(Nil) ->
          case
            links_of(linking)
            |> result.try(fn(links) {
              db.with_connection_at(database, fn(connection) {
                use _ <- result.try(
                  design.name_linked(connection, linked_names(links))
                  |> result.replace_error(Nil),
                )
                design_json(connection)
              })
              |> result.map(fn(to_json) { to_json(links) })
            })
          {
            Ok(found) -> send_json(found, 200)
            Error(Nil) -> wisp.internal_server_error()
          }
      }
    }
  }
}

fn linked_names(links: List(accounts.Link)) -> List(#(String, String)) {
  list.filter_map(links, fn(link) {
    option.to_result(link.account, Nil)
    |> result.map(fn(account) {
      #(link.team_member, accounts.full_name(account))
    })
  })
}

fn add_team_member(request: wisp.Request, database: String) -> wisp.Response {
  use name <- require_body(
    request,
    decode.field("name", decode.string, decode.success),
    or: "expected a body like {\"name\": \"Inès\"}",
  )
  case
    db.with_connection_at(database, fn(connection) {
      design.add_team_member(connection, name)
    })
  {
    Ok(team_member) ->
      json.object([
        #("id", json.string(team_member.id)),
        #("name", json.string(team_member.name)),
      ])
      |> send_json(201)
    Error(design.Invalid(reason)) -> wisp.bad_request(reason)
    Error(design.StoreFailed) -> wisp.internal_server_error()
  }
}

fn labels(database: String) -> wisp.Response {
  use connection <- read(database)
  design.load_labels(connection) |> result.map(design.labels_json)
}

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
      use now <- result.try(db.now(connection))
      Ok(demand.to_json(demands, calendar, now / 86_400))
    })

  case result {
    Ok(body) -> wisp.json_response(body, 200)
    Error(_) -> wisp.internal_server_error()
  }
}

fn create_demand(request: wisp.Request, database: String) -> wisp.Response {
  let decoder = {
    use label <- decode.field("label", decode.string)
    use client <- decode.field("client", decode.string)
    use due_on <- decode.field("dueOn", decode.string)
    use pieces <- decode.field("pieces", decode.int)
    use code <- decode.optional_field(
      "code",
      None,
      decode.optional(decode.string),
    )
    decode.success(#(label, client, due_on, pieces, code))
  }
  use #(label, client, due_on, pieces, code) <- require_body(
    request,
    decoder,
    or: "expected a body like {\"label\": \"Checkout redesign\", \"client\": \"Retail\", \"dueOn\": \"2026-12-31\", \"pieces\": 8}",
  )
  case
    db.with_connection_at(database, fn(connection) {
      demand.create(connection, label, client, due_on, pieces, code)
    })
  {
    Ok(id) -> send_json(json.object([#("id", json.string(id))]), 201)
    Error(demand.Invalid(reason)) -> wisp.bad_request(reason)
    Error(demand.StoreFailed) -> wisp.internal_server_error()
  }
}

fn change_code(
  request: wisp.Request,
  database: String,
  id: String,
) -> wisp.Response {
  use code <- require_body(
    request,
    decode.at(["code"], decode.string),
    or: "expected a body like {\"code\": \"CHK\"}",
  )
  case
    db.with_connection_at(database, fn(connection) {
      demand.change_code(connection, id, code)
    })
  {
    Ok(Nil) -> wisp.no_content()
    Error(demand.Invalid(reason)) -> wisp.bad_request(reason)
    Error(demand.StoreFailed) -> wisp.internal_server_error()
  }
}

fn line_view(database: String) -> wisp.Response {
  use connection <- read(database)
  use stations <- result.try(line.load(connection))
  use steps <- result.try(line.list_steps(connection))
  use demands <- result.try(demand.list_active(connection))
  use calendar <- result.try(calendar.load(connection))
  use now <- result.try(db.now(connection))
  use andons <- result.try(andon.andons(connection, calendar, now))
  use #(stale, active) <- result.try(andon.stale(connection, calendar, now))
  let takt = demand.line_takt_hours(demands)
  use bottlenecks <- result.try(andon.bottlenecks(connection, takt))
  use held <- result.try(flow.held_for_release(connection))
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
      #("heldForRelease", flow.held_for_release_json(held)),
    ]),
  )
}

fn andons(database: String) -> wisp.Response {
  use connection <- read(database)
  andon.current(connection) |> result.map(andon.andons_json)
}

fn raise_andon(
  request: wisp.Request,
  database: String,
  act_as: ActAs,
) -> wisp.Response {
  let decoder = {
    use station <- decode.field("station", decode.string)
    use team_member <- decode.optional_field(
      "teamMember",
      None,
      decode.optional(decode.string),
    )
    decode.success(#(station, team_member))
  }
  use #(station, team_member) <- require_body(
    request,
    decoder,
    or: "expected a body like {\"station\": \"ws-web\"}",
  )
  case act_as(team_member) {
    Error(Nil) -> not_yours()
    Ok(team_member) ->
      andon_response(
        db.with_connection_at(database, fn(connection) {
          flow.raise_andon(connection, station, team_member)
        }),
      )
  }
}

fn close_andon(
  request: wisp.Request,
  database: String,
  act_as: ActAs,
) -> wisp.Response {
  let decoder = {
    use station <- decode.field("station", decode.string)
    use team_member <- decode.field("teamMember", decode.string)
    decode.success(#(station, team_member))
  }
  use #(station, team_member) <- require_body(
    request,
    decoder,
    or: "expected a body like {\"station\": \"ws-web\", \"teamMember\": \"pe-bob\"}",
  )
  case act_as(Some(team_member)) {
    Ok(Some(team_member)) ->
      andon_response(
        db.with_connection_at(database, fn(connection) {
          flow.close_andon(connection, station, team_member)
        }),
      )
    _ -> not_yours()
  }
}

fn andon_response(result: Result(Nil, flow.FlowError)) -> wisp.Response {
  case result {
    Ok(Nil) -> wisp.no_content()
    Error(failure) -> flow_failure(failure)
  }
}

fn backlog(database: String) -> wisp.Response {
  use connection <- read(database)
  use backlog <- result.try(heijunka.load(connection))
  use mix <- result.try(heijunka.product_mix(connection, backlog.demands))
  Ok(heijunka.to_json(backlog, mix))
}

fn make_urgent(request: wisp.Request, database: String) -> wisp.Response {
  let decoder = {
    use piece <- decode.field("piece", decode.string)
    use reason <- decode.optional_field(
      "reason",
      None,
      decode.optional(decode.string),
    )
    decode.success(#(piece, reason))
  }
  use #(piece, reason) <- require_body(
    request,
    decoder,
    or: "expected a body like {\"piece\": \"p-billing-3\"}",
  )
  flow_response(
    db.with_connection_at(database, fn(connection) {
      flow.make_urgent(connection, piece, reason)
    }),
  )
}

fn pull(
  request: wisp.Request,
  database: String,
  act_as: ActAs,
) -> wisp.Response {
  let decoder = {
    use station <- decode.field("station", decode.string)
    use team_member <- decode.optional_field(
      "teamMember",
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
  use #(station, team_member, reason) <- require_body(
    request,
    decoder,
    or: "expected a body like {\"station\": \"ws-web\"}",
  )
  case act_as(team_member) {
    Error(Nil) -> not_yours()
    Ok(team_member) ->
      flow_response(
        db.with_connection_at(database, fn(connection) {
          flow.pull(connection, station, team_member, reason)
        }),
      )
  }
}

fn finish(request: wisp.Request, database: String) -> wisp.Response {
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
  use #(station, piece, reason) <- require_body(
    request,
    decoder,
    or: "expected a body like {\"station\": \"ws-web\", \"piece\": \"p-checkout-8\"}",
  )
  flow_response(
    db.with_connection_at(database, fn(connection) {
      flow.finish(connection, station, piece, reason)
    }),
  )
}

fn deploy(request: wisp.Request, database: String) -> wisp.Response {
  use #(piece, hold) <- require_body(
    request,
    {
      use piece <- decode.field("piece", decode.string)
      use hold <- decode.optional_field("hold", False, decode.bool)
      decode.success(#(piece, hold))
    },
    or: "expected a body like {\"piece\": \"p-checkout-9\", \"hold\": false}",
  )
  flow_response(
    db.with_connection_at(database, fn(connection) {
      flow.deploy(connection, piece, hold:)
    }),
  )
}

fn release(request: wisp.Request, database: String) -> wisp.Response {
  use pieces <- require_body(
    request,
    decode.field("pieces", decode.list(decode.string), decode.success),
    or: "expected a body like {\"pieces\": [\"p-checkout-9\"]}",
  )
  case
    db.with_connection_at(database, fn(connection) {
      flow.release(connection, pieces)
    })
  {
    Ok(released) ->
      json.object([#("released", json.int(released))]) |> send_json(200)
    Error(failure) -> flow_failure(failure)
  }
}

fn flow_response(result: Result(flow.Flowed, flow.FlowError)) -> wisp.Response {
  case result {
    Ok(flowed) ->
      json.object([
        #("piece", json.string(flowed.piece)),
        #("demand", json.string(flowed.demand)),
        #(
          "deviations",
          json.array(flowed.deviations, fn(rule) {
            json.string(flow.rule_name(rule))
          }),
        ),
        #("kanbansSentTo", json.array(flowed.kanbans_sent_to, json.string)),
      ])
      |> send_json(200)
    Error(failure) -> flow_failure(failure)
  }
}

fn flow_failure(failure: flow.FlowError) -> wisp.Response {
  case failure {
    flow.NeedsConfirmation(rules) ->
      json.object([
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
      ])
      |> send_json(409)
    flow.ReorderNeedsConfirmation(effects) ->
      json.object([
        #("confirm", json.string(flow.rule_name(flow.ReorderHeijunkaSequence))),
        #(
          "message",
          json.string(flow.rule_warning(flow.ReorderHeijunkaSequence)),
        ),
        #("effects", heijunka.effects_json(effects)),
      ])
      |> send_json(409)
    flow.NothingToPull ->
      conflict(
        "nothing_to_pull",
        "No Piece waits upstream of this Work Station, so there is nothing to pull.",
      )
    flow.NothingToAssemble ->
      conflict(
        "nothing_to_assemble",
        "No Piece has every Sub-Piece waiting in the last Blue Bin of its Branch, so there is nothing to assemble.",
      )
    flow.PieceNotHere ->
      conflict(
        "piece_not_here",
        "This Piece is no longer where the action expects it.",
      )
    flow.NotUpstream ->
      conflict(
        "not_upstream",
        "A Piece never moves backward: the defect belongs to a Work Station it already crossed.",
      )
    flow.UnknownRework ->
      conflict("unknown_rework", "This Rework is already repaired.")
    flow.ReworkFirst ->
      conflict(
        "rework_first",
        "This Team Member repairs a Rework first. Repair it, or hand it to another Team Member of the Work Station, before pulling a new Piece.",
      )
    flow.NotOfStation ->
      conflict(
        "not_of_station",
        "An Assignment goes only to a Team Member of the same Work Station.",
      )
    flow.NotNextOfDemand ->
      conflict(
        "not_next_of_demand",
        "Inside one Demand, Pieces leave the Backlog first-in, first-out. Only the next Piece of this Demand can be made urgent.",
      )
    flow.NoAndon -> conflict("no_andon", "No Andon stops this Work Station.")
    flow.NotTeamLeader ->
      conflict(
        "not_team_leader",
        "Only the Team Leader of the Work Station closes its Andon.",
      )
    flow.NobodyRepairs ->
      conflict(
        "nobody_repairs",
        "Nobody repairs this Rework yet. Help it once a Team Member of the Work Station that made the defect takes it.",
      )
    flow.NotOfReworkStations ->
      conflict(
        "not_of_rework_stations",
        "Only the Team Members of the Work Station that found the defect, or of the one that made it, help this Rework.",
      )
    flow.RepairsItAlready ->
      conflict("repairs_it_already", "This Team Member repairs this Rework.")
    flow.HelpsAnotherPiece ->
      conflict(
        "helps_another_piece",
        "This Team Member already helps another Piece. Stop helping it first.",
      )
    flow.NotHelping ->
      conflict("not_helping", "This Team Member helps no Piece.")
    flow.EmptyDescription ->
      wisp.bad_request("a Rework says in one line what the defect is")
    flow.UnknownStation -> wisp.not_found()
    flow.StoreFailed -> wisp.internal_server_error()
  }
}

/// A flow action the state of the Line refuses: the SPA shows `message`.
fn conflict(code: String, message: String) -> wisp.Response {
  json.object([
    #("error", json.string(code)),
    #("message", json.string(message)),
  ])
  |> send_json(409)
}

fn raise_rework(request: wisp.Request, database: String) -> wisp.Response {
  let decoder = {
    use station <- decode.field("station", decode.string)
    use piece <- decode.field("piece", decode.string)
    use made_by <- decode.field("madeBy", decode.string)
    use description <- decode.field("description", decode.string)
    decode.success(#(station, piece, made_by, description))
  }
  use #(station, piece, made_by, description) <- require_body(
    request,
    decoder,
    or: "expected a body like {\"station\": \"ws-qa-ios\", \"piece\": \"p-offline-4-ios\", \"madeBy\": \"ws-ios\", \"description\": \"…\"}",
  )
  case
    db.with_connection_at(database, fn(connection) {
      flow.raise_rework(connection, station, piece, made_by, description)
    })
  {
    Ok(raised) ->
      json.object([
        #("id", json.string(raised.id)),
        #("piece", json.string(raised.piece)),
        #("demand", json.string(raised.demand)),
        #("assignee", json.nullable(raised.assignee, json.string)),
        #("paused", json.nullable(raised.paused, json.string)),
      ])
      |> send_json(200)
    Error(failure) -> flow_failure(failure)
  }
}

fn repair_rework(request: wisp.Request, database: String) -> wisp.Response {
  use rework <- require_body(
    request,
    decode.field("rework", decode.string, decode.success),
    or: "expected a body like {\"rework\": \"rw-1\"}",
  )
  case
    db.with_connection_at(database, fn(connection) {
      flow.repair_rework(connection, rework)
    })
  {
    Ok(repaired) ->
      json.object([
        #("piece", json.string(repaired.piece)),
        #("resumed", json.nullable(repaired.resumed, json.string)),
      ])
      |> send_json(200)
    Error(failure) -> flow_failure(failure)
  }
}

fn help_the_rework(
  request: wisp.Request,
  database: String,
  act_as: ActAs,
) -> wisp.Response {
  let decoder = {
    use rework <- decode.field("rework", decode.string)
    use team_member <- decode.optional_field(
      "teamMember",
      None,
      decode.optional(decode.string),
    )
    decode.success(#(rework, team_member))
  }
  use #(rework, team_member) <- require_body(
    request,
    decoder,
    or: "expected a body like {\"rework\": \"rw-1\", \"teamMember\": \"pe-yasmine\"}",
  )
  use team_member <- acting(act_as, team_member)
  case
    db.with_connection_at(database, fn(connection) {
      flow.help_the_rework(connection, rework, team_member)
    })
  {
    Ok(helped) ->
      json.object([
        #("piece", json.string(helped.piece)),
        #("assignee", json.string(helped.assignee)),
        #("paused", json.array(helped.paused, json.string)),
      ])
      |> send_json(200)
    Error(failure) -> flow_failure(failure)
  }
}

fn stop_helping(
  request: wisp.Request,
  database: String,
  act_as: ActAs,
) -> wisp.Response {
  use team_member <- require_body(
    request,
    decode.optional_field(
      "teamMember",
      None,
      decode.optional(decode.string),
      decode.success,
    ),
    or: "expected a body like {\"teamMember\": \"pe-yasmine\"}",
  )
  use team_member <- acting(act_as, team_member)
  case
    db.with_connection_at(database, fn(connection) {
      flow.stop_helping(connection, team_member)
    })
  {
    Ok(stopped) ->
      json.object([
        #("piece", json.string(stopped.piece)),
        #("resumed", json.nullable(stopped.resumed, json.string)),
      ])
      |> send_json(200)
    Error(failure) -> flow_failure(failure)
  }
}

/// The Team Member an action acts as (F50); the owner must name one.
fn acting(
  act_as: ActAs,
  wanted: Option(String),
  run: fn(String) -> wisp.Response,
) -> wisp.Response {
  case act_as(wanted) {
    Ok(Some(team_member)) -> run(team_member)
    Ok(None) -> wisp.bad_request("name the Team Member who helps")
    Error(Nil) -> not_yours()
  }
}

fn team_members(database: String) -> wisp.Response {
  use connection <- read(database)
  assignment.team_members(connection)
  |> result.map(assignment.team_members_json)
}

fn next_thing(team_member: String, database: String) -> wisp.Response {
  case
    db.with_connection_at(database, fn(connection) {
      use view <- result.try(assignment.load(connection, team_member))
      use andons <- result.try(
        andon.current(connection)
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
    Ok(body) -> send_json(body, 200)
    Error(assignment.UnknownTeamMember) -> wisp.not_found()
    Error(assignment.ReadFailed) -> wisp.internal_server_error()
  }
}

fn assign(
  request: wisp.Request,
  database: String,
  act_as: ActAs,
) -> wisp.Response {
  let decoder = {
    use kind <- decode.field("kind", decode.string)
    use id <- decode.field("id", decode.string)
    use team_member <- decode.field("teamMember", decode.string)
    case kind {
      "piece" -> decode.success(#(flow.PieceAssignment, id, team_member))
      "rework" -> decode.success(#(flow.ReworkAssignment, id, team_member))
      _ -> decode.failure(#(flow.PieceAssignment, id, team_member), "kind")
    }
  }
  use #(kind, id, team_member) <- require_body(
    request,
    decoder,
    or: "expected a body like {\"kind\": \"piece\", \"id\": \"p-checkout-8-web\", \"teamMember\": \"pe-lila\"}",
  )
  case act_as(Some(team_member)) {
    Ok(Some(team_member)) -> reassign(database, kind, id, team_member)
    _ -> not_yours()
  }
}

fn reassign(
  database: String,
  kind: flow.AssignmentKind,
  id: String,
  team_member: String,
) -> wisp.Response {
  case
    db.with_connection_at(database, fn(connection) {
      flow.reassign(connection, kind, id, team_member)
    })
  {
    Ok(reassigned) ->
      json.object([
        #("piece", json.string(reassigned.piece)),
        #("teamMember", json.string(reassigned.team_member)),
      ])
      |> send_json(200)
    Error(failure) -> flow_failure(failure)
  }
}

fn rename_step(
  request: wisp.Request,
  position: String,
  database: String,
) -> wisp.Response {
  let decoder = {
    use name <- decode.field("name", decode.string)
    case int.parse(position) {
      Ok(position) -> decode.success(#(position, name))
      Error(Nil) -> decode.failure(#(0, name), "position")
    }
  }
  use #(position, name) <- require_body(
    request,
    decoder,
    or: "expected a body like {\"name\": \"Build\"}",
  )
  case
    db.with_connection_at(database, fn(connection) {
      line.rename_step(connection, position, name)
    })
  {
    Ok(step) ->
      json.object([
        #("position", json.int(step.position)),
        #("name", json.string(step.name)),
      ])
      |> send_json(200)
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

/// The JSON body decoded, or `400` with `message`.
fn require_body(
  request: wisp.Request,
  decoder: decode.Decoder(a),
  or message: String,
  then next: fn(a) -> wisp.Response,
) -> wisp.Response {
  use body <- wisp.require_json(request)
  case decode.run(body, decoder) {
    Ok(decoded) -> next(decoded)
    Error(_) -> wisp.bad_request(message)
  }
}

/// A read of the Line: its JSON, or `500` when the store fails.
fn read(
  database: String,
  load: fn(sqlight.Connection) -> Result(json.Json, error),
) -> wisp.Response {
  case db.with_connection_at(database, load) {
    Ok(found) -> send_json(found, 200)
    Error(_) -> wisp.internal_server_error()
  }
}

fn send_json(body: json.Json, status: Int) -> wisp.Response {
  wisp.json_response(json.to_string(body), status)
}
