import gleam/dynamic/decode
import gleam/int
import gleam/json
import gleam/list
import gleam/result
import gleam/set.{type Set}
import gleam/string
import sqlight

/// The Working Calendar of the Line. `days` uses `strftime('%w')`
/// numbers, 0 for Sunday; `start` and `end` are minutes after midnight, UTC.
pub type Calendar {
  Calendar(days: List(Int), start: Int, end: Int, holidays: List(Holiday))
}

/// `index` is the day number since 1970-01-01, the unit of `working_seconds`.
pub type Holiday {
  Holiday(day: String, label: String, index: Int)
}

/// SQL condition on a `day` column: a working day of the Working Calendar.
pub const working_day_sql =
  "instr((select days from working_calendar), strftime('%w', day)) > 0
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

/// Holiday indexes are ignored: the store computes them.
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
      let counted = case
        set.contains(days, weekday(day)) && !set.contains(holidays, day)
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

/// 1970-01-01 was a Thursday, day 4 in `strftime('%w')` numbers.
fn weekday(day: Int) -> Int {
  int.modulo(day + 4, 7) |> result.unwrap(0)
}

/// `day` counts days since 1970-01-01, like `Holiday.index`.
pub fn is_working_day(calendar: Calendar, day: Int) -> Bool {
  list.contains(calendar.days, weekday(day))
  && !list.any(calendar.holidays, fn(holiday) { holiday.index == day })
}

/// The `count`-th working day after `day`, which itself does not count; `day`
/// when `count` is 0. Error past `limit`, so a slow pace cannot search for
/// ever.
pub fn add_working_days(
  calendar: Calendar,
  day: Int,
  count: Int,
  limit: Int,
) -> Result(Int, Nil) {
  case count <= 0, day >= limit {
    True, _ -> Ok(day)
    False, True -> Error(Nil)
    False, False -> {
      let next = day + 1
      case is_working_day(calendar, next) {
        True -> add_working_days(calendar, next, count - 1, limit)
        False -> add_working_days(calendar, next, count, limit)
      }
    }
  }
}

/// The working days after `from` up to `to` included; negative when `to`
/// comes first.
pub fn working_days_between(calendar: Calendar, from: Int, to: Int) -> Int {
  case to < from {
    True -> 0 - working_days_between(calendar, to, from)
    False -> count_working_days(calendar, from + 1, to, 0)
  }
}

fn count_working_days(calendar: Calendar, day: Int, last: Int, total: Int) {
  case day > last {
    True -> total
    False ->
      count_working_days(
        calendar,
        day + 1,
        last,
        case is_working_day(calendar, day) {
          True -> total + 1
          False -> total
        },
      )
  }
}

/// "2026-11-09" is day 20_766 since 1970-01-01 (proleptic Gregorian).
pub fn day_number(text: String) -> Result(Int, Nil) {
  case string.split(text, "-") {
    [year, month, day] -> {
      use year <- result.try(int.parse(year))
      use month <- result.try(int.parse(month))
      use day <- result.try(int.parse(day))
      let year = case month <= 2 {
        True -> year - 1
        False -> year
      }
      let era = int.floor_divide(year, 400) |> result.unwrap(0)
      let year_of_era = year - era * 400
      let shifted_month = case month > 2 {
        True -> month - 3
        False -> month + 9
      }
      let day_of_year = { 153 * shifted_month + 2 } / 5 + day - 1
      let day_of_era =
        year_of_era * 365 + year_of_era / 4 - year_of_era / 100 + day_of_year
      Ok(era * 146_097 + day_of_era - 719_468)
    }
    _ -> Error(Nil)
  }
}

/// The inverse of `day_number`.
pub fn day_text(day: Int) -> String {
  let shifted = day + 719_468
  let era = int.floor_divide(shifted, 146_097) |> result.unwrap(0)
  let day_of_era = shifted - era * 146_097
  let year_of_era =
    {
      day_of_era
      - day_of_era
      / 1460
      + day_of_era
      / 36_524
      - day_of_era
      / 146_096
    }
    / 365
  let day_of_year =
    day_of_era - { 365 * year_of_era + year_of_era / 4 - year_of_era / 100 }
  let shifted_month = { 5 * day_of_year + 2 } / 153
  let day = day_of_year - { 153 * shifted_month + 2 } / 5 + 1
  let month = case shifted_month < 10 {
    True -> shifted_month + 3
    False -> shifted_month - 9
  }
  let year = case month <= 2 {
    True -> year_of_era + era * 400 + 1
    False -> year_of_era + era * 400
  }
  let pad = fn(value, width) {
    string.pad_start(int.to_string(value), width, "0")
  }
  pad(year, 4) <> "-" <> pad(month, 2) <> "-" <> pad(day, 2)
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
