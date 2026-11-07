import bluebin/calendar.{type Calendar}
import bluebin/design
import gleam/bool
import gleam/dynamic/decode
import gleam/float
import gleam/int
import gleam/json
import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/result
import gleam/string
import sqlight

pub type Demand {
  Demand(
    id: String,
    label: String,
    client: String,
    due_on: String,
    pieces_asked: Int,
    pieces_produced: Int,
    working_days_total: Int,
    working_days_elapsed: Int,
    hours_per_day: Float,
  )
}

/// Working days: every day between the first start and the later of today and
/// the last due date that the Working Calendar counts.
const list_sql = "
with recursive
  span(day, last_day) as (
    select
      (select min(started_on) from demand where state = 'active'),
      (select max(d) from (
        select max(due_on) as d from demand where state = 'active'
        union all select date('now')
      ))
  ),
  days(day, last_day) as (
    select day, last_day from span
    union all
    select date(day, '+1 day'), last_day from days where day < last_day
  ),
  working_day(day) as (
    select day from days where "
  <> calendar.working_day_sql
  <> "
  )
select
  d.id,
  d.label,
  d.client,
  d.due_on,
  d.pieces_asked,
  (select count(*) from piece p where p.demand_id = d.id and p.state = 'produced'),
  (select count(*) from working_day w where w.day >= d.started_on and w.day <= d.due_on),
  (select count(*) from working_day w where w.day >= d.started_on and w.day <= date('now')),
  (select (strftime('%s', '2000-01-01 ' || day_end) - strftime('%s', '2000-01-01 ' || day_start)) / 3600.0
     from working_calendar)
from demand d
where d.state = 'active'
order by d.due_on
"

pub fn list_active(
  connection: sqlight.Connection,
) -> Result(List(Demand), sqlight.Error) {
  sqlight.query(list_sql, on: connection, with: [], expecting: decoder())
}

fn decoder() -> decode.Decoder(Demand) {
  use id <- decode.field(0, decode.string)
  use label <- decode.field(1, decode.string)
  use client <- decode.field(2, decode.string)
  use due_on <- decode.field(3, decode.string)
  use pieces_asked <- decode.field(4, decode.int)
  use pieces_produced <- decode.field(5, decode.int)
  use working_days_total <- decode.field(6, decode.int)
  use working_days_elapsed <- decode.field(7, decode.int)
  use hours_per_day <- decode.field(8, decode.float)
  decode.success(Demand(
    id:,
    label:,
    client:,
    due_on:,
    pieces_asked:,
    pieces_produced:,
    working_days_total:,
    working_days_elapsed:,
    hours_per_day:,
  ))
}

pub fn takt_time_hours(demand: Demand) -> Float {
  case demand.pieces_asked {
    0 -> 0.0
    asked ->
      int.to_float(demand.working_days_total)
      *. demand.hours_per_day
      /. int.to_float(asked)
  }
}

pub fn takt_gap(demand: Demand) -> Float {
  case demand.working_days_total {
    0 -> 0.0
    total -> {
      let share =
        int.to_float(demand.working_days_elapsed) /. int.to_float(total)
      let expected = float.min(1.0, share) *. int.to_float(demand.pieces_asked)
      round_to_tenth(int.to_float(demand.pieces_produced) -. expected)
    }
  }
}

pub fn andon(demand: Demand) -> Bool {
  takt_gap(demand) <=. -1.0
}

pub fn round_to_tenth(value: Float) -> Float {
  int.to_float(float.round(value *. 10.0)) /. 10.0
}

/// The working days the Demand still needs at its pace so far: Pieces
/// produced ÷ working days elapsed. None until a Piece is produced.
pub fn remaining_working_days(demand: Demand) -> Option(Int) {
  case demand.pieces_produced > 0 {
    False -> None
    True -> {
      let remaining = int.max(0, demand.pieces_asked - demand.pieces_produced)
      let elapsed = int.max(1, demand.working_days_elapsed)
      // ceil(remaining ÷ (produced ÷ elapsed)), in whole numbers.
      Some(
        { remaining * elapsed + demand.pieces_produced - 1 }
        / demand.pieces_produced,
      )
    }
  }
}

/// The day the last Piece should reach production, and how many working days
/// after the due date that is (≤ 0: on time).
pub type Forecast {
  Forecast(on: String, late_days: Int)
}

/// Beyond about three years a forecast says nothing useful.
const forecast_horizon_days = 1096

/// `today` counts days since 1970-01-01.
pub fn forecast(
  demand: Demand,
  calendar: Calendar,
  today: Int,
) -> Option(Forecast) {
  use days <- option.then(remaining_working_days(demand))
  use on <- option.then(
    calendar.add_working_days(
      calendar,
      today,
      days,
      today + forecast_horizon_days,
    )
    |> option.from_result,
  )
  use due <- option.then(
    calendar.day_number(demand.due_on) |> option.from_result,
  )
  Some(Forecast(
    on: calendar.day_text(on),
    late_days: calendar.working_days_between(calendar, due, on),
  ))
}

