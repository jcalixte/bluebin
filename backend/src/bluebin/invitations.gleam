import gleam/dynamic/decode
import gleam/erlang/atom.{type Atom}
import gleam/erlang/charlist.{type Charlist}
import gleam/http
import gleam/http/request.{type Request}
import gleam/httpc
import gleam/json
import gleam/option.{type Option, None, Some}
import gleam/result
import wisp

/// The authentik that signs people in to Bluebin (ADR-0003).
const authentik = "https://auth.bluebin.app"

/// The sign-up flow of `authentik/bluebin-invitation.yaml`.
const flow = "bluebin-invitation"

/// Only authentik's own administrator invites people.
const admin = "akadmin"

/// Traefik forward auth copies it from authentik's answer, so it is trusted
/// only while SSO is on (ADR-0003).
const username_header = "x-authentik-username"

/// A week: time to read the message, and a forgotten link dies soon.
const lifetime_seconds = 604_800

pub type Invitation {
  /// `expires` is RFC 3339, in UTC.
  Invitation(link: String, expires: String)
}

pub type Failure {
  /// `AUTHENTIK_TOKEN` is not set.
  NoToken
  Unreachable
  /// authentik answered with this status, as 403 when the token lacks a permission.
  Refused(status: Int)
  UnknownAnswer
}

/// Sends a request to authentik and gives its status and body.
pub type Send =
  fn(Request(String)) -> Result(#(Int, String), Nil)

pub type Invite =
  fn() -> Result(Invitation, Failure)

pub fn is_admin(request: Request(body)) -> Bool {
  request.get_header(request, username_header) == Ok(admin)
}

/// `token` is an authentik API token allowed to view flows and add invitations.
pub fn invite(token: Option(String), send: Send) -> Invite {
  fn() {
    case token {
      None -> Error(NoToken)
      Some(token) -> create(token, send, now_seconds())
    }
  }
}

/// `now` is in Unix seconds.
pub fn create(
  token: String,
  send: Send,
  now: Int,
) -> Result(Invitation, Failure) {
  use flow_pk <- result.try(call(
    token,
    send,
    http.Get,
    "/api/v3/flows/instances/" <> flow <> "/",
    "",
  ))
  let expires = rfc3339(now + lifetime_seconds)
  let body =
    json.object([
      // authentik wants a unique name of letters, digits, - and _.
      #("name", json.string("bluebin-" <> wisp.random_string(16))),
      #("flow", json.string(flow_pk)),
      #("single_use", json.bool(True)),
      #("expires", json.string(expires)),
    ])
    |> json.to_string
  use invitation_pk <- result.try(call(
    token,
    send,
    http.Post,
    "/api/v3/stages/invitation/invitations/",
    body,
  ))
  Ok(Invitation(
    link: authentik <> "/if/flow/" <> flow <> "/?itoken=" <> invitation_pk,
    expires:,
  ))
}

/// The `pk` of the object authentik answers with.
fn call(
  token: String,
  send: Send,
  method: http.Method,
  path: String,
  body: String,
) -> Result(String, Failure) {
  let assert Ok(request) = request.to(authentik <> path)
  let request =
    request
    |> request.set_method(method)
    |> request.set_header("authorization", "Bearer " <> token)
    |> request.set_header("accept", "application/json")
    |> request.set_header("content-type", "application/json")
    |> request.set_body(body)
  case send(request) {
    Error(Nil) -> Error(Unreachable)
    Ok(#(status, body)) if status == 200 || status == 201 ->
      json.parse(body, decode.at(["pk"], decode.string))
      |> result.replace_error(UnknownAnswer)
    Ok(#(status, _)) -> Error(Refused(status))
  }
}

/// Over HTTPS, with the certificate checked.
pub fn http_send(request: Request(String)) -> Result(#(Int, String), Nil) {
  httpc.configure()
  |> httpc.timeout(10_000)
  |> httpc.dispatch(request)
  |> result.map(fn(response) { #(response.status, response.body) })
  |> result.replace_error(Nil)
}

type TimeUnit {
  Second
}

@external(erlang, "os", "system_time")
fn system_time(unit: TimeUnit) -> Int

fn now_seconds() -> Int {
  system_time(Second)
}

@external(erlang, "calendar", "system_time_to_rfc3339")
fn system_time_to_rfc3339(
  seconds: Int,
  options: List(#(Atom, Charlist)),
) -> Charlist

fn rfc3339(seconds: Int) -> String {
  system_time_to_rfc3339(seconds, [
    #(atom.create("offset"), charlist.from_string("Z")),
  ])
  |> charlist.to_string
}
