import bluebin/holidays
import gleam/dynamic.{type Dynamic}
import gleam/int
import gleam/string
import simplifile

const france = "[{\"date\":\"2026-01-01\",\"localName\":\"Jour de l'an\"}]"

/// A cache directory of its own, so the tests never share a file.
fn fresh_directory() -> String {
  let directory =
    "build/test-holidays/" <> int.to_string(int.absolute_value(unique()))
  let _ = simplifile.delete(directory)
  directory
}

@external(erlang, "erlang", "unique_integer")
fn unique() -> Int

fn answering(body: String) -> holidays.Fetch {
  fn(_url) { Ok(#(200, body)) }
}

fn unreachable(_url: String) -> Result(#(Int, String), Nil) {
  Error(Nil)
}

pub fn the_second_ask_is_served_from_the_cache_test() {
  let directory = fresh_directory()
  assert holidays.public_holidays("2026", "FR", answering(france), directory)
    == Ok(Ok(france))
  assert holidays.public_holidays("2026", "FR", unreachable, directory)
    == Ok(Ok(france))
}

pub fn the_cache_asks_nager_date_for_the_year_and_country_test() {
  let directory = fresh_directory()
  let fetch = fn(url) {
    case string.ends_with(url, "/api/v3/PublicHolidays/2026/FR") {
      True -> Ok(#(200, france))
      False -> Ok(#(404, ""))
    }
  }
  assert holidays.public_holidays("2026", "fr", fetch, directory)
    == Ok(Ok(france))
}

pub fn each_year_and_country_has_its_own_entry_test() {
  let directory = fresh_directory()
  let _ = holidays.public_holidays("2026", "FR", answering(france), directory)
  assert holidays.public_holidays("2027", "FR", unreachable, directory)
    == Ok(Error(holidays.Unreachable))
  assert holidays.public_holidays("2026", "DE", unreachable, directory)
    == Ok(Error(holidays.Unreachable))
}

pub fn a_refusal_is_not_cached_test() {
  let directory = fresh_directory()
  let refusing = fn(_url) { Ok(#(404, "")) }
  assert holidays.public_holidays("2026", "XX", refusing, directory)
    == Ok(Error(holidays.Refused(404)))
  assert holidays.public_holidays("2026", "XX", answering("[]"), directory)
    == Ok(Ok("[]"))
}

pub fn an_entry_older_than_a_month_is_asked_again_test() {
  let directory = fresh_directory()
  let _ = holidays.countries(answering("[\"old\"]"), directory)
  let _ =
    change_time(directory <> "/countries.json", #(#(2000, 1, 1), #(0, 0, 0)))
  assert holidays.countries(answering("[\"new\"]"), directory)
    == Ok("[\"new\"]")
}

@external(erlang, "file", "change_time")
fn change_time(
  file: String,
  time: #(#(Int, Int, Int), #(Int, Int, Int)),
) -> Dynamic

pub fn a_bad_year_or_country_never_reaches_nager_date_test() {
  let directory = fresh_directory()
  let fetch = answering(france)
  assert holidays.public_holidays("20x6", "FR", fetch, directory) == Error(Nil)
  assert holidays.public_holidays("1066", "FR", fetch, directory) == Error(Nil)
  assert holidays.public_holidays("2026", "FRA", fetch, directory) == Error(Nil)
  assert holidays.public_holidays("2026", "..", fetch, directory) == Error(Nil)
}
