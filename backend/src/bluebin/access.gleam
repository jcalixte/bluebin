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

pub type Role {
  Owner
  Member(team_member: String)
  Viewer
  NoRole
}

pub type Need {
  Read
  Flow
  Own
}

pub type Refusal {
  NoSuchRoute
  WrongMethod(allowed: List(http.Method))
}

/// Every route inside a Line must be listed in `routes` (§8).
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
    ["api", "demands", _, "code"] -> [#(http.Put, Flow)]
    ["api", "line"] -> [#(http.Get, Read)]
    ["api", "backlog"] -> [#(http.Get, Read)]
    ["api", "backlog", "urgent"] -> [#(http.Post, Flow)]
    ["api", "backlog", "route"] -> [#(http.Post, Flow)]
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
    ["api", "line-changes"] -> [#(http.Get, Read)]
    ["api", "measures", "weeks"] -> [#(http.Get, Read)]
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

/// `email` is `None` unless SSO is on and the Account is signed in (F52).
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

/// A link to a Team Member who left grants nothing (ADR-0004).
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
/// (R7).
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

pub type OpenWorkspace {
  OpenWorkspace(
    owner: String,
    name: Option(String),
    own: Bool,
    lines: List(OpenLine),
  )
}

pub type OpenLine {
  OpenLine(
    line: lines.Line,
    shared: Bool,
    role: Role,
    team_member: Option(String),
  )
}

/// `email` is `None` unless SSO is on and the Account is signed in (F52).
/// May make the caller's first Line, from `start`.
pub fn workspaces(
  accounts_database: String,
  caller: String,
  email: Option(String),
  start: db.Start,
) -> Result(List(OpenWorkspace), Nil) {
  use own_memberships <- result.try(case email {
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
        team_member: list.key_find(own_memberships, line.id)
          |> option.from_result,
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
