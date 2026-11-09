import bluebin
import bluebin/accounts
import bluebin/db
import bluebin/invitations
import bluebin/lines
import bluebin/live
import gleam/dynamic/decode
import gleam/http
import gleam/int
import gleam/list
import gleam/string
import simplifile
import sqlight
import wisp/simulate

pub fn an_email_is_lowercase_and_shaped_test() {
  assert accounts.normal_email("  Ada@Example.COM ") == Ok("ada@example.com")
  assert accounts.normal_email(" ") == Ok("")
  assert accounts.normal_email("ada") == Error(Nil)
  assert accounts.normal_email("ada@example") == Error(Nil)
  assert accounts.normal_email("@example.com") == Error(Nil)
  assert accounts.normal_email("a@b@example.com") == Error(Nil)
  assert accounts.normal_email("ada lovelace@example.com") == Error(Nil)
}

fn random(prefix: String) -> String {
  prefix <> int.to_string(int.random(1_000_000_000))
}

fn remove(path: String) {
  let _ = simplifile.delete_all([path, path <> "-wal", path <> "-shm"])
  Nil
}

fn emails(path: String, workspace: String) -> List(#(String, String)) {
  let assert Ok(found) = accounts.links(path, workspace, lines.first)
  list.map(found, fn(link) { #(link.team_member, link.email) })
  |> list.sort(fn(a, b) { string.compare(a.0, b.0) })
}

fn logged(path: String) -> List(#(String, String)) {
  use connection <- db.with_connection_at(path)
  let assert Ok(rows) =
    sqlight.query(
      "select team_member, coalesce(email, '-') from link_change order by rowid",
      on: connection,
      with: [],
      expecting: {
        use team_member <- decode.field(0, decode.string)
        use email <- decode.field(1, decode.string)
        decode.success(#(team_member, email))
      },
    )
  rows
}

pub fn links_change_with_a_dated_log_test() {
  let path = random("data/links-test-") <> ".db"
  let save = fn(wanted, kept) {
    accounts.save_links(path, "w1", lines.first, wanted:, kept:)
  }
  let all = ["pe-a", "pe-b", "pe-c"]

  let assert Ok(Nil) =
    save([#("pe-a", "a@example.com"), #("pe-b", "b@example.com")], all)
  let first = emails(path, "w1")
  let assert Ok(Nil) =
    save([#("pe-a", "b@example.com"), #("pe-b", "a@example.com")], all)
  let swapped = emails(path, "w1")
  let taken = save([#("pe-c", "a@example.com")], all)
  // An empty email unlinks; a Team Member who left the Line loses its link.
  let assert Ok(Nil) = save([#("pe-a", "")], ["pe-a"])
  let left = emails(path, "w1")
  let log = logged(path)
  remove(path)

  assert first == [#("pe-a", "a@example.com"), #("pe-b", "b@example.com")]
  assert swapped == [#("pe-a", "b@example.com"), #("pe-b", "a@example.com")]
  assert taken == Error(accounts.EmailTaken("a@example.com"))
  assert left == []
  assert list.length(log) == 6
  assert list.drop(log, 4) |> list.sort(fn(a, b) { string.compare(a.0, b.0) })
    == [#("pe-a", "-"), #("pe-b", "-")]
}

fn context(path: String, sso: Bool) -> bluebin.Context {
  let assert Ok(hub) = live.start()
  bluebin.Context(hub:, sso:, accounts: path, invite: fn() {
    Error(invitations.NoToken)
  })
}

fn call(
  context: bluebin.Context,
  method: http.Method,
  path: String,
  who: #(String, String),
  body: String,
) -> #(Int, String) {
  let response =
    simulate.request(method, path)
    |> simulate.header("x-authentik-uid", who.0)
    |> simulate.header("x-authentik-email", who.1)
    |> simulate.string_body(body)
    |> simulate.header("content-type", "application/json")
    |> bluebin.handle_request(context)
  #(response.status, simulate.read_body(response))
}

const ines = "\"id\":\"pe-ines\",\"name\":\"Inès\""

/// The GET body is a valid PUT body.
fn with_email_for_ines(design: String, email: String) -> String {
  let assert Ok(#(before, after)) =
    string.split_once(design, ines <> ",\"email\":\"\"")
  before <> ines <> ",\"email\":\"" <> email <> "\"" <> after
}

fn setup(sso: Bool) {
  let owner = #(random("links-owner-"), "owner@example.com")
  let ada = #(random("links-ada-"), "Ada@Example.com")
  let path = random("data/links-test-") <> ".db"
  let assert Ok(Nil) = simplifile.create_directory_all(db.workspaces_directory)
  // With SSO on a Line starts empty; these tests need the demo data.
  let assert Ok(Nil) = db.ready(db.workspace_path(owner.0), db.Demo)
  #(context(path, sso), owner, ada, path)
}

fn call_as_admin(
  context: bluebin.Context,
  method: http.Method,
  path: String,
  who: #(String, String),
) -> #(Int, String) {
  let response =
    simulate.request(method, path)
    |> simulate.header("x-authentik-uid", who.0)
    |> simulate.header("x-authentik-email", who.1)
    |> simulate.header("x-authentik-username", "akadmin")
    |> bluebin.handle_request(context)
  #(response.status, simulate.read_body(response))
}

fn clean(owner: #(String, String), ada: #(String, String), path: String) {
  remove(path)
  remove(db.workspace_path(owner.0))
  remove(db.workspace_path(ada.0))
}

pub fn a_link_holds_from_the_next_sign_in_test() {
  let #(context, owner, ada, path) = setup(True)

  let #(_, design) = call(context, http.Get, "/api/design", owner, "")
  let #(saved, _) =
    call(
      context,
      http.Put,
      "/api/design",
      owner,
      with_email_for_ines(design, " ADA@example.com "),
    )
  let #(_, not_yet) = call(context, http.Get, "/api/design", owner, "")
  let _ =
    call(
      context,
      http.Put,
      "/api/account",
      ada,
      "{\"firstName\": \"Augusta Ada\", \"lastName\": \"King\"}",
    )
  let #(_, linked) = call(context, http.Get, "/api/design", owner, "")
  let #(_, line) = call(context, http.Get, "/api/line", owner, "")
  clean(owner, ada, path)

  assert saved == 200
  assert string.contains(
    not_yet,
    ines <> ",\"email\":\"ada@example.com\",\"account\":null",
  )
  assert string.contains(
    linked,
    "\"id\":\"pe-ines\",\"name\":\"Augusta Ada King\",\"email\":\"ada@example.com\",\"account\":{\"firstName\":\"Augusta Ada\",\"lastName\":\"King\"}",
  )
  assert string.contains(line, "Augusta Ada King")
}

/// The Account's name can be longer than a name the owner types: the next
/// Design save still passes.
pub fn a_link_to_a_known_account_names_at_once_test() {
  let #(context, owner, ada, path) = setup(True)

  let _ =
    call(
      context,
      http.Put,
      "/api/account",
      ada,
      "{\"firstName\": \"Augusta Ada Byron\", \"lastName\": \"King-Noel Countess of Lovelace\"}",
    )
  let #(_, design) = call(context, http.Get, "/api/design", owner, "")
  let #(saved, body) =
    call(
      context,
      http.Put,
      "/api/design",
      owner,
      with_email_for_ines(design, "ada@example.com"),
    )
  let #(again, _) = call(context, http.Put, "/api/design", owner, body)
  clean(owner, ada, path)

  assert saved == 200
  assert string.contains(
    body,
    "\"id\":\"pe-ines\",\"name\":\"Augusta Ada Byron King-Noel Countess of Lovelace\"",
  )
  assert again == 200
}

pub fn a_wrong_or_shared_email_is_refused_test() {
  let #(context, owner, ada, path) = setup(True)

  let #(_, design) = call(context, http.Get, "/api/design", owner, "")
  let #(wrong, _) =
    call(
      context,
      http.Put,
      "/api/design",
      owner,
      with_email_for_ines(design, "ada"),
    )
  let assert Ok(#(before, after)) =
    string.split_once(
      with_email_for_ines(design, "ada@example.com"),
      "\"name\":\"Marc\",\"email\":\"\"",
    )
  let #(twice, reason) =
    call(
      context,
      http.Put,
      "/api/design",
      owner,
      before <> "\"name\":\"Marc\",\"email\":\"ADA@example.com\"" <> after,
    )
  clean(owner, ada, path)

  assert wrong == 400
  assert twice == 400
  assert reason
    == "Bad request: Two Team Members have the email ada@example.com."
}

pub fn no_line_has_a_reset_test() {
  let #(context, owner, ada, path) = setup(True)

  let #(reset, _) = call_as_admin(context, http.Post, "/api/reset", owner)
  clean(owner, ada, path)

  assert reset == 404
}

pub fn a_new_account_starts_with_an_empty_line_test() {
  let #(context, owner, ada, path) = setup(True)

  let #(_, design) = call(context, http.Get, "/api/design", ada, "")
  clean(owner, ada, path)

  assert string.contains(design, "Team Member 1")
  assert !string.contains(design, "pe-ines")
}

pub fn akadmin_starts_with_an_empty_line_test() {
  let #(context, owner, ada, path) = setup(True)

  let #(_, design) = call_as_admin(context, http.Get, "/api/design", ada)
  clean(owner, ada, path)

  assert string.contains(design, "Team Member 1")
  assert !string.contains(design, "pe-ines")
}

pub fn with_sso_off_nothing_links_test() {
  let #(context, owner, ada, path) = setup(False)

  let #(_, design) = call(context, http.Get, "/api/design", owner, "")
  let #(saved, body) =
    call(
      context,
      http.Put,
      "/api/design",
      owner,
      with_email_for_ines(design, "ada@example.com"),
    )
  let made = simplifile.is_file(path)
  clean(owner, ada, path)

  assert saved == 200
  assert string.contains(body, ines <> ",\"email\":\"\",\"account\":null")
  assert made == Ok(False)
}

pub fn an_spa_without_emails_keeps_the_links_test() {
  let #(context, owner, ada, path) = setup(True)

  let #(_, design) = call(context, http.Get, "/api/design", owner, "")
  let _ =
    call(
      context,
      http.Put,
      "/api/design",
      owner,
      with_email_for_ines(design, "ada@example.com"),
    )
  let #(_, design) = call(context, http.Get, "/api/design", owner, "")
  let older = string.replace(design, ",\"email\":\"ada@example.com\"", "")
  let #(saved, _) = call(context, http.Put, "/api/design", owner, older)
  let kept = emails(path, owner.0)
  clean(owner, ada, path)

  assert saved == 200
  assert kept == [#("pe-ines", "ada@example.com")]
}
