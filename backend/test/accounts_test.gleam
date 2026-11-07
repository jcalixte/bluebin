import bluebin
import bluebin/accounts
import bluebin/invitations
import bluebin/live
import gleam/http
import gleam/http/request
import gleam/int
import gleam/json
import gleam/list
import gleam/option.{None, Some}
import simplifile
import wisp/simulate

fn with_name(name: String) {
  request.new() |> request.set_header("x-authentik-name", name)
}

pub fn the_first_word_is_the_suggested_first_name_test() {
  assert accounts.suggested_name(with_name(" Ada  King Lovelace "))
    == #("Ada", "King Lovelace")
  assert accounts.suggested_name(with_name("Cher")) == #("Cher", "")
  assert accounts.suggested_name(request.new()) == #("", "")
}

/// Each test has its own accounts file, removed at the end.
fn scratch_accounts() -> String {
  "data/accounts-test-" <> int.to_string(int.random(1_000_000_000)) <> ".db"
}

fn remove(path: String) {
  let _ = simplifile.delete_all([path, path <> "-wal", path <> "-shm"])
  Nil
}

fn call(
  context: bluebin.Context,
  method: http.Method,
  headers: List(#(String, String)),
  body: String,
) {
  let request =
    simulate.request(method, "/api/account")
    |> simulate.string_body(body)
    |> simulate.header("content-type", "application/json")
  headers
  |> list.fold(request, fn(request, header) {
    simulate.header(request, header.0, header.1)
  })
  |> bluebin.handle_request(context)
}

const ada = [
  #("x-authentik-uid", "a1b2c3"),
  #("x-authentik-email", "ada@example.com"),
  #("x-authentik-name", "Ada Lovelace"),
]

const ada_named = "{\"firstName\": \"Augusta Ada\", \"lastName\": \"King\"}"

pub fn with_sso_off_no_account_is_made_test() {
  let assert Ok(hub) = live.start()
  let path = scratch_accounts()
  let context =
    bluebin.Context(hub:, sso: False, accounts: path, invite: no_invite)

  let looked = call(context, http.Get, ada, "")
  let saved = call(context, http.Put, ada, ada_named)

  assert looked.status == 200
  assert simulate.read_body(looked)
    == json.to_string(json.object([#("signedIn", json.bool(False))]))
  assert saved.status == 403
  assert simplifile.is_file(path) == Ok(False)
}

pub fn an_account_gives_its_name_once_test() {
  let assert Ok(hub) = live.start()
  let path = scratch_accounts()
  let context =
    bluebin.Context(hub:, sso: True, accounts: path, invite: no_invite)

  let first = call(context, http.Get, ada, "") |> simulate.read_body
  let saved = call(context, http.Put, ada, ada_named)
  let next = call(context, http.Get, ada, "") |> simulate.read_body
  remove(path)

  assert first
    == "{\"signedIn\":true,\"named\":false,\"admin\":false,\"email\":\"ada@example.com\",\"firstName\":\"Ada\",\"lastName\":\"Lovelace\"}"
  assert saved.status == 200
  assert next
    == "{\"signedIn\":true,\"named\":true,\"admin\":false,\"email\":\"ada@example.com\",\"firstName\":\"Augusta Ada\",\"lastName\":\"King\"}"
}

pub fn an_email_changed_in_authentik_replaces_the_stored_one_test() {
  let assert Ok(hub) = live.start()
  let path = scratch_accounts()
  let context =
    bluebin.Context(hub:, sso: True, accounts: path, invite: no_invite)

  let _ = call(context, http.Put, ada, ada_named)
  let moved = [
    #("x-authentik-uid", "a1b2c3"),
    #("x-authentik-email", "ada@lovelace.org"),
  ]
  let _ = call(context, http.Get, moved, "")
  let stored = accounts.sign_in(path, "a1b2c3", "ada@lovelace.org")
  remove(path)

  assert stored
    == Ok(
      Some(accounts.Account(
        email: "ada@lovelace.org",
        first_name: "Augusta Ada",
        last_name: "King",
      )),
    )
}

pub fn an_empty_name_makes_no_account_test() {
  let assert Ok(hub) = live.start()
  let path = scratch_accounts()
  let context =
    bluebin.Context(hub:, sso: True, accounts: path, invite: no_invite)

  let saved =
    call(
      context,
      http.Put,
      ada,
      "{\"firstName\": \" \", \"lastName\": \"King\"}",
    )
  let stored = accounts.sign_in(path, "a1b2c3", "ada@example.com")
  remove(path)

  assert saved.status == 400
  assert stored == Ok(None)
}

pub fn with_sso_on_an_account_needs_an_email_test() {
  let assert Ok(hub) = live.start()
  let path = scratch_accounts()
  let context =
    bluebin.Context(hub:, sso: True, accounts: path, invite: no_invite)

  let no_email = [#("x-authentik-uid", "a1b2c3")]
  let looked = call(context, http.Get, no_email, "")
  let saved = call(context, http.Put, no_email, ada_named)
  let visitor = call(context, http.Get, [], "") |> simulate.read_body
  remove(path)

  assert looked.status == 401
  assert saved.status == 401
  assert visitor == "{\"signedIn\":false}"
}

fn no_invite() {
  Error(invitations.NoToken)
}
