import gleam/http/request
import gleam/httpc
import gleam/int
import gleam/result
import gleam/string
import simplifile

/// Nager.Date: free public holiday API, no key. See https://date.nager.at
const api = "https://date.nager.at/api/v3"

/// Under `data/`, the mounted volume, so the cache outlives a redeploy.
pub const directory = "data/holidays"

/// Public holidays rarely change: one call per answer and per month at most.
const max_age_seconds = 2_592_000

pub type Failure {
  /// Nager.Date did not answer.
  Unreachable
  /// Nager.Date answered with this status, as 404 for an unknown country.
  Refused(status: Int)
}

/// What Nager.Date answers to a GET of `path`: its status and body.
pub type Fetch =
  fn(String) -> Result(#(Int, String), Nil)

/// The countries Nager.Date knows, as its JSON.
pub fn countries(
  fetch: Fetch,
  in directory: String,
) -> Result(String, Failure) {
  cached("/AvailableCountries", "countries.json", fetch, directory)
}

/// The public holidays of `country` in `year`, as Nager.Date's JSON.
/// `Error(Nil)` when the year or the country code is not valid.
pub fn public_holidays(
  year: String,
  country: String,
  fetch: Fetch,
  in directory: String,
) -> Result(Result(String, Failure), Nil) {
  use year <- result.try(valid_year(year))
  use country <- result.try(valid_country(country))
  let year = int.to_string(year)
  Ok(cached(
    "/PublicHolidays/" <> year <> "/" <> country,
    year <> "-" <> country <> ".json",
    fetch,
    directory,
  ))
}

fn valid_year(year: String) -> Result(Int, Nil) {
  case int.parse(year) {
    Ok(year) if year >= 1900 && year <= 2100 -> Ok(year)
    _ -> Error(Nil)
  }
}

/// ISO 3166-1 alpha-2, so the code is also safe as a file name.
fn valid_country(country: String) -> Result(String, Nil) {
  let upper = string.uppercase(country)
  let letters = string.to_graphemes(upper)
  let is_letter = fn(letter) {
    string.contains("ABCDEFGHIJKLMNOPQRSTUVWXYZ", letter)
  }
  case letters {
    [a, b] ->
      case is_letter(a) && is_letter(b) {
        True -> Ok(upper)
        False -> Error(Nil)
      }
    _ -> Error(Nil)
  }
}

fn cached(
  path: String,
  file: String,
  fetch: Fetch,
  directory: String,
) -> Result(String, Failure) {
  let file = directory <> "/" <> file
  case fresh(file) {
    Ok(body) -> Ok(body)
    Error(Nil) ->
      case fetch(api <> path) {
        Error(Nil) -> Error(Unreachable)
        Ok(#(200, body)) -> {
          let _ = simplifile.create_directory_all(directory)
          keep(file, body)
          Ok(body)
        }
        Ok(#(status, _)) -> Error(Refused(status))
      }
  }
}

fn fresh(file: String) -> Result(String, Nil) {
  use info <- result.try(
    simplifile.file_info(file) |> result.replace_error(Nil),
  )
  case now_seconds() - info.mtime_seconds < max_age_seconds {
    True -> simplifile.read(file) |> result.replace_error(Nil)
    False -> Error(Nil)
  }
}

/// Writes then renames, so a concurrent read never sees half a file. A failed
/// write only costs one more call next time.
fn keep(file: String, body: String) -> Nil {
  let partial = file <> "." <> int.to_string(unique_integer()) <> ".tmp"
  let _ = {
    use _ <- result.try(simplifile.write(partial, body))
    simplifile.rename(partial, file)
  }
  let _ = simplifile.delete(partial)
  Nil
}

/// A GET to Nager.Date over HTTPS, with the certificate checked.
pub fn http_fetch(url: String) -> Result(#(Int, String), Nil) {
  use request <- result.try(request.to(url))
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

@external(erlang, "erlang", "unique_integer")
fn erlang_unique_integer() -> Int

fn unique_integer() -> Int {
  int.absolute_value(erlang_unique_integer())
}
