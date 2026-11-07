import bluebin/accounts
import bluebin/db
import bluebin/lines
import gleam/dynamic/decode
import gleam/http
import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/result
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

/// The role table. `segments` is the path inside the Line, `["api"]` for
/// the Line itself. A route missing here is refused (§8).
pub fn need(method: http.Method, segments: List(String)) -> Result(Need, Nil) {
  case method, segments {
    http.Get, ["api"]
    | http.Get, ["api", "events"]
    | http.Get, ["api", "demands"]
    | http.Get, ["api", "line"]
    | http.Get, ["api", "backlog"]
    | http.Get, ["api", "andons"]
    | http.Get, ["api", "team-members"]
    | http.Get, ["api", "team-members", _, "next"]
    | http.Get, ["api", "design"]
    | http.Get, ["api", "labels"]
    | http.Get, ["api", "measures"]
    | http.Get, ["api", "calendar"]
    -> Ok(Read)

    http.Post, ["api", "demands"]
    | http.Post, ["api", "backlog", "urgent"]
    | http.Post, ["api", "pull"]
    | http.Post, ["api", "finish"]
    | http.Post, ["api", "deliver"]
    | http.Post, ["api", "rework"]
    | http.Post, ["api", "rework", "repair"]
    | http.Post, ["api", "andon"]
    | http.Post, ["api", "andon", "close"]
    | http.Post, ["api", "assign"]
    -> Ok(Flow)

    http.Put, ["api"]
    | http.Put, ["api", "sharing"]
    | http.Post, ["api", "team-members"]
    | http.Put, ["api", "design"]
    | http.Put, ["api", "steps", _]
    | http.Put, ["api", "calendar"]
    | http.Post, ["api", "reset"]
    -> Ok(Own)

    _, _ -> Error(Nil)
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
  case lines.database(workspace, line) {
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