pub fn to_json(
  demands: List(Demand),
  calendar: Calendar,
  today: Int,
) -> String {
  json.array(demands, fn(demand) {
    let forecast = forecast(demand, calendar, today)
    json.object([
      #("id", json.string(demand.id)),
      #("label", json.string(demand.label)),
      #("client", json.string(demand.client)),
      #("dueOn", json.string(demand.due_on)),
      #("piecesAsked", json.int(demand.pieces_asked)),
      #("piecesProduced", json.int(demand.pieces_produced)),
      #("workingDaysTotal", json.int(demand.working_days_total)),
      #("workingDaysElapsed", json.int(demand.working_days_elapsed)),
      #("taktTimeHours", json.float(round_to_tenth(takt_time_hours(demand)))),
      #("taktGap", json.float(takt_gap(demand))),
      #("andon", json.bool(andon(demand))),
      #(
        "forecastOn",
        json.nullable(option.map(forecast, fn(f) { f.on }), json.string),
      ),
      #(
        "forecastLateDays",
        json.nullable(option.map(forecast, fn(f) { f.late_days }), json.int),
      ),
    ])
  })
  |> json.to_string
}

pub fn line_takt_hours(demands: List(Demand)) -> Float {
  let rate =
    demands
    |> list.map(takt_time_hours)
    |> list.filter(fn(hours) { hours >. 0.0 })
    |> list.fold(0.0, fn(total, hours) { total +. 1.0 /. hours })

  case rate >. 0.0 {
    True -> round_to_tenth(1.0 /. rate)
    False -> 0.0
  }
}

pub fn behind_count(demands: List(Demand)) -> Int {
  demands |> list.filter(andon) |> list.length
}

pub const max_text_length = 60

pub const max_pieces = 200

pub type CreateError {
  Invalid(String)
  StoreFailed
}

/// Enters a Demand that starts today, with its Pieces waiting in the Backlog.
/// Returns its id.
pub fn create(
  connection: sqlight.Connection,
  label: String,
  client: String,
  due_on: String,
  pieces: Int,
) -> Result(String, CreateError) {
  let label = string.trim(label)
  let client = string.trim(client)
  use _ <- result.try(check_text(label, "A Demand needs a label."))
  use _ <- result.try(check_text(client, "A Demand needs a Client."))
  use <- bool.guard(
    pieces < 1 || pieces > max_pieces,
    Error(Invalid(
      "A Demand asks for 1 to " <> int.to_string(max_pieces) <> " Pieces.",
    )),
  )
  use due <- result.try(
    query(
      connection,
      "select date(?1) is ?1, ?1 >= date('now')",
      [sqlight.text(due_on)],
      {
        use valid <- decode.field(0, sqlight.decode_bool())
        use ahead <- decode.field(1, sqlight.decode_bool())
        decode.success(#(valid, ahead))
      },
    ),
  )
  use _ <- result.try(case due {
    [#(True, True)] -> Ok(Nil)
    [#(True, False)] -> Error(Invalid("The due date cannot be in the past."))
    _ -> Error(Invalid("The due date must be a day like 2026-12-31."))
  })
  use labels <- result.try(
    design.load_labels(connection) |> result.replace_error(StoreFailed),
  )

  use _ <- result.try(exec(connection, "begin immediate;"))
  let created = {
    use rows <- result.try(query(
      connection,
      "insert into demand
         (id, label, client, started_on, due_on, pieces_asked, state)
       values ('d-' || lower(hex(randomblob(6))), ?1, ?2, date('now'), ?3, ?4,
               'active')
       returning id",
      [
        sqlight.text(label),
        sqlight.text(client),
        sqlight.text(due_on),
        sqlight.int(pieces),
      ],
      decode.at([0], decode.string),
    ))
    use id <- result.try(list.first(rows) |> result.replace_error(StoreFailed))
    use _ <- result.try(query(
      connection,
      "with recursive n(i) as (select 1 union all select i + 1 from n where i < ?2)
       insert into piece (id, demand_id, reference, state, entered_at)
       select 'p-' || substr(?1, 3) || '-' || i, ?1, ?3 || '-' || i, 'backlog',
              strftime('%Y-%m-%dT%H:%M:%SZ', 'now')
         from n order by i",
      [
        sqlight.text(id),
        sqlight.int(pieces),
        sqlight.text(initials(labels.piece)),
      ],
      decode.success(Nil),
    ))
    use _ <- result.try(query(
      connection,
      "insert into flow_event (kind, payload)
       values ('demand_entered', json_object('demand', ?1, 'pieces', ?2))",
      [sqlight.text(id), sqlight.int(pieces)],
      decode.success(Nil),
    ))
    Ok(id)
  }
  case created {
    Ok(id) -> {
      use _ <- result.try(exec(connection, "commit;"))
      Ok(id)
    }
    Error(error) -> {
      let _ = exec(connection, "rollback;")
      Error(error)
    }
  }
}

/// "User Story" gives "US", the prefix of each Piece reference.
pub fn initials(label: String) -> String {
  case
    string.split(label, " ")
    |> list.filter_map(string.first)
    |> string.concat
    |> string.uppercase
  {
    "" -> "P"
    found -> found
  }
}

fn check_text(text: String, when_empty: String) -> Result(Nil, CreateError) {
  case text == "", string.length(text) > max_text_length {
    True, _ -> Error(Invalid(when_empty))
    _, True ->
      Error(Invalid(
        "\""
        <> text
        <> "\" is longer than "
        <> int.to_string(max_text_length)
        <> " characters.",
      ))
    False, False -> Ok(Nil)
  }
}

fn query(
  connection: sqlight.Connection,
  sql: String,
  values: List(sqlight.Value),
  decoder: decode.Decoder(a),
) -> Result(List(a), CreateError) {
  sqlight.query(sql, on: connection, with: values, expecting: decoder)
  |> result.replace_error(StoreFailed)
}

fn exec(
  connection: sqlight.Connection,
  sql: String,
) -> Result(Nil, CreateError) {
  sqlight.exec(sql, connection) |> result.replace_error(StoreFailed)
}
