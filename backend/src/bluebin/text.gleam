import gleam/string

pub type TextError {
  Empty
  TooLong
}

/// The trimmed `text`, when it is neither empty nor longer than `max`
/// characters.
pub fn check(text: String, max: Int) -> Result(String, TextError) {
  let trimmed = string.trim(text)
  case trimmed == "", string.length(trimmed) > max {
    True, _ -> Error(Empty)
    _, True -> Error(TooLong)
    False, False -> Ok(trimmed)
  }
}
