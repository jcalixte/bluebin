import gleam/http
import gleam/option.{None}
import simplifile
import wisp

/// Serves the built SPA from `directory` for every `GET` outside `/api`.
/// A path that is no file gets `index.html`, so a client route survives a
/// reload; a missing asset stays a 404, never an HTML page with a JS type.
pub fn serve(
  request: wisp.Request,
  from directory: String,
  next handler: fn() -> wisp.Response,
) -> wisp.Response {
  case request.method, wisp.path_segments(request) {
    _, ["api", ..] -> handler()
    http.Get, ["assets", ..] ->
      {
        use <- wisp.serve_static(request, under: "/", from: directory)
        wisp.not_found()
      }
      // Vite puts a content hash in every asset name, so a new build never
      // reuses a URL and the browser can keep each one for good.
      |> cache("public, max-age=31536000, immutable")
    http.Get, _ ->
      {
        use <- wisp.serve_static(request, under: "/", from: directory)
        index(directory)
      }
      |> cache("no-cache")
    _, _ -> handler()
  }
}

fn index(directory: String) -> wisp.Response {
  let path = directory <> "/index.html"
  case simplifile.is_file(path) {
    Ok(True) ->
      wisp.ok()
      |> wisp.set_header("content-type", "text/html; charset=utf-8")
      |> wisp.set_body(wisp.File(path:, offset: 0, limit: None))
    _ -> wisp.not_found()
  }
}

/// Only a found file is worth keeping: a cached 404 would outlive the fix.
fn cache(response: wisp.Response, policy: String) -> wisp.Response {
  case response.status {
    200 | 304 -> wisp.set_header(response, "cache-control", policy)
    _ -> response
  }
}
