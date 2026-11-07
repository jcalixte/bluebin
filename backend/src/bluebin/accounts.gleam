import bluebin/db
import bluebin/text
import gleam/dict
import gleam/dynamic/decode
import gleam/http/request.{type Request}
import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/result
import gleam/string
import simplifile
import sqlight

/// One file for every Workspace: an Account and its links cross Lines and
/// Workspaces (ADR-0004). Must stay under `data/`, the mounted volume.
pub const database = "data/accounts.db"

pub const max_name_length = 60

pub type Account {
  Account(email: String, first_name: String, last_name: String)
}

pub type AccountError {
  EmptyName
  NameTooLong
  StoreFailed
}

/// The email the owner typed on a Team Member, and the Account that has it.
/// The link holds once such an Account exists (ADR-0003).
pub type Link {
  Link(team_member: String, email: String, account: Option(Account))
}

pub type LinkError {
  EmailTaken(email: String)
  LinkStoreFailed
}

const max_email_length = 254

/// Additive only: during a rolling deploy the old code runs on this file too.
const schema =
  "
create table if not exists account (
  uid        text primary key,
  email      text not null,
  first_name text not null,
  last_name  text not null,
  created_at text not null default (strftime('%Y-%m-%dT%H:%M:%SZ', 'now'))
);
create table if not exists team_member_link (
  workspace   text not null,
  line        text not null,
  team_member text not null,
  email       text not null,
  primary key (workspace, line, team_member),
  unique (workspace, line, email)
);
create index if not exists team_member_link_by_email on team_member_link (email);
create table if not exists link_change (
  at          text not null default (strftime('%Y-%m-%dT%H:%M:%SZ', 'now')),
  workspace   text not null,
  line        text not null,
  team_member text not null,
  email       text
);
create table if not exists line_share_change (
  at        text not null default (strftime('%Y-%m-%dT%H:%M:%SZ', 'now')),
  workspace text not null,
  line      text not null,
  shared    integer not null
);
create index if not exists line_share_change_by_line
  on line_share_change (workspace, line);
"

/// Traefik forward auth copies these from authentik's answer, so they are
/// trusted only while SSO is on (ADR-0003).
const email_header = "x-authentik-email"

const name_header = "x-authentik-name"

pub fn email_of(request: Request(body)) -> Result(String, Nil) {
  case request.get_header(request, email_header) {
    Ok(email) ->
      case string.trim(email) {
        "" -> Error(Nil)
        email -> Ok(email)
      }
    Error(Nil) -> Error(Nil)
  }
}

/// The first and last name to suggest on the first sign-in, from the one
/// name authentik knows: its first word, then the rest.
pub fn suggested_name(request: Request(body)) -> #(String, String) {
  let name = request.get_header(request, name_header) |> result.unwrap("")
  case string.split_once(string.trim(name), " ") {
    Ok(#(first, last)) -> #(first, string.trim(last))
    Error(Nil) -> #(string.trim(name), "")
  }
}

/// The Account of `uid`, `None` before its first and last name are given.
/// An email changed in authentik replaces the stored one.
pub fn sign_in(
  database: String,
  uid: String,
  email: String,
) -> Result(Option(Account), Nil) {
  use connection <- open(database)
  use _ <- result.try(
    sqlight.query(
      "update account set email = ?2 where uid = ?1 and email <> ?2",
      on: connection,
      with: [sqlight.text(uid), sqlight.text(email)],
      expecting: decode.success(Nil),
    )
    |> result.replace_error(Nil),
  )
  case
    sqlight.query(
      "select email, first_name, last_name from account where uid = ?1",
      on: connection,
      with: [sqlight.text(uid)],
      expecting: account_decoder(),
    )
  {
    Ok([account, ..]) -> Ok(Some(account))
    Ok([]) -> Ok(None)
    Error(_) -> Error(Nil)
  }
}

/// Makes the Account on its first save; later saves change its name.
pub fn save(
  database: String,
  uid: String,
  email: String,
  first_name: String,
  last_name: String,
) -> Result(Account, AccountError) {
  use first_name <- result.try(check_name(first_name))
  use last_name <- result.try(check_name(last_name))
  let saved = {
    use connection <- open(database)
    sqlight.query(
      "insert into account (uid, email, first_name, last_name)
       values (?1, ?2, ?3, ?4)
       on conflict (uid) do update
         set email = excluded.email,
             first_name = excluded.first_name,
             last_name = excluded.last_name",
      on: connection,
      with: [
        sqlight.text(uid),
        sqlight.text(email),
        sqlight.text(first_name),
        sqlight.text(last_name),
      ],
      expecting: decode.success(Nil),
    )
    |> result.replace_error(Nil)
  }
  case saved {
    Ok(_) -> Ok(Account(email:, first_name:, last_name:))
    Error(Nil) -> Error(StoreFailed)
  }
}

