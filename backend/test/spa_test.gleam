import bluebin/spa
import gleam/http
import gleam/list
import simplifile
import wisp
import wisp/simulate

const directory = "build/spa-fixture"

fn fixture() -> Nil {
  let assert Ok(_) = simplifile.create_directory_all(directory <> "/assets")
  let assert Ok(_) =
    simplifile.write(directory <> "/index.html", "<div id=\"app\"></div>")
  let assert Ok(_) =
    simplifile.write(directory <> "/assets/index-abc123.js", "console.log(1)")
  Nil
}

fn get(path: String) -> wisp.Response {
  fixture()
  spa.serve(simulate.request(http.Get, path), from: directory, next: fn() {
    wisp.response(418)
  })
}

fn cache_control(response: wisp.Response) -> Result(String, Nil) {
  list.key_find(response.headers, "cache-control")
}

pub fn client_route_gets_index_html_test() {
  let response = get("/team-members/pe-bob")
  assert response.status == 200
  assert simulate.read_body(response) == "<div id=\"app\"></div>"
  assert cache_control(response) == Ok("no-cache")
}

pub fn hashed_asset_is_kept_for_good_test() {
  let response = get("/assets/index-abc123.js")
  assert response.status == 200
  assert simulate.read_body(response) == "console.log(1)"
  assert cache_control(response) == Ok("public, max-age=31536000, immutable")
}

pub fn missing_asset_is_an_uncached_404_test() {
  let response = get("/assets/index-old999.js")
  assert response.status == 404
  assert cache_control(response) == Error(Nil)
}

pub fn api_goes_to_the_next_handler_test() {
  assert get("/api/demands").status == 418
  assert get("/api/nope").status == 418
}

pub fn write_outside_api_goes_to_the_next_handler_test() {
  fixture()
  let response =
    spa.serve(simulate.request(http.Post, "/"), from: directory, next: fn() {
      wisp.response(418)
    })
  assert response.status == 418
}
