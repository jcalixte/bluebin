import gleam/string

pub type TextError {
  Empty
  TooLong
}

pub fn check(text: String, max: Int) -> Result(String, TextError) {
  let trimmed = string.trim(text)
  case trimmed == "", string.length(trimmed) > max {
    True, _ -> Error(Empty)
    _, True -> Error(TooLong)
    False, False -> Ok(trimmed)
  }
}