/// Lowercase, so a link does not depend on how the owner types the email.
/// An empty email means no link.
pub fn normal_email(email: String) -> Result(String, Nil) {
  let email = string.trim(email) |> string.lowercase
  let shaped = case string.split(email, "@") {
    [name, domain] -> name != "" && string.contains(domain, ".")
    _ -> False
  }
  case email {
    "" -> Ok("")
    _ ->
      case
        shaped
        && string.length(email) <= max_email_length
        && !string.contains(email, " ")
      {
        True -> Ok(email)
        False -> Error(Nil)
      }
  }
}

/// The links of one Line. A link to a Team Member who left the Line grants
/// nothing: the caller keeps only the Team Members it knows (ADR-0004).
pub fn links(
  database: String,
  workspace: String,
  line: String,
) -> Result(List(Link), Nil) {
  use connection <- open(database)
  sqlight.query(
    "select l.team_member, l.email, a.email, a.first_name, a.last_name
       from team_member_link l
       left join account a
         on a.uid = (select uid from account
                      where lower(email) = l.email
                      order by created_at limit 1)
      where l.workspace = ?1 and l.line = ?2",
    on: connection,
    with: [sqlight.text(workspace), sqlight.text(line)],
    expecting: {
      use team_member <- decode.field(0, decode.string)
      use email <- decode.field(1, decode.string)
      use account <- decode.field(2, decode.optional(decode.string))
      use first_name <- decode.field(3, decode.optional(decode.string))
      use last_name <- decode.field(4, decode.optional(decode.string))
      let account = case account, first_name, last_name {
        Some(email), Some(first_name), Some(last_name) ->
          Some(Account(email:, first_name:, last_name:))
        _, _, _ -> None
      }
      decode.success(Link(team_member:, email:, account:))
    },
  )
  |> result.replace_error(Nil)
}

