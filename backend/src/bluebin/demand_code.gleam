import gleam/list
import gleam/result
import gleam/string

const letters = "ABCDEFGHIJKLMNOPQRSTUVWXYZ"

pub fn propose(label: String, taken: List(String)) -> String {
  let words =
    string.split(string.uppercase(label), " ")
    |> list.map(only_letters)
    |> list.filter(fn(word) { word != "" })
  let base = case words {
    [] -> "DM"
    [word] -> string.slice(word, 0, 3)
    _ -> words |> list.filter_map(string.first) |> string.concat
  }
  let base = case string.length(base) {
    1 -> base <> "D"
    _ -> string.slice(base, 0, 4)
  }
  case list.contains(taken, base) {
    False -> base
    True -> {
      let stem = string.slice(base, 0, 3)
      string.to_graphemes(letters)
      |> list.map(fn(letter) { stem <> letter })
      |> list.find(fn(code) { !list.contains(taken, code) })
      |> result.unwrap(base)
    }
  }
}

pub fn check(code: String) -> Result(String, String) {
  let code = string.uppercase(string.trim(code))
  let length = string.length(code)
  case length >= 2 && length <= 4 && only_letters(code) == code {
    True -> Ok(code)
    False ->
      Error(
        "A Demand Code has 2 to 4 letters, A to Z, like CHK. \""
        <> code
        <> "\" does not.",
      )
  }
}

/// Updates every Piece: add a `where` to limit it to one Demand.
pub const write_references_sql =
  "
update piece
   set reference = (select d.code from demand d where d.id = piece.demand_id)
                   || '-' || number || coalesce(' · ' || branch, '')"

fn only_letters(text: String) -> String {
  string.to_graphemes(text)
  |> list.filter(fn(one) { string.contains(letters, one) })
  |> string.concat
}
