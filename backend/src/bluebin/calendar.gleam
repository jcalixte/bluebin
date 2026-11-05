import gleam/dynamic/decode
import gleam/int
import gleam/json
import gleam/list
import gleam/result
import gleam/set.{type Set}
import gleam/string
import sqlight

/// The Working Calendar of the Value Stream. `days` uses `strftime('%w')`
/// numbers, 0 for Sunday; `start` and `end` are minutes after midnight, UTC.
pub type Calendar {
  Calendar(days: List(Int), start: Int, end: Int, holidays: List(Holiday))
}

/// `index` is the day number since 1970-01-01, the unit of `working_seconds`.
pub type Holiday {
  Holiday(day: String, label: String, index: Int)
}

/// SQL condition on a `day` column: a working day of the Working Calendar.
pub const working_day_sql = "instr((select days from working_calendar), strftime('%w', day)) > 0
     and day not in (select day from holiday)"

pub fn load(connection: sqlight.Connection) -> Result(Calendar, sqlight.Error) {
  use rows <- result.try(
    sqlight.query(
      "select days, day_start, day_end from working_calendar where id = 1",
      on: connection,
      with: [],
      expecting: {
        use days <- decode.field(0, decode.string)
        use start <- decode.field(1, decode.string)
        use end <- decode.field(2, decode.string)
        decode.success(#(days, start, end))
      },
    ),
  )
  use holidays <- result.try(
    sqlight.query(
      "select day, label, cast(strftime('%s', day) as integer) / 86400
       from holiday order by day",
      on: connection,
      with: [],
      expecting: {
        use day <- decode.field(0, decode.string)
        use label <- decode.field(1, decode.string)
        use index <- decode.field(2, decode.int)
        decode.success(Holiday(day:, label:, index:))
      },
    ),
  )
  let #(days, start, end) = case rows {
    [row, ..] -> row
    [] -> #("12345", "09:00", "16:00")
  }
  Ok(Calendar(
    days: string.to_graphemes(days) |> list.filter_map(int.parse),
    start: parse_time(start) |> result.unwrap(0),
    end: parse_time(end) |> result.unwrap(0),
    holidays:,
  ))
}

pub type Invalid {
  Invalid(String)
  StoreFailed
}

/// Replaces the Working Calendar in one transaction. Holiday indexes are
/// ignored: the store computes them.
pub fn save(
  connection: sqlight.Connection,
  calendar: Calendar,
) -> Result(Nil, Invalid) {
  use _ <- result.try(validate(calendar))
  let days =
    calendar.days
    |> list.unique
    |> list.sort(int.compare)
    |> list.map(int.to_string)
    |> string.concat
  let run = fn(sql, values) {
    sqlight.query(sql, on: connection, with: values, expecting: decode.dynamic)
    |> result.replace_error(StoreFailed)
  }
  use _ <- result.try(
    sqlight.exec("begin immediate;", connection)
    |> result.replace_error(StoreFailed),
  )
  let saved = {
    use _ <- result.try(
      run(
        "insert or replace into working_calendar (id, days, day_start, day_end)
       values (1, ?1, ?2, ?3)",
        [
          sqlight.text(days),
          sqlight.text(format_time(calendar.start)),
          sqlight.text(format_time(calendar.end)),
        ],
      ),
    )
    use _ <- result.try(run("delete from holiday", []))
    list.try_each(calendar.holidays, fn(holiday) {
      use inserted <- result.try(
        run(
          "insert or replace into holiday (day, label)
         select ?1, ?2 where date(?1) is ?1
         returning day",
          [sqlight.text(holiday.day), sqlight.text(string.trim(holiday.label))],
        ),
      )
      case inserted {
        [] -> Error(Invalid("A holiday needs a date like 2026-12-25."))
        _ -> Ok(Nil)
      }
    })
  }
  case saved {
    Ok(Nil) ->
      sqlight.exec("commit;", connection) |> result.replace_error(StoreFailed)
    Error(failure) -> {
      let _ = sqlight.exec("rollback;", connection)
      Error(failure)
    }
  }
}

