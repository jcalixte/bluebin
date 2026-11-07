import bluebin
import bluebin/access
import bluebin/db
import bluebin/invitations
import bluebin/live
import gleam/http
import gleam/int
import gleam/list
import gleam/option.{None, Some}
import gleam/string
import simplifile
import wisp/simulate

/// Every route inside a Line, as the router knows it. A route added to the
/// router and not to the role table is refused: add it here too.
const routes = [
  #(http.Get, ["api", "events"], access.Read),
  #(http.Get, ["api", "demands"], access.Read),
  #(http.Get, ["api", "line"], access.Read),
  #(http.Get, ["api", "backlog"], access.Read),
  #(http.Get, ["api", "andons"], access.Read),
  #(http.Get, ["api", "team-members"], access.Read),
  #(http.Get, ["api", "team-members", "pe-ines", "next"], access.Read),
  #(http.Get, ["api", "design"], access.Read),
  #(http.Get, ["api", "labels"], access.Read),
  #(http.Get, ["api", "measures"], access.Read),
  #(http.Get, ["api", "calendar"], access.Read),
  #(http.Post, ["api", "demands"], access.Flow),
  #(http.Post, ["api", "backlog", "urgent"], access.Flow),
  #(http.Post, ["api", "pull"], access.Flow),
  #(http.Post, ["api", "finish"], access.Flow),
  #(http.Post, ["api", "deliver"], access.Flow),
  #(http.Post, ["api", "rework"], access.Flow),
  #(http.Post, ["api", "rework", "repair"], access.Flow),
  #(http.Post, ["api", "andon"], access.Flow),
  #(http.Post, ["api", "andon", "close"], access.Flow),
  #(http.Post, ["api", "assign"], access.Flow),
  #(http.Put, ["api"], access.Own),
  #(http.Put, ["api", "sharing"], access.Own),
  #(http.Post, ["api", "team-members"], access.Own),
  #(http.Put, ["api", "design"], access.Own),
  #(http.Put, ["api", "steps", "1"], access.Own),
  #(http.Put, ["api", "calendar"], access.Own),
  #(http.Post, ["api", "reset"], access.Own),
]

pub fn each_route_has_its_need_test() {
  list.each(routes, fn(route) {
    let #(method, segments, need) = route
    assert access.need(method, segments) == Ok(need)
  })
}

pub fn a_route_missing_from_the_table_is_refused_test() {
  assert access.need(http.Get, ["api", "nothing"]) == Error(Nil)
  assert access.need(http.Delete, ["api", "demands"]) == Error(Nil)
  assert access.need(http.Get, ["api", "reset"]) == Error(Nil)
}

/// One check for each role × route.
pub fn each_role_reaches_only_its_routes_test() {
  let roles = [
    #(access.Owner, [access.Read, access.Flow, access.Own]),
    #(access.Member("pe-ines"), [access.Read, access.Flow]),
    #(access.Viewer, [access.Read]),
    #(access.NoRole, []),
  ]
  list.each(roles, fn(pair) {
    let #(role, granted) = pair
    list.each(routes, fn(route) {
      let assert Ok(need) = access.need(route.0, route.1)
      assert access.allows(role, need) == list.contains(granted, need)
    })
  })
}

pub fn a_member_acts_only_as_themselves_test() {
  let member = access.Member("pe-ines")
  let nobody_else = fn(_) { False }
  assert access.actor(member, None, nobody_else) == Ok(Some("pe-ines"))
  assert access.actor(member, Some("pe-ines"), nobody_else)
    == Ok(Some("pe-ines"))
  assert access.actor(member, Some("pe-bob"), nobody_else) == Error(Nil)
  assert access.actor(access.Viewer, None, nobody_else) == Error(Nil)
}

pub fn the_owner_acts_only_for_team_members_with_no_other_account_test() {
  let linked = fn(team_member) { team_member == "pe-ines" }
  assert access.actor(access.Owner, Some("pe-bob"), linked)
    == Ok(Some("pe-bob"))
  assert access.actor(access.Owner, Some("pe-ines"), linked) == Error(Nil)
  assert access.actor(access.Owner, None, linked) == Ok(None)
}

fn random(prefix: String) -> String {
  prefix <> int.to_string(int.random(1_000_000_000))
}

