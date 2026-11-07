import bluebin/db
import bluebin/text
import gleam/dynamic/decode
import gleam/int
import gleam/list
import gleam/order
import gleam/result
import gleam/string
import simplifile
import sqlight

/// The Line every account has from its first request. Its data stays
/// in the file the account had when it could own only one Line.
pub const first = "main"

/// The other Lines: this prefix and lowercase hex digits only, so an
/// id is always a safe file name.
const prefix = "ln-"

const hex_digits = "0123456789abcdef"

pub const max_name_length = 60

pub type Line {
  Line(id: String, name: String)
}

pub type LineError {
  EmptyName
  NameTooLong
  UnknownLine
  StoreFailed
}

pub fn is_id(line: String) -> Bool {
  case line == first, string.starts_with(line, prefix) {
    True, _ -> True
    False, True -> {
      let digits = string.drop_start(line, string.length(prefix))
      let length = string.length(digits)
      length > 0
      && length <= 32
      && list.all(string.to_graphemes(digits), string.contains(hex_digits, _))
    }
    False, False -> False
  }
}

/// `workspace` must be a checked identity (see `bluebin/workspace`) and
/// `line` a checked id (`is_id`): both become part of a file path.
fn path(workspace: String, line: String) -> String {
  case line == first {
    True -> db.workspace_path(workspace)
    False -> directory(workspace) <> "/" <> line <> ".db"
  }
}

fn directory(workspace: String) -> String {
  db.workspaces_directory <> "/" <> workspace
}

/// The ready database of one Line of the workspace. The first Value
/// Line is made on demand from `start`; any other must exist, so an unknown
/// id never creates a file.
pub fn database(
  workspace: String,
  line: String,
  start: db.Start,
) -> Result(String, LineError) {
  open(workspace, line, start, fn(_) { Ok(path(workspace, line)) })
}

/// Like `database`, then `run` on the same connection.
fn open(
  workspace: String,
  line: String,
  start: db.Start,
  run: fn(sqlight.Connection) -> Result(a, LineError),
) -> Result(a, LineError) {
  use <- guard_known(workspace, line)
  db.open(path(workspace, line), start, fn(_) { StoreFailed }, run)
}

/// Never makes a file: a link into another Workspace must not create it.
pub fn exists(workspace: String, line: String) -> Bool {
  is_id(line) && simplifile.is_file(path(workspace, line)) == Ok(True)
}

fn guard_known(
  workspace: String,
  line: String,
  next: fn() -> Result(a, LineError),
) -> Result(a, LineError) {
  case is_id(line) {
    False -> Error(UnknownLine)
    True if line == first -> next()
    True ->
      case simplifile.is_file(path(workspace, line)) {
        Ok(True) -> next()
        _ -> Error(UnknownLine)
      }
  }
}

/// Every Line of the workspace, by name. Makes the first one from `start`
/// when it is new.
pub fn list(
  workspace: String,
  start: db.Start,
) -> Result(List(Line), LineError) {
  let others =
    simplifile.read_directory(directory(workspace))
    // No directory yet: the account has only its first Line.
    |> result.unwrap([])
    |> list.filter_map(fn(file) {
      case string.ends_with(file, ".db") {
        False -> Error(Nil)
        True -> {
          let id = string.drop_end(file, 3)
          case id != first && is_id(id) {
            True -> Ok(id)
            False -> Error(Nil)
          }
        }
      }
    })

  [first, ..others]
  |> list.try_map(fn(id) {
    use connection <- open(workspace, id, start)
    use name <- result.map(name_of(connection))
    Line(id:, name:)
  })
  |> result.map(list.sort(_, by_name))
}

fn by_name(one: Line, other: Line) -> order.Order {
  string.compare(string.lowercase(one.name), string.lowercase(other.name))
  |> order.break_tie(string.compare(one.id, other.id))
}

fn name_of(connection: sqlight.Connection) -> Result(String, LineError) {
  case
    sqlight.query(
      "select name from line_label where id = 1",
      on: connection,
      with: [],
      expecting: decode.field(0, decode.string, decode.success),
    )
  {
    Ok([name, ..]) -> Ok(name)
    _ -> Error(StoreFailed)
  }
}

/// A new Line starts empty: one Work Station and one Team Member.
pub fn create(workspace: String, name: String) -> Result(Line, LineError) {
  use name <- result.try(check_name(name))
  let id = prefix <> random_hex()
  let path = path(workspace, id)
  let made = {
    use _ <- result.try(
      simplifile.create_directory_all(directory(workspace))
      |> result.replace_error(Nil),
    )
    use _ <- result.try(db.ready(path, db.Empty) |> result.replace_error(Nil))
    use connection <- db.with_connection_at(path)
    save_name(connection, name)
  }
  case made {
    Ok(Nil) -> Ok(Line(id:, name:))
    Error(Nil) -> {
      // A half-made file would show in the list with no name given.
      let _ = simplifile.delete_all([path, path <> "-wal", path <> "-shm"])
      Error(StoreFailed)
    }
  }
}

pub fn rename(
  workspace: String,
  line: String,
  name: String,
) -> Result(Line, LineError) {
  use name <- result.try(check_name(name))
  use database <- result.try(database(workspace, line, db.Empty))
  use connection <- db.with_connection_at(database)
  save_name(connection, name)
  |> result.replace(Line(id: line, name:))
  |> result.replace_error(StoreFailed)
}

fn save_name(connection: sqlight.Connection, name: String) -> Result(Nil, Nil) {
  sqlight.query(
    "update line_label set name = ?1 where id = 1",
    on: connection,
    with: [sqlight.text(name)],
    expecting: decode.success(Nil),
  )
  |> result.replace(Nil)
  |> result.replace_error(Nil)
}

fn check_name(name: String) -> Result(String, LineError) {
  text.check(name, max_name_length)
  |> result.map_error(fn(error) {
    case error {
      text.Empty -> EmptyName
      text.TooLong -> NameTooLong
    }
  })
}

/// 48 random bits: the ids live in one account's directory, so they only
/// need to differ from the few others there.
fn random_hex() -> String {
  int.random(0x1000000000000)
  |> int.to_base16
  |> string.lowercase
  |> string.pad_start(to: 12, with: "0")
}

/// The live channel of one Line: two Lines, of one account or
/// of two, never wake each other's screens.
pub fn channel(workspace: String, line: String) -> String {
  workspace <> "/" <> line
}
