import bluebin/calendar
import gleam/dynamic/decode
import gleam/float
import gleam/int
import gleam/json
import gleam/list
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

pub fn to_json(demands: List(Demand)) -> String {
  json.array(demands, fn(demand) {
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
    ])
  })
  |> json.to_string
}

pub fn value_stream_takt_hours(demands: List(Demand)) -> Float {
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