fn remove(path: String) {
  let _ = simplifile.delete_all([path, path <> "-wal", path <> "-shm"])
  Nil
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

/// The first Team Member of the body with no email gets `email`.
fn with_email(design: String, team_member: String, email: String) -> String {
  let assert Ok(#(before, after)) =
    string.split_once(design, "\"id\":\"" <> team_member <> "\"")
  let assert Ok(#(name, rest)) = string.split_once(after, "\"email\":\"\"")
  before
  <> "\"id\":\""
  <> team_member
  <> "\""
  <> name
  <> "\"email\":\""
  <> email
  <> "\""
  <> rest
}

fn first_team_member(design: String) -> String {
  let assert Ok(#(_, after)) =
    string.split_once(design, "\"teamMembers\":[{\"id\":\"")
  let assert Ok(#(id, _)) = string.split_once(after, "\"")
  id
}

fn named(context, who: #(String, String), first: String) {
  let assert #(200, _) =
    call(
      context,
      http.Put,
      "/api/account",
      who,
      "{\"firstName\": \"" <> first <> "\", \"lastName\": \"Test\"}",
    )
  Nil
}

type World {
  World(
    context: bluebin.Context,
    owner: #(String, String),
    ada: #(String, String),
    carol: #(String, String),
    bob: #(String, String),
    other_line: String,
    path: String,
  )
}

/// Ada is Inès in the owner's first Line; Carol is the one Team Member of
/// the owner's other Line; Bob is in no Line of the owner.
fn world(sso: Bool) -> World {
  let path = random("data/access-test-") <> ".db"
  let owner = #(random("access-owner-"), "owner@example.com")
  let ada = #(random("access-ada-"), "ada@example.com")
  let carol = #(random("access-carol-"), "carol@example.com")
  let bob = #(random("access-bob-"), "bob@example.com")
  let assert Ok(Nil) = simplifile.create_directory_all(db.workspaces_directory)
  let on = context(path, True)
  named(on, owner, "Olga")
  named(on, ada, "Ada")
  named(on, carol, "Carol")
  named(on, bob, "Bob")

  let #(_, design) = call(on, http.Get, "/api/design", owner, "")
  let assert #(200, _) =
    call(
      on,
      http.Put,
      "/api/design",
      owner,
      with_email(design, "pe-ines", ada.1),
    )
  let assert #(201, made) =
    call(on, http.Post, "/api/lines", owner, "{\"name\": \"Mobile\"}")
  let assert Ok(#(_, after)) = string.split_once(made, "\"id\":\"")
  let assert Ok(#(other_line, _)) = string.split_once(after, "\"")
  let other = "/api/lines/" <> other_line <> "/design"
  let #(_, design) = call(on, http.Get, other, owner, "")
  let assert #(200, _) =
    call(
      on,
      http.Put,
      other,
      owner,
      with_email(design, first_team_member(design), carol.1),
    )
  World(context(path, sso), owner, ada, carol, bob, other_line, path)
}

fn clean(world: World) {
  remove(world.path)
  let _ =
    simplifile.delete_all([db.workspaces_directory <> "/" <> world.owner.0])
  list.each([world.owner, world.ada, world.carol, world.bob], fn(who) {
    remove(db.workspace_path(who.0))
  })
}

fn in_owner(world: World, line: String, path: String) -> String {
  "/api/w/" <> world.owner.0 <> "/lines/" <> line <> path
}

pub fn a_private_line_is_hidden_from_everyone_else_test() {
  let world = world(True)
  let main = in_owner(world, "main", "/line")
  let #(bob, _) = call(world.context, http.Get, main, world.bob, "")
  let #(carol, _) = call(world.context, http.Get, main, world.carol, "")
  let #(ada, _) = call(world.context, http.Get, main, world.ada, "")
  let #(unknown, _) =
    call(
      world.context,
      http.Get,
      in_owner(world, "ln-0", "/line"),
      world.ada,
      "",
    )
  let #(climbing, _) =
    call(world.context, http.Get, "/api/w/a.db/lines/main/line", world.ada, "")
  clean(world)

  assert bob == 404
  assert carol == 404
  assert ada == 200
  assert unknown == 404
  assert climbing == 404
}

pub fn a_member_does_the_flow_but_not_the_design_test() {
  let world = world(True)
  let at = in_owner(world, "main", _)
  let #(_, design) = call(world.context, http.Get, at("/design"), world.ada, "")
  let #(redesign, _) =
    call(world.context, http.Put, at("/design"), world.ada, design)
  let #(reset, _) = call(world.context, http.Post, at("/reset"), world.ada, "")
  let #(rename, _) =
    call(world.context, http.Put, at(""), world.ada, "{\"name\": \"Mine\"}")
  let #(share, _) =
    call(
      world.context,
      http.Put,
      at("/sharing"),
      world.ada,
      "{\"shared\": true}",
    )
  let #(as_bob, _) =
    call(
      world.context,
      http.Post,
      at("/andon"),
      world.ada,
      "{\"station\": \"ws-web\", \"teamMember\": \"pe-bob\"}",
    )
  let #(as_self, _) =
    call(
      world.context,
      http.Post,
      at("/andon"),
      world.ada,
      "{\"station\": \"ws-web\"}",
    )
  let #(demand, _) =
    call(
      world.context,
      http.Post,
      at("/demands"),
      world.ada,
      "{\"label\": \"Search\", \"client\": \"Retail\", \"dueOn\": \"2099-12-31\", \"pieces\": 2}",
    )
  clean(world)

  assert redesign == 403
  assert reset == 403
  assert rename == 403
  assert share == 403
  assert as_bob == 403
  assert as_self == 204
  assert demand == 201
}

pub fn the_owner_does_not_act_for_a_linked_team_member_test() {
  let world = world(True)
  let #(for_ines, _) =
    call(
      world.context,
      http.Post,
      "/api/andon/close",
      world.owner,
      "{\"station\": \"ws-web\", \"teamMember\": \"pe-ines\"}",
    )
  let #(for_bob, _) =
    call(
      world.context,
      http.Post,
      "/api/andon",
      world.owner,
      "{\"station\": \"ws-web\", \"teamMember\": \"pe-bob\"}",
    )
  clean(world)

  assert for_ines == 403
  assert for_bob == 204
}

pub fn a_shared_line_is_look_only_for_the_workspace_test() {
  let world = world(True)
  let main = in_owner(world, "main", "/line")
  let #(shared, _) =
    call(
      world.context,
      http.Put,
      "/api/lines/main/sharing",
      world.owner,
      "{\"shared\": true}",
    )
  let #(carol, _) = call(world.context, http.Get, main, world.carol, "")
  let #(carol_acts, _) =
    call(
      world.context,
      http.Post,
      in_owner(world, "main", "/andon"),
      world.carol,
      "{\"station\": \"ws-web\"}",
    )
  // Bob is a Team Member in no Line of this Workspace: it does not open.
  let #(bob, _) = call(world.context, http.Get, main, world.bob, "")
  let #(_, menu) =
    call(world.context, http.Get, "/api/workspaces", world.carol, "")
  clean(world)

  assert shared == 200
  assert carol == 200
  assert carol_acts == 403
  assert bob == 404
  assert string.contains(menu, "\"name\":\"Olga Test\",\"own\":false")
  assert string.contains(
    menu,
    "\"id\":\"main\",\"name\":\"Line\",\"shared\":true,\"role\":\"viewer\"",
  )
}

pub fn the_menu_lists_the_lines_of_each_workspace_test() {
  let world = world(True)
  let #(status, menu) =
    call(world.context, http.Get, "/api/workspaces", world.ada, "")
  clean(world)

  assert status == 200
  assert string.contains(menu, "\"owner\":\"" <> world.ada.0 <> "\"")
  assert string.contains(menu, "\"owner\":\"" <> world.owner.0 <> "\"")
  assert string.contains(
    menu,
    "\"shared\":false,\"role\":\"member\",\"teamMember\":\"pe-ines\"",
  )
  // The Private Line where Ada is no Team Member stays out.
  assert !string.contains(menu, world.other_line)
}

pub fn with_sso_off_no_other_workspace_opens_test() {
  let world = world(False)
  let #(ada, _) =
    call(
      world.context,
      http.Get,
      in_owner(world, "main", "/line"),
      world.ada,
      "",
    )
  let #(_, menu) =
    call(world.context, http.Get, "/api/workspaces", world.ada, "")
  let #(share, _) =
    call(
      world.context,
      http.Put,
      "/api/lines/main/sharing",
      world.owner,
      "{\"shared\": true}",
    )
  clean(world)

  assert ada == 404
  assert !string.contains(menu, world.owner.0)
  assert share == 403
}
