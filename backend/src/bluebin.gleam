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
              list_lines(workspace)
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
    Ok(role) ->
      case access.need(request.method, segments) {
        Error(Nil) -> wisp.response(403)
        Ok(need) ->
          case access.allows(role, need) {
            False -> wisp.response(403)
            True ->
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
            _ -> wisp.response(403)
          }
      }
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
  case lines.database(workspace, line) {
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
        access.actor(role, wanted, linked_elsewhere(
          context,
          identity,
          workspace,
          line,
          _,
        ))
      }
      case segments {
        ["api"] ->
          case request.method {
            http.Put -> rename_line(request, workspace, line)
            _ -> {
              use <- wisp.require_method(request, http.Get)
              line_name(workspace, line)
            }
          }
        ["api", "sharing"] ->
          share_line(request, context, identity, workspace, line)
        _ -> route(request, segments, database, linking, act_as)
      }
    }
  }
}

/// The Team Member a flow action acts as, or `Error` when the Account may
/// not act as the one in the request (F50).
type ActAs =
  fn(Option(String)) -> Result(Option(String), Nil)

/// A Team Member linked to another Account acts only through that Account (R7).
fn linked_elsewhere(
  context: Context,
  identity: Identity,
  workspace: String,
  line: String,
  team_member: String,
) -> Bool {
  case identity {
    SignedOut | NoEmail -> False
    SignedIn(email:, ..) ->
      case accounts.links(context.accounts, workspace, line) {
        Error(Nil) -> True
        Ok(links) ->
          list.any(links, fn(link) {
            case link.team_member == team_member, link.account {
              True, Some(account) ->
                string.lowercase(account.email) != string.lowercase(email)
              _, _ -> False
            }
          })
      }
  }
}

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
    SignedOut | NoEmail ->
      wisp.response(403)
      |> wisp.string_body("A Line is shared only with sign-in on.")
    SignedIn(..) -> {
      use body <- wisp.require_json(request)
      case
        decode.run(body, decode.field("shared", decode.bool, decode.success))
      {
        Error(_) -> wisp.bad_request("expected a body like {\"shared\": true}")
        Ok(shared) ->
          case accounts.share(context.accounts, workspace, line, shared) {
            Ok(Nil) -> json_body([#("shared", json.bool(shared))], 200)
            Error(Nil) -> wisp.internal_server_error()
          }
      }
    }
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
  case context.sso, workspace == workspace.public {
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
    SignedOut ->
      json.object([#("signedIn", json.bool(False))])
      |> json.to_string
      |> wisp.json_response(200)
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
      use body <- wisp.require_json(request)
      let decoder = {
        use first_name <- decode.field("firstName", decode.string)
        use last_name <- decode.field("lastName", decode.string)
        decode.success(#(first_name, last_name))
      }
      case decode.run(body, decoder) {
        Error(_) ->
          wisp.bad_request(
            "expected a body like {\"firstName\": \"Ada\", \"lastName\": \"Lovelace\"}",
          )
        Ok(#(first_name, last_name)) ->
          case
            accounts.save(context.accounts, uid, email, first_name, last_name)
          {
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
      lines.database(workspace, line)
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
  |> json.to_string
  |> wisp.json_response(200)
}

fn create_invitation(
  request: wisp.Request,
  context: Context,
  workspace: String,
) -> wisp.Response {
  case identity_of(request, context, workspace) {
    SignedOut | NoEmail -> wisp.response(403)
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
              |> json.to_string
              |> wisp.json_response(201)
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
/// With SSO off only its own Workspace opens (F52).
fn list_workspaces(
  request: wisp.Request,
  context: Context,
  caller: String,
) -> wisp.Response {
  let identity = identity_of(request, context, caller)
  let shared = fn(workspace, line) {
    case identity {
      SignedIn(..) -> accounts.is_shared(context.accounts, workspace, line)
      SignedOut | NoEmail -> Ok(False)
    }
  }
  let found = {
    // The owner can be a Team Member of their own Lines too (F45).
    use held <- result.try(case identity {
      SignedIn(email:, ..) -> access.live_links(context.accounts, email, caller)
      SignedOut | NoEmail -> Ok([])
    })
    use own <- result.try(lines.list(caller) |> result.replace_error(Nil))
    use own <- result.try(
      list.try_map(own, fn(line) {
        use shared <- result.map(shared(caller, line.id))
        line_entry_json(
          line,
          shared,
          access.Owner,
          list.key_find(held, line.id) |> option.from_result,
        )
      }),
    )
    use name <- result.try(case identity {
      SignedIn(..) -> accounts.name_of_uid(context.accounts, caller)
      SignedOut | NoEmail -> Ok(None)
    })
    use others <- result.map(case identity {
      SignedIn(email:, ..) -> other_workspaces(context, caller, email)
      SignedOut | NoEmail -> Ok([])
    })
    [workspace_json(caller, name, True, own), ..others]
  }
  case found {
    Ok(workspaces) ->
      wisp.json_response(
        json.to_string(json.preprocessed_array(workspaces)),
        200,
      )
    Error(Nil) -> wisp.internal_server_error()
  }
}

/// The Workspaces where `email` is a Team Member: its Lines there, and the
/// Shared Lines of those Workspaces.
fn other_workspaces(
  context: Context,
  caller: String,
  email: String,
) -> Result(List(json.Json), Nil) {
  use links <- result.try(accounts.links_of(context.accounts, email))
  let workspaces =
    list.map(links, fn(link) { link.0 })
    |> list.unique
    |> list.filter(fn(workspace) { workspace != caller })
  use found <- result.map(
    list.try_map(workspaces, fn(workspace) {
      use held <- result.try(access.live_links(
        context.accounts,
        email,
        workspace,
      ))
      case held {
        [] -> Ok(None)
        _ -> {
          use all <- result.try(
            lines.list(workspace) |> result.replace_error(Nil),
          )
          use entries <- result.try(
            list.try_map(all, fn(line) {
              use shared <- result.map(accounts.is_shared(
                context.accounts,
                workspace,
                line.id,
              ))
              case list.key_find(held, line.id), shared {
                Ok(team_member), _ ->
                  Some(line_entry_json(
                    line,
                    shared,
                    access.Member(team_member),
                    Some(team_member),
                  ))
                Error(Nil), True ->
                  Some(line_entry_json(line, shared, access.Viewer, None))
                Error(Nil), False -> None
              }
            }),
          )
          use name <- result.map(accounts.name_of_uid(
            context.accounts,
            workspace,
          ))
          Some(#(
            option.unwrap(name, ""),
            workspace_json(workspace, name, False, option.values(entries)),
          ))
        }
      }
    }),
  )
  option.values(found)
  |> list.sort(fn(one, other) { string.compare(one.0, other.0) })
  |> list.map(fn(pair) { pair.1 })
}

fn workspace_json(
  owner: String,
  name: Option(String),
  own: Bool,
  entries: List(json.Json),
) -> json.Json {
  json.object([
    #("owner", json.string(owner)),
    #("name", json.nullable(name, json.string)),
    #("own", json.bool(own)),
    #("lines", json.preprocessed_array(entries)),
  ])
}

fn line_entry_json(
  line: lines.Line,
  shared: Bool,
  role: access.Role,
  own_team_member: Option(String),
) -> json.Json {
  let role = case role {
    access.Member(_) -> "member"
    access.Viewer -> "viewer"
    access.Owner | access.NoRole -> "owner"
  }
  json.object([
    #("id", json.string(line.id)),
    #("name", json.string(line.name)),
    #("shared", json.bool(shared)),
    #("role", json.string(role)),
    #("teamMember", json.nullable(own_team_member, json.string)),
  ])
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

fn line_name(workspace: String, line: String) -> wisp.Response {
  case lines.list(workspace) {
    Error(_) -> wisp.internal_server_error()
    Ok(found) ->
      case list.find(found, fn(one) { one.id == line }) {
        Ok(found) -> wisp.json_response(json.to_string(line_json(found)), 200)
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
/// nothing, and never the `public` Workspace.
fn caller_of(
  request: request.Request(body),
  context: Context,
) -> Result(String, Nil) {
  case workspace.from_request(request) {
    Ok(caller) if context.sso && caller == workspace.public -> Error(Nil)
    found -> found
  }
}

fn route(
  request: wisp.Request,
  segments: List(String),
  database: String,
  linking: Option(Linking),
  act_as: ActAs,
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
      pull(request, database, act_as)
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
      raise_andon(request, database, act_as)
    }
    ["api", "andon", "close"] -> {
      use <- wisp.require_method(request, http.Post)
      close_andon(request, database, act_as)
    }
    ["api", "assign"] -> {
      use <- wisp.require_method(request, http.Post)
      assign(request, database, act_as)
    }
    ["api", "team-members"] ->
      case request.method {
        http.Post -> add_team_member(request, database)
        _ -> {
          use <- wisp.require_method(request, http.Get)
          team_members(database)
        }
      }
    ["api", "design"] ->
      case request.method {
        http.Put -> save_design(request, database, linking)
        _ -> {
          use <- wisp.require_method(request, http.Get)
          design_of(database, linking)
        }
      }
    ["api", "labels"] -> {
      use <- wisp.require_method(request, http.Get)
      labels(database)
    }
    ["api", "team-members", team_member, "next"] -> {
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
      reset(request, database, linking)
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

fn design_of(database: String, linking: Option(Linking)) -> wisp.Response {
  case db.with_connection_at(database, design_json), links_of(linking) {
    Ok(to_json), Ok(links) ->
      wisp.json_response(json.to_string(to_json(links)), 200)
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

/// The email of each Team Member in the body; one with no `email` field,
/// sent by an SPA older than the links, keeps its link.
fn emails_decoder() -> decode.Decoder(List(#(String, String))) {
  use team_members <- decode.field(
    "teamMembers",
    decode.list({
      use id <- decode.field("id", decode.string)
      use email <- decode.optional_field(
        "email",
        None,
        decode.map(decode.string, Some),
      )
      decode.success(#(id, email))
    }),
  )
  list.filter_map(team_members, fn(pair) {
    option.to_result(pair.1, Nil) |> result.map(fn(email) { #(pair.0, email) })
  })
  |> decode.success
}

fn check_emails(
  emails: List(#(String, String)),
) -> Result(List(#(String, String)), String) {
  use checked <- result.try(
    list.try_map(emails, fn(pair) {
      case accounts.normal_email(pair.1) {
        Ok(email) -> Ok(#(pair.0, email))
        Error(Nil) ->
          Error("\"" <> string.trim(pair.1) <> "\" is not an email.")
      }
    }),
  )
  let given =
    list.map(checked, fn(pair) { pair.1 }) |> list.filter(fn(e) { e != "" })
  case accounts.unique_emails(given) {
    Ok(Nil) -> Ok(checked)
    Error(accounts.EmailTaken(email)) -> Error(email_taken(email))
    Error(accounts.LinkStoreFailed) -> Error("")
  }
}

fn email_taken(email: String) -> String {
  "Two Team Members have the email " <> email <> "."
}

fn save_design(
  request: wisp.Request,
  database: String,
  linking: Option(Linking),
) -> wisp.Response {
  use body <- wisp.require_json(request)
  case decode.run(body, design.decoder()), decode.run(body, emails_decoder()) {
    Ok(wanted), Ok(emails) ->
      case check_emails(emails) {
        Error(reason) -> wisp.bad_request(reason)
        Ok(emails) -> save_design_and_links(database, linking, wanted, emails)
      }
    _, _ ->
      wisp.bad_request(
        "expected the body of GET /api/design: {\"labels\", \"teamMembers\", \"steps\"}",
      )
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
          wisp.bad_request(email_taken(email))
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
            Ok(found) -> wisp.json_response(json.to_string(found), 200)
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
/// A Reset can bring back Team Member ids, so the Line's links go too.
fn reset(
  request: wisp.Request,
  database: String,
  linking: Option(Linking),
) -> wisp.Response {
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
  let cleared = fn() {
    case linking {
      None -> Ok(Nil)
      Some(linking) ->
        accounts.save_links(
          linking.accounts,
          linking.workspace,
          linking.line,
          wanted: [],
          kept: [],
        )
    }
  }
  case db.with_connection_at(database, run), cleared() {
    Ok(Nil), Ok(Nil) -> wisp.no_content()
    _, _ -> wisp.internal_server_error()
  }
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

fn raise_andon(
  request: wisp.Request,
  database: String,
  act_as: ActAs,
) -> wisp.Response {
  use body <- wisp.require_json(request)
  let decoder = {
    use station <- decode.field("station", decode.string)
    use team_member <- decode.optional_field(
      "teamMember",
      None,
      decode.optional(decode.string),
    )
    decode.success(#(station, team_member))
  }

  case decode.run(body, decoder) {
    Error(_) ->
      wisp.bad_request("expected a body like {\"station\": \"ws-web\"}")
    Ok(#(station, team_member)) ->
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
}

fn close_andon(
  request: wisp.Request,
  database: String,
  act_as: ActAs,
) -> wisp.Response {
  use body <- wisp.require_json(request)
  let decoder = {
    use station <- decode.field("station", decode.string)
    use team_member <- decode.field("teamMember", decode.string)
    decode.success(#(station, team_member))
  }

  case decode.run(body, decoder) {
    Error(_) ->
      wisp.bad_request(
        "expected a body like {\"station\": \"ws-web\", \"teamMember\": \"pe-bob\"}",
      )
    Ok(#(station, team_member)) ->
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

fn pull(
  request: wisp.Request,
  database: String,
  act_as: ActAs,
) -> wisp.Response {
  use body <- wisp.require_json(request)
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

  case decode.run(body, decoder) {
    Error(_) ->
      wisp.bad_request("expected a body like {\"station\": \"ws-web\"}")
    Ok(#(station, team_member, reason)) ->
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

fn assign(
  request: wisp.Request,
  database: String,
  act_as: ActAs,
) -> wisp.Response {
  use body <- wisp.require_json(request)
  let decoder = {
    use kind <- decode.field("kind", decode.string)
    use id <- decode.field("id", decode.string)
    use team_member <- decode.field("teamMember", decode.string)
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
        "expected a body like {\"kind\": \"piece\", \"id\": \"p-checkout-8-web\", \"teamMember\": \"pe-lila\"}",
      )
    Ok(#(kind, id, team_member)) ->
      case act_as(Some(team_member)) {
        Ok(Some(team_member)) -> reassign(database, kind, id, team_member)
        _ -> not_yours()
      }
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
      json_body(
        [
          #("piece", json.string(reassigned.piece)),
          #("teamMember", json.string(reassigned.team_member)),
        ],
        200,
      )
    Error(failure) -> flow_response(Error(failure))
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