fn validate(calendar: Calendar) -> Result(Nil, Invalid) {
  case calendar {
    Calendar(days: [], ..) -> Error(Invalid("Choose at least one working day."))
    Calendar(start:, end:, ..) if start >= end ->
      Error(Invalid("The working day must end after it starts."))
    _ ->
      case list.all(calendar.days, fn(day) { day >= 0 && day <= 6 }) {
        True -> Ok(Nil)
        False ->
          Error(Invalid("A working day is a number from 0 (Sunday) to 6."))
      }
  }
}

/// The Working Time between two Unix times, in seconds.
pub fn working_seconds(calendar: Calendar, from: Int, to: Int) -> Int {
  case to <= from {
    True -> 0
    False -> {
      let days = set.from_list(calendar.days)
      let holidays =
        calendar.holidays
        |> list.map(fn(holiday) { holiday.index })
        |> set.from_list
      sum_days(calendar, days, holidays, from, to, floor_day(from), 0)
    }
  }
}

fn sum_days(
  calendar: Calendar,
  days: Set(Int),
  holidays: Set(Int),
  from: Int,
  to: Int,
  day: Int,
  total: Int,
) -> Int {
  let midnight = day * 86_400
  case midnight >= to {
    True -> total
    False -> {
      // 1970-01-01 was a Thursday, day 4 in `strftime('%w')` numbers.
      let weekday = int.modulo(day + 4, 7) |> result.unwrap(0)
      let counted = case
        set.contains(days, weekday) && !set.contains(holidays, day)
      {
        False -> 0
        True ->
          int.max(
            0,
            int.min(to, midnight + calendar.end * 60)
              - int.max(from, midnight + calendar.start * 60),
          )
      }
      sum_days(calendar, days, holidays, from, to, day + 1, total + counted)
    }
  }
}

fn floor_day(seconds: Int) -> Int {
  int.floor_divide(seconds, 86_400) |> result.unwrap(0)
}

/// "09:30" is 570 minutes after midnight.
pub fn parse_time(text: String) -> Result(Int, Nil) {
  case string.split(text, ":") {
    [hours, minutes] -> {
      use hours <- result.try(int.parse(hours))
      use minutes <- result.try(int.parse(minutes))
      let total = hours * 60 + minutes
      case hours >= 0 && minutes >= 0 && minutes < 60 && total <= 1440 {
        True -> Ok(total)
        False -> Error(Nil)
      }
    }
    _ -> Error(Nil)
  }
}

pub fn format_time(minutes: Int) -> String {
  let pad = fn(value) { string.pad_start(int.to_string(value), 2, "0") }
  pad(minutes / 60) <> ":" <> pad(minutes % 60)
}

pub fn decoder() -> decode.Decoder(Calendar) {
  let time = {
    use text <- decode.then(decode.string)
    case parse_time(text) {
      Ok(minutes) -> decode.success(minutes)
      Error(Nil) -> decode.failure(0, "a time like 09:00")
    }
  }
  use days <- decode.field("days", decode.list(decode.int))
  use start <- decode.field("start", time)
  use end <- decode.field("end", time)
  use holidays <- decode.optional_field(
    "holidays",
    [],
    decode.list({
      use day <- decode.field("day", decode.string)
      use label <- decode.optional_field("label", "", decode.string)
      decode.success(Holiday(day:, label:, index: 0))
    }),
  )
  decode.success(Calendar(days:, start:, end:, holidays:))
}

pub fn to_json(calendar: Calendar) -> json.Json {
  json.object([
    #("days", json.array(calendar.days, json.int)),
    #("start", json.string(format_time(calendar.start))),
    #("end", json.string(format_time(calendar.end))),
    #(
      "holidays",
      json.array(calendar.holidays, fn(holiday) {
        json.object([
          #("day", json.string(holiday.day)),
          #("label", json.string(holiday.label)),
        ])
      }),
    ),
  ])
}
