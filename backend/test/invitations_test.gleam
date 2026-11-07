import bluebin
import bluebin/invitations
import bluebin/live
import gleam/http
import gleam/http/request
import gleam/list
import gleam/option.{None, Some}
import gleam/string
import simplifile
import wisp/simulate

const flow_answer = "{\"pk\": \"f10f10f1-0000-4000-8000-000000000001\", \"slug\": \"bluebin-invitation\"}"

const invitation_answer = "{\"pk\": \"dee58273-8435-43de-a789-1a7f3de09497\", \"name\": \"bluebin-x\"}"

/// A fake authentik: answers the flow lookup, then the new invitation.
fn authentik(request: request.Request(String)) -> Result(#(Int, String), Nil) {
  case request.method, request.path {
    http.Get, "/api/v3/flows/instances/bluebin-invitation/" ->
      Ok(#(200, flow_answer))
    http.Post, "/api/v3/stages/invitation/invitations/" ->
      Ok(#(201, invitation_answer))
    _, _ -> Ok(#(404, ""))
  }
}

pub fn an_invitation_is_a_single_use_link_to_the_bluebin_flow_test() {
  let assert Ok(invitation) = invitations.create("secret", authentik, 0)
  assert invitation.link
    == "https://auth.apoena.dev/if/flow/bluebin-invitation/?itoken=dee58273-8435-43de-a789-1a7f3de09497"
  assert invitation.expires == "1970-01-08T00:00:00Z"
}

pub fn the_invitation_names_the_flow_and_carries_the_token_test() {
  let send = fn(request: request.Request(String)) {
    case request.method {
      http.Post -> {
        assert request.get_header(request, "authorization")
          == Ok("Bearer secret")
        assert string.contains(
          request.body,
          "\"flow\":\"f10f10f1-0000-4000-8000-000000000001\"",
        )
        assert string.contains(request.body, "\"single_use\":true")
        assert string.contains(request.body, "\"name\":\"bluebin-")
      }
      _ -> Nil
    }
    authentik(request)
  }
  let assert Ok(_) = invitations.create("secret", send, 0)
}

pub fn a_refusal_from_authentik_is_reported_test() {
  let refused = fn(_) { Ok(#(403, "{\"detail\": \"no permission\"}")) }
  assert invitations.create("secret", refused, 0)
    == Error(invitations.Refused(403))
  assert invitations.create("secret", fn(_) { Error(Nil) }, 0)
    == Error(invitations.Unreachable)
  assert invitations.invite(None, authentik)() == Error(invitations.NoToken)
}

fn call(context: bluebin.Context, headers: List(#(String, String))) {
  headers
  |> list.fold(
    simulate.request(http.Post, "/api/invitations"),
    fn(request, header) { simulate.header(request, header.0, header.1) },
  )
  |> bluebin.handle_request(context)
}

fn context(sso: Bool, path: String) {
  let assert Ok(hub) = live.start()
  bluebin.Context(
    hub:,
    sso:,
    accounts: path,
    invite: invitations.invite(Some("secret"), authentik),
  )
}

fn signed_in(username: String) {
  [
    #("x-authentik-uid", "a1b2c3"),
    #("x-authentik-email", "ada@example.com"),
    #("x-authentik-username", username),
  ]
}

pub fn only_akadmin_makes_an_invitation_test() {
  let path = "data/accounts-invitations-test.db"
  let response = call(context(True, path), signed_in("akadmin"))
  assert response.status == 201
  assert string.contains(
    simulate.read_body(response),
    "\"link\":\"https://auth.apoena.dev/if/flow/bluebin-invitation/?itoken=dee58273-8435-43de-a789-1a7f3de09497\"",
  )

  assert call(context(True, path), signed_in("ada")).status == 403
  // With SSO off any client can send the header.
  assert call(context(False, path), signed_in("akadmin")).status == 403
  let _ = simplifile.delete_all([path, path <> "-wal", path <> "-shm"])
}

fn account(context: bluebin.Context, username: String) -> String {
  signed_in(username)
  |> list.fold(simulate.request(http.Get, "/api/account"), fn(request, header) {
    simulate.header(request, header.0, header.1)
  })
  |> bluebin.handle_request(context)
  |> simulate.read_body
}

pub fn the_account_tells_the_spa_who_is_admin_test() {
  let path = "data/accounts-admin-test.db"
  assert string.contains(
    account(context(True, path), "akadmin"),
    "\"admin\":true",
  )
  assert string.contains(account(context(True, path), "ada"), "\"admin\":false")
  let _ = simplifile.delete_all([path, path <> "-wal", path <> "-shm"])
}
