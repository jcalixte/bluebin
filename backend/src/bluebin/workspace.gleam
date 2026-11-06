import gleam/http/request.{type Request}
import gleam/list
import gleam/string

/// The authentik user id. Traefik forward auth copies it from authentik's
/// answer (`authResponseHeaders`) and so replaces any value a client sends.
/// The API trusts it only because no request reaches the container without
/// that middleware.
const header = "x-authentik-uid"

const allowed = "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789-_"

/// The workspace of the signed-in user; a user has one workspace for now.
/// `Error(Nil)` when the header is missing or unsafe as a file name.
pub fn from_request(request: Request(body)) -> Result(String, Nil) {
  case request.get_header(request, header) {
    Ok(uid) ->
      case is_safe(uid) {
        True -> Ok(uid)
        False -> Error(Nil)
      }
    Error(Nil) -> Error(Nil)
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
