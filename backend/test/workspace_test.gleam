import bluebin
import bluebin/db
import bluebin/demand
import bluebin/live
import bluebin/workspace
import gleam/erlang/process
import gleam/http
import gleam/http/request
import gleam/int
import gleam/list
import simplifile
import sqlight
import wisp/simulate

fn with_uid(uid: String) {
  request.new() |> request.set_header("x-authentik-uid", uid)
}

pub fn the_workspace_is_the_authentik_uid_test() {
  let uid = "5f2b0c9e1d7a4b3c8e6f0a1b2c3d4e5f5f2b0c9e1d7a4b3c8e6f0a1b2c3d4e5f"
  assert workspace.from_request(with_uid(uid)) == Ok(uid)
}

pub fn no_identity_means_no_workspace_test() {
  assert workspace.from_request(request.new()) == Error(Nil)
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
    process.spawn(fn() { process.send(done, db.ready(database)) })
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
  let assert Ok(Nil) = db.ready(ours)
  let assert Ok(Nil) = db.ready(theirs)

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

pub fn the_api_refuses_a_request_without_identity_test() {
  let assert Ok(hub) = live.start()
  let response =
    bluebin.handle_request(simulate.request(http.Get, "/api/demands"), hub)
  assert response.status == 401
}

pub fn the_healthcheck_needs_no_identity_test() {
  let assert Ok(hub) = live.start()
  let response =
    bluebin.handle_request(simulate.request(http.Get, "/api/health"), hub)
  assert response.status == 200
}

pub fn a_signed_in_user_gets_a_seeded_workspace_test() {
  let assert Ok(hub) = live.start()
  let uid = "router-test-" <> int.to_string(int.random(1_000_000))
  let assert Ok(Nil) = simplifile.create_directory_all(db.workspaces_directory)
  let response =
    simulate.request(http.Get, "/api/demands")
    |> simulate.header("x-authentik-uid", uid)
    |> bluebin.handle_request(hub)
  remove_workspace(uid)
  assert response.status == 200
}