/// Sets the email of each Team Member in `wanted` (an empty one removes the
/// link) and removes the links of every Team Member not in `kept`. Each
/// change goes to the dated log (R8), in the same transaction.
pub fn save_links(
  database: String,
  workspace: String,
  line: String,
  wanted wanted: List(#(String, String)),
  kept kept: List(String),
) -> Result(Nil, LinkError) {
  let saved = {
    use connection <- open(database)
    Ok({
      use <- db.transaction(connection, fn(_) { LinkStoreFailed })
      change_links(connection, workspace, line, wanted, kept)
    })
  }
  case saved {
    Ok(outcome) -> outcome
    Error(Nil) -> Error(LinkStoreFailed)
  }
}

fn change_links(
  connection: sqlight.Connection,
  workspace: String,
  line: String,
  wanted: List(#(String, String)),
  kept: List(String),
) -> Result(Nil, LinkError) {
  use current <- result.try(
    sqlight.query(
      "select team_member, email from team_member_link
        where workspace = ?1 and line = ?2",
      on: connection,
      with: [sqlight.text(workspace), sqlight.text(line)],
      expecting: {
        use team_member <- decode.field(0, decode.string)
        use email <- decode.field(1, decode.string)
        decode.success(#(team_member, email))
      },
    )
    |> result.map(dict.from_list)
    |> result.replace_error(LinkStoreFailed),
  )
  let after =
    list.fold(wanted, current, fn(links, pair) {
      case pair.1 {
        "" -> dict.delete(links, pair.0)
        email -> dict.insert(links, pair.0, email)
      }
    })
    |> dict.filter(fn(team_member, _) { list.contains(kept, team_member) })
  use _ <- result.try(unique_emails(dict.values(after)))

  let gone =
    dict.filter(current, fn(team_member, email) {
      dict.get(after, team_member) != Ok(email)
    })
  let made =
    dict.filter(after, fn(team_member, email) {
      dict.get(current, team_member) != Ok(email)
    })
  // Removals first, so two Team Members can swap their emails.
  use _ <- result.try(
    dict.to_list(gone)
    |> list.try_each(fn(pair) {
      write_link(
        connection,
        "delete from team_member_link
          where workspace = ?1 and line = ?2 and team_member = ?3",
        [workspace, line, pair.0],
      )
    }),
  )
  use _ <- result.try(
    dict.to_list(made)
    |> list.try_each(fn(pair) {
      write_link(
        connection,
        "insert into team_member_link (workspace, line, team_member, email)
         values (?1, ?2, ?3, ?4)",
        [workspace, line, pair.0, pair.1],
      )
    }),
  )
  dict.keys(gone)
  |> list.append(dict.keys(made))
  |> list.unique
  |> list.try_each(fn(team_member) {
    sqlight.query(
      "insert into link_change (workspace, line, team_member, email)
       values (?1, ?2, ?3, ?4)",
      on: connection,
      with: [
        sqlight.text(workspace),
        sqlight.text(line),
        sqlight.text(team_member),
        sqlight.nullable(
          sqlight.text,
          dict.get(after, team_member) |> option.from_result,
        ),
      ],
      expecting: decode.success(Nil),
    )
    |> result.replace(Nil)
    |> result.replace_error(LinkStoreFailed)
  })
}

/// One email for each Line: an Account is at most one Team Member there.
pub fn unique_emails(emails: List(String)) -> Result(Nil, LinkError) {
  case first_duplicate(emails) {
    None -> Ok(Nil)
    Some(email) -> Error(EmailTaken(email))
  }
}

fn first_duplicate(emails: List(String)) -> Option(String) {
  case emails {
    [] -> None
    [email, ..rest] ->
      case list.contains(rest, email) {
        True -> Some(email)
        False -> first_duplicate(rest)
      }
  }
}

/// The email of each Team Member in a Design body; one with no `email`
/// field, sent by an SPA older than the links, keeps its link.
pub fn emails_decoder() -> decode.Decoder(List(#(String, String))) {
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

/// Each (Team Member, email) pair with its email made normal, or the reason
/// to show the owner: an email that is none, or one given twice.
pub fn check_emails(
  emails: List(#(String, String)),
) -> Result(List(#(String, String)), String) {
  use checked <- result.try(
    list.try_map(emails, fn(pair) {
      case normal_email(pair.1) {
        Ok(email) -> Ok(#(pair.0, email))
        Error(Nil) ->
          Error("\"" <> string.trim(pair.1) <> "\" is not an email.")
      }
    }),
  )
  let given =
    list.map(checked, fn(pair) { pair.1 }) |> list.filter(fn(e) { e != "" })
  case first_duplicate(given) {
    None -> Ok(checked)
    Some(email) -> Error(email_taken(email))
  }
}

pub fn email_taken(email: String) -> String {
  "Two Team Members have the email " <> email <> "."
}

fn write_link(
  connection: sqlight.Connection,
  sql: String,
  values: List(String),
) -> Result(Nil, LinkError) {
  sqlight.query(
    sql,
    on: connection,
    with: list.map(values, sqlight.text),
    expecting: decode.success(Nil),
  )
  |> result.replace(Nil)
  |> result.replace_error(LinkStoreFailed)
}

/// Where the Account with `email` is a Team Member: (Workspace, Line, Team
/// Member), across every Workspace.
pub fn links_of(
  database: String,
  email: String,
) -> Result(List(#(String, String, String)), Nil) {
  use connection <- open(database)
  sqlight.query(
    "select workspace, line, team_member from team_member_link
      where email = lower(?1)",
    on: connection,
    with: [sqlight.text(string.trim(email))],
    expecting: {
      use workspace <- decode.field(0, decode.string)
      use line <- decode.field(1, decode.string)
      use team_member <- decode.field(2, decode.string)
      decode.success(#(workspace, line, team_member))
    },
  )
  |> result.replace_error(Nil)
}

/// A Line is Private until its owner shares it. The last dated change wins,
/// so the log is the state.
pub fn is_shared(
  database: String,
  workspace: String,
  line: String,
) -> Result(Bool, Nil) {
  use connection <- open(database)
  case
    sqlight.query(
      "select shared from line_share_change
        where workspace = ?1 and line = ?2
        order by rowid desc limit 1",
      on: connection,
      with: [sqlight.text(workspace), sqlight.text(line)],
      expecting: decode.field(0, decode.int, decode.success),
    )
  {
    Ok([shared, ..]) -> Ok(shared == 1)
    Ok([]) -> Ok(False)
    Error(_) -> Error(Nil)
  }
}

pub fn share(
  database: String,
  workspace: String,
  line: String,
  shared: Bool,
) -> Result(Nil, Nil) {
  use connection <- open(database)
  sqlight.query(
    "insert into line_share_change (workspace, line, shared)
     values (?1, ?2, ?3)",
    on: connection,
    with: [sqlight.text(workspace), sqlight.text(line), sqlight.bool(shared)],
    expecting: decode.success(Nil),
  )
  |> result.replace(Nil)
  |> result.replace_error(Nil)
}

/// The owner's name, to title a Workspace; `None` before the first sign-in.
pub fn name_of_uid(
  database: String,
  uid: String,
) -> Result(Option(String), Nil) {
  use connection <- open(database)
  case
    sqlight.query(
      "select email, first_name, last_name from account where uid = ?1",
      on: connection,
      with: [sqlight.text(uid)],
      expecting: account_decoder(),
    )
  {
    Ok([account, ..]) -> Ok(Some(full_name(account)))
    Ok([]) -> Ok(None)
    Error(_) -> Error(Nil)
  }
}

pub fn full_name(account: Account) -> String {
  account.first_name <> " " <> account.last_name
}

fn check_name(name: String) -> Result(String, AccountError) {
  text.check(name, max_name_length)
  |> result.map_error(fn(error) {
    case error {
      text.Empty -> EmptyName
      text.TooLong -> NameTooLong
    }
  })
}

fn account_decoder() -> decode.Decoder(Account) {
  use email <- decode.field(0, decode.string)
  use first_name <- decode.field(1, decode.string)
  use last_name <- decode.field(2, decode.string)
  decode.success(Account(email:, first_name:, last_name:))
}

fn open(
  database: String,
  run: fn(sqlight.Connection) -> Result(a, Nil),
) -> Result(a, Nil) {
  // The data can be wiped while the server runs: SQLite makes the file, not
  // its directory.
  let _ = simplifile.create_directory_all(db.directory_of(database))
  use connection <- db.with_connection_at(database)
  use _ <- result.try(
    sqlight.exec(schema, connection) |> result.replace_error(Nil),
  )
  run(connection)
}
