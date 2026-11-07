import bluebin
import bluebin/db
import bluebin/demand
import bluebin/invitations
import bluebin/lines
import bluebin/live
import bluebin/workspace
import gleam/erlang/process
import gleam/http
import gleam/http/request
import gleam/int
import gleam/list
import gleam/string
import simplifile
import sqlight
import wisp
import wisp/simulate

fn with_uid(uid: String) {
  request.new() |> request.set_header("x-authentik-uid", uid)
}

pub fn the_workspace_is_the_authentik_uid_test() {
  let uid = "5f2b0c9e1d7a4b3c8e6f0a1b2c3d4e5f5f2b0c9e1d7a4b3c8e6f0a1b2c3d4e5f"
  assert workspace.from_request(with_uid(uid)) == Ok(uid)
}

pub fn no_identity_means_the_public_workspace_test() {
  assert workspace.from_request(request.new()) == Ok(workspace.public)
}

pub fn an_empty_identity_is_refused_test() {
  assert workspace.from_request(with_uid("")) == Error(Nil)
}

pub fn a_uid_cannot_leave_the_workspaces_directory_test() {
  assert workspace.from_request(with_uid("../app")) == Error(Nil)
  assert workspace.from_request(with_uid("a/b")) == Error(Nil)
  assert workspace.from_request(with_uid("a.db")) == Error(Nil)
  assert workspace.from_request(with_uid(string_of(129))) == Error(Nil)
  assert workspace.from_request(with_uid(string_of(128))) == Ok(string_of(128))
}

fn string_of(length: Int) -> String {
  list.repeat("a", length) |> list.fold("", fn(all, one) { all <> one })
}

/// A real file, as the SPA's first load opens one from several processes.
fn scratch_database(name: String) -> String {
  let directory = "build/test-workspaces"
  let assert Ok(Nil) = simplifile.create_directory_all(directory)
  let path =
    directory <> "/" <> name <> int.to_string(int.random(1_000_000)) <> ".db"
  let _ = simplifile.delete_all([path, path <> "-wal", path <> "-shm"])
  path
}

pub fn a_new_workspace_is_ready_after_parallel_first_requests_test() {
  let database = scratch_database("parallel")
  let done = process.new_subject()
  list.repeat(Nil, 8)
  |> list.each(fn(_) {
    process.spawn(fn() { process.send(done, db.ready(database, db.Demo)) })
  })
  list.repeat(Nil, 8)
  |> list.each(fn(_) {
    let assert Ok(Ok(Nil)) = process.receive(done, 10_000)
  })

  use connection <- db.with_connection_at(database)
  let assert Ok(demands) = demand.list_active(connection)
  // Seeded once, not once per request.
  assert list.length(demands) == 3
}

pub fn workspaces_do_not_share_data_test() {
  let ours = scratch_database("ours")
  let theirs = scratch_database("theirs")
  let assert Ok(Nil) = db.ready(ours, db.Demo)
  let assert Ok(Nil) = db.ready(theirs, db.Demo)

  let assert Ok(_) = {
    use connection <- db.with_connection_at(ours)
    sqlight.exec("update demand set state = 'delivered'", connection)
  }

  let assert Ok(left) = {
    use connection <- db.with_connection_at(theirs)
    demand.list_active(connection)
  }
  assert list.length(left) == 3
}

/// The router writes under `data/workspaces`, so each test uses its own uid
/// and removes the file it made.
fn remove_workspace(uid: String) {
  let path = db.workspace_path(uid)
  let _ = simplifile.delete_all([path, path <> "-wal", path <> "-shm"])
  Nil
}

pub fn the_api_refuses_an_unsafe_identity_test() {
  let assert Ok(hub) = live.start()
  let response =
    simulate.request(http.Get, "/api/demands")
    |> simulate.header("x-authentik-uid", "../app")
    |> bluebin.handle_request(sso_off(hub))
  assert response.status == 401
}

pub fn the_healthcheck_needs_no_identity_test() {
  let assert Ok(hub) = live.start()
  let response =
    bluebin.handle_request(
      simulate.request(http.Get, "/api/health"),
      sso_off(hub),
    )
  assert response.status == 200
}

pub fn a_signed_in_user_gets_a_seeded_workspace_test() {
  let assert Ok(hub) = live.start()
  let uid = "router-test-" <> int.to_string(int.random(1_000_000))
  let assert Ok(Nil) = simplifile.create_directory_all(db.workspaces_directory)
  let response =
    simulate.request(http.Get, "/api/demands")
    |> simulate.header("x-authentik-uid", uid)
    |> bluebin.handle_request(sso_off(hub))
  remove_workspace(uid)
  assert response.status == 200
}

fn as_user(
  method: http.Method,
  path: String,
  uid: String,
  body: String,
  hub: live.Hub,
) {
  simulate.request(method, path)
  |> simulate.header("x-authentik-uid", uid)
  |> simulate.string_body(body)
  |> simulate.header("content-type", "application/json")
  |> bluebin.handle_request(sso_off(hub))
}

