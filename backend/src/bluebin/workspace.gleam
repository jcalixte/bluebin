import gleam/http/request.{type Request}
import gleam/list
import gleam/string

/// Traefik forward auth copies it from authentik's answer
/// (`authResponseHeaders`) and so replaces any value a client sends.
/// With SSO off, nothing replaces it: the header then only picks a file.
const header = "x-authentik-uid"

/// The Workspace of a request without an identity, shared by everyone while
/// SSO is off. Not hex, so no authentik uid can collide with it.
pub const anonymous = "anonymous"

const allowed =
  "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789-_"

/// The caller's own Workspace. Another owner's comes from the URL (`parse`),
/// behind the guard of `bluebin/access`.
pub fn from_request(request: Request(body)) -> Result(String, Nil) {
  case request.get_header(request, header) {
    Ok(uid) ->
      case is_safe(uid) {
        True -> Ok(uid)
        False -> Error(Nil)
      }
    Error(Nil) -> Ok(anonymous)
  }
}

/// The owner's uid in a URL (H12), checked like the header: it names a
/// directory.
pub fn parse(uid: String) -> Result(String, Nil) {
  case is_safe(uid) {
    True -> Ok(uid)
    False -> Error(Nil)
  }
}

/// authentik uids are hex digests; anything outside `[A-Za-z0-9_-]` could
/// climb out of the workspaces directory.
fn is_safe(uid: String) -> Bool {
  let characters = string.to_graphemes(uid)
  let length = list.length(characters)
  let known = list.all(characters, string.contains(allowed, _))
  length > 0 && length <= 128 && known
}
