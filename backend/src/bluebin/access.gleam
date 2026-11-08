import bluebin/accounts
import bluebin/db
import bluebin/lines
import gleam/dynamic/decode
import gleam/http
import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/result
import gleam/string
import sqlight

/// What an Account may do in one Line (H10).
pub type Role {
  Owner
  Member(team_member: String)
  Viewer
  NoRole
}

/// What a route inside a Line asks of the Role.
pub type Need {
  Read
  Flow
  Own
}

/// Why `need` found no Need: the path is no route inside a Line, or the
/// route takes other methods.
pub type Refusal {
  NoSuchRoute
  WrongMethod(allowed: List(http.Method))
}

/// The role table, the one list of routes inside a Line. `segments` is the
/// path inside the Line, `["api"]` for the Line itself (§8).
pub fn need(
  method: http.Method,
  segments: List(String),
) -> Result(Need, Refusal) {
  case routes(segments) {
    [] -> Error(NoSuchRoute)
    allowed ->
      list.key_find(allowed, method)
      |> result.replace_error(WrongMethod(list.map(allowed, fn(one) { one.0 })))
  }
}

fn routes(segments: List(String)) -> List(#(http.Method, Need)) {
  case segments {
    ["api"] -> [#(http.Get, Read), #(http.Put, Own)]
    ["api", "events"] -> [#(http.Get, Read)]
    ["api", "demands"] -> [#(http.Get, Read), #(http.Post, Flow)]
    ["api", "line"] -> [#(http.Get, Read)]
    ["api", "backlog"] -> [#(http.Get, Read)]
    ["api", "backlog", "urgent"] -> [#(http.Post, Flow)]
    ["api", "pull"] -> [#(http.Post, Flow)]
    ["api", "finish"] -> [#(http.Post, Flow)]
    ["api", "deploy"] -> [#(http.Post, Flow)]
    ["api", "release"] -> [#(http.Post, Flow)]
    ["api", "rework"] -> [#(http.Post, Flow)]
    ["api", "rework", "repair"] -> [#(http.Post, Flow)]
    ["api", "help"] -> [#(http.Post, Flow)]
    ["api", "help", "stop"] -> [#(http.Post, Flow)]
    ["api", "andons"] -> [#(http.Get, Read)]
    ["api", "andon"] -> [#(http.Post, Flow)]
    ["api", "andon", "close"] -> [#(http.Post, Flow)]
    ["api", "assign"] -> [#(http.Post, Flow)]
    ["api", "team-members"] -> [#(http.Get, Read), #(http.Post, Own)]
    ["api", "team-members", _, "next"] -> [#(http.Get, Read)]
    ["api", "design"] -> [#(http.Get, Read), #(http.Put, Own)]
    ["api", "labels"] -> [#(http.Get, Read)]
    ["api", "measures"] -> [#(http.Get, Read)]
    ["api", "calendar"] -> [#(http.Get, Read), #(http.Put, Own)]
    ["api", "steps", _] -> [#(http.Put, Own)]
    ["api", "sharing"] -> [#(http.Put, Own)]
    _ -> []
  }
}

pub fn allows(role: Role, need: Need) -> Bool {
  case role, need {
    Owner, _ -> True
    Member(_), Read | Member(_), Flow -> True
    Viewer, Read -> True
    _, _ -> False
  }
}

/// `email` is `None` unless SSO is on and the Account is signed in (F52):
/// then only its own Workspace opens.
pub fn role(
  accounts_database: String,
  caller: String,
  email: Option(String),
  workspace: String,
  line: String,
) -> Result(Role, Nil) {
  case workspace == caller, email {
    True, _ -> Ok(Owner)
    False, None -> Ok(NoRole)
    False, Some(email) -> {
      use held <- result.try(live_links(accounts_database, email, workspace))
      case list.key_find(held, line) {
        Ok(team_member) -> Ok(Member(team_member))
        Error(Nil) -> anyone(accounts_database, workspace, line)
      }
    }
  }
}

/// The Role of anyone, signed in or not, who is no Team Member of `line`:
/// a Shared Line shows, look-only (F53).
pub fn anyone(
  accounts_database: String,
  workspace: String,
  line: String,
) -> Result(Role, Nil) {
  case lines.exists(workspace, line) {
    False -> Ok(NoRole)
    True -> {
      use shared <- result.map(accounts.is_shared(
        accounts_database,
        workspace,
        line,
      ))
      case shared {
        True -> Viewer
        False -> NoRole
      }
    }
  }
}

/// The (Line, Team Member) pairs where `email` is a Team Member of
/// `workspace`. A link to a Team Member who left grants nothing (ADR-0004).
pub fn live_links(
  accounts_database: String,
  email: String,
  workspace: String,
) -> Result(List(#(String, String)), Nil) {
  use links <- result.try(accounts.links_of(accounts_database, email))
  list.filter_map(links, fn(link) {
    let #(in_workspace, line, team_member) = link
    case in_workspace == workspace && lines.exists(workspace, line) {
      False -> Error(Nil)
      True ->
        case is_team_member(workspace, line, team_member) {
          True -> Ok(#(line, team_member))
          False -> Error(Nil)
        }
    }
  })
  |> Ok
}

fn is_team_member(
  workspace: String,
  line: String,
  team_member: String,
) -> Bool {
  case lines.database(workspace, line, db.Empty) {
    Error(_) -> False
    Ok(database) ->
      db.with_connection_at(database, fn(connection) {
        sqlight.query(
          "select 1 from team_member where id = ?1 and removed_at is null",
          on: connection,
          with: [sqlight.text(team_member)],
          expecting: decode.success(Nil),
        )
      })
      == Ok([Nil])
  }
}

/// The Team Member a flow action acts as, from the `teamMember` of the
/// request (F50). A Member acts only as themselves, by default too; the
/// owner acts for any Team Member that `linked_elsewhere` does not claim.
pub fn actor(
  role: Role,
  wanted: Option(String),
  linked_elsewhere: fn(String) -> Bool,
) -> Result(Option(String), Nil) {
  case role, wanted {
    Member(own), None -> Ok(Some(own))
    Member(own), Some(team_member) if team_member == own -> Ok(Some(own))
    Owner, None -> Ok(None)
    Owner, Some(team_member) ->
      case linked_elsewhere(team_member) {
        True -> Error(Nil)
        False -> Ok(Some(team_member))
      }
    _, _ -> Error(Nil)
  }
}

/// A Team Member linked to another Account acts only through that Account
/// (R7). `email` is `None` unless the Account is signed in.
pub fn linked_elsewhere(
  accounts_database: String,
  email: Option(String),
  workspace: String,
  line: String,
  team_member: String,
) -> Bool {
  case email {
    None -> False
    Some(email) ->
      case accounts.links(accounts_database, workspace, line) {
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

/// A Workspace the Account can open, with the Lines it opens there.
pub type OpenWorkspace {
  OpenWorkspace(
    owner: String,
    name: Option(String),
    own: Bool,
    lines: List(OpenLine),
  )
}

/// `team_member` is the Account's own Team Member in the Line, if any.
pub type OpenLine {
  OpenLine(
    line: lines.Line,
    shared: Bool,
    role: Role,
    team_member: Option(String),
  )
}

/// Every Line the Account can open, by Workspace, its own first (F46).
/// `email` is `None` unless SSO is on and the Account is signed in: then
/// only its own Workspace opens (F52). `start` is how the caller's own first
/// Line starts, when this call makes it.
pub fn workspaces(
  accounts_database: String,
  caller: String,
  email: Option(String),
  start: db.Start,
) -> Result(List(OpenWorkspace), Nil) {
  // The owner can be a Team Member of their own Lines too (F45).
  use held <- result.try(case email {
    Some(email) -> live_links(accounts_database, email, caller)
    None -> Ok([])
  })
  use own <- result.try(lines.list(caller, start) |> result.replace_error(Nil))
  use own <- result.try(
    list.try_map(own, fn(line) {
      use shared <- result.map(case email {
        Some(_) -> accounts.is_shared(accounts_database, caller, line.id)
        None -> Ok(False)
      })
      OpenLine(
        line:,
        shared:,
        role: Owner,
        team_member: list.key_find(held, line.id) |> option.from_result,
      )
    }),
  )
  case email {
    None ->
      Ok([OpenWorkspace(owner: caller, name: None, own: True, lines: own)])
    Some(email) -> {
      use name <- result.try(accounts.name_of_uid(accounts_database, caller))
      use others <- result.map(other_workspaces(
        accounts_database,
        caller,
        email,
      ))
      [OpenWorkspace(owner: caller, name:, own: True, lines: own), ..others]
    }
  }
}

/// The Workspaces where `email` is a Team Member: its Lines there, and the
/// Shared Lines of those Workspaces, by owner name.
fn other_workspaces(
  accounts_database: String,
  caller: String,
  email: String,
) -> Result(List(OpenWorkspace), Nil) {
  use links <- result.try(accounts.links_of(accounts_database, email))
  let workspaces =
    list.map(links, fn(link) { link.0 })
    |> list.unique
    |> list.filter(fn(workspace) { workspace != caller })
  use found <- result.map(
    list.try_map(workspaces, fn(workspace) {
      use held <- result.try(live_links(accounts_database, email, workspace))
      case held {
        [] -> Ok(None)
        _ -> {
          use all <- result.try(
            lines.list(workspace, db.Empty) |> result.replace_error(Nil),
          )
          use entries <- result.try(
            list.try_map(all, fn(line) {
              use shared <- result.map(accounts.is_shared(
                accounts_database,
                workspace,
                line.id,
              ))
              case list.key_find(held, line.id), shared {
                Ok(team_member), _ ->
                  Some(OpenLine(
                    line:,
                    shared:,
                    role: Member(team_member),
                    team_member: Some(team_member),
                  ))
                Error(Nil), True ->
                  Some(OpenLine(line:, shared:, role: Viewer, team_member: None))
                Error(Nil), False -> None
              }
            }),
          )
          use name <- result.map(accounts.name_of_uid(
            accounts_database,
            workspace,
          ))
          Some(OpenWorkspace(
            owner: workspace,
            name:,
            own: False,
            lines: option.values(entries),
          ))
        }
      }
    }),
  )
  option.values(found)
  |> list.sort(fn(one, other) {
    string.compare(option.unwrap(one.name, ""), option.unwrap(other.name, ""))
  })
}