fn remove_lines(uid: String) {
  remove_workspace(uid)
  let _ = simplifile.delete_all([db.workspaces_directory <> "/" <> uid])
  Nil
}

pub fn an_account_names_and_lists_its_lines_test() {
  let assert Ok(hub) = live.start()
  let uid = "lines-test-" <> int.to_string(int.random(1_000_000))
  let assert Ok(Nil) = simplifile.create_directory_all(db.workspaces_directory)

  let assert Ok(line) = lines.create(uid, "  Mobile  ")
  assert line.name == "Mobile"
  let assert Ok(_) = lines.rename(uid, lines.first, "Web")
  let assert Ok(found) = lines.list(uid, db.Demo)

  let created =
    as_user(http.Post, "/api/lines", uid, "{\"name\": \"Back office\"}", hub)
  let listed = as_user(http.Get, "/api/lines", uid, "", hub)
  remove_lines(uid)

  assert found == [lines.Line(line.id, "Mobile"), lines.Line("main", "Web")]
  assert created.status == 201
  let assert wisp.Text(body) = listed.body
  assert string.contains(body, "\"name\":\"Back office\"")
}

pub fn a_new_line_starts_empty_and_apart_test() {
  let uid = "lines-test-" <> int.to_string(int.random(1_000_000))
  let assert Ok(Nil) = simplifile.create_directory_all(db.workspaces_directory)

  let assert Ok(line) = lines.create(uid, "Mobile")
  let assert Ok(first) = lines.database(uid, lines.first, db.Demo)
  let assert Ok(other) = lines.database(uid, line.id, db.Demo)
  let assert Ok(first_demands) = {
    use connection <- db.with_connection_at(first)
    demand.list_active(connection)
  }
  let assert Ok(other_demands) = {
    use connection <- db.with_connection_at(other)
    demand.list_active(connection)
  }
  remove_lines(uid)

  assert first != other
  assert list.length(first_demands) == 3
  assert other_demands == []
}

pub fn a_line_needs_a_name_test() {
  let uid = "lines-test-" <> int.to_string(int.random(1_000_000))
  assert lines.create(uid, "   ") == Error(lines.EmptyName)
  assert lines.create(uid, string_of(61)) == Error(lines.NameTooLong)
  assert lines.rename(uid, lines.first, "") == Error(lines.EmptyName)
}

pub fn an_unknown_line_is_not_created_test() {
  let assert Ok(hub) = live.start()
  let uid = "lines-test-" <> int.to_string(int.random(1_000_000))
  let unknown = as_user(http.Get, "/api/lines/ln-abc/demands", uid, "", hub)
  let unsafe = as_user(http.Get, "/api/lines/..%2Fapp/demands", uid, "", hub)
  let other_account =
    as_user(http.Put, "/api/lines/ln-abc", uid, "{\"name\": \"Mine\"}", hub)
  remove_lines(uid)

  assert unknown.status == 404
  assert unsafe.status == 404
  assert other_account.status == 404
  assert simplifile.is_file(
      db.workspaces_directory <> "/" <> uid <> "/ln-abc.db",
    )
    == Ok(False)
  assert lines.is_id("main")
  assert lines.is_id("ln-0a1b2c")
  assert !lines.is_id("ln-")
  assert !lines.is_id("ln-XYZ")
  assert !lines.is_id("../main")
}

pub fn the_routes_of_a_line_reach_its_own_data_test() {
  let assert Ok(hub) = live.start()
  let uid = "lines-test-" <> int.to_string(int.random(1_000_000))
  let assert Ok(Nil) = simplifile.create_directory_all(db.workspaces_directory)
  let assert Ok(line) = lines.create(uid, "Mobile")

  let scoped =
    as_user(http.Get, "/api/lines/" <> line.id <> "/demands", uid, "", hub)
  let first = as_user(http.Get, "/api/lines/main/demands", uid, "", hub)
  let bare = as_user(http.Get, "/api/demands", uid, "", hub)
  remove_lines(uid)

  let assert wisp.Text(scoped) = scoped.body
  let assert wisp.Text(first) = first.body
  let assert wisp.Text(bare) = bare.body
  assert scoped != first
  assert first == bare
}

/// A data wipe removes the directory while the server runs.
pub fn a_removed_directory_is_made_again_test() {
  let directory = "data/test-wiped-" <> int.to_string(int.random(1_000_000))
  let path = directory <> "/a.db"
  let _ = simplifile.delete_all([directory])
  let assert Ok(Nil) = db.ready(path, db.Demo)
  let assert Ok(True) = simplifile.is_file(path)
  let _ = simplifile.delete_all([directory])
}

/// No test with SSO off touches the accounts file.
fn sso_off(hub: live.Hub) -> bluebin.Context {
  bluebin.Context(
    hub:,
    sso: False,
    accounts: "data/no-accounts.db",
    invite: fn() { Error(invitations.NoToken) },
  )
}
