import bluebin/db
import gleam/dynamic/decode
import gleam/http/request.{type Request}
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

/// Additive only: during a rolling deploy the old code runs on this file too.
const schema = "
create table if not exists account (
  uid        text primary key,
  email      text not null,
  first_name text not null,
  last_name  text not null,
  created_at text not null default (strftime('%Y-%m-%dT%H:%M:%SZ', 'now'))
);
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

fn check_name(name: String) -> Result(String, AccountError) {
  let name = string.trim(name)
  case string.is_empty(name), string.length(name) > max_name_length {
    True, _ -> Error(EmptyName)
    _, True -> Error(NameTooLong)
    False, False -> Ok(name)
  }
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
