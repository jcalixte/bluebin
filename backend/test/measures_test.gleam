import bluebin/calendar.{Calendar, Holiday}
import bluebin/db
import bluebin/demand
import bluebin/flow
import bluebin/measures.{Event, Pass}
import gleam/dict
import gleam/dynamic/decode
import gleam/list
import gleam/option.{None, Some}
import gleam/string
import sqlight

const hour = 3600

/// Friday 2026-11-06 09:00 UTC.
const friday = 1_793_955_600

/// Monday 2026-11-09 00:00 UTC, day 20_766 since 1970-01-01.
const monday = 1_794_182_400

fn office() -> calendar.Calendar {
  Calendar(days: [1, 2, 3, 4, 5], start: 9 * 60, end: 16 * 60, holidays: [])
}

pub fn working_time_skips_nights_and_weekends_test() {
  // Friday 15:00 to Monday 10:00: one hour each side of the weekend.
  let from = friday + 6 * hour
  let to = monday + 10 * hour
  assert calendar.working_seconds(office(), from, to) == 2 * hour
  assert calendar.working_seconds(office(), to, from) == 0
}

pub fn working_time_skips_holidays_test() {
  let monday_off =
    Calendar(..office(), holidays: [
      Holiday(day: "2026-11-09", label: "Bridge", index: 20_766),
    ])
  assert calendar.working_seconds(monday_off, friday, monday + 24 * hour)
    == 7 * hour
}

pub fn lead_time_is_touch_time_plus_stagnation_time_test() {
  // Two Sub-Pieces in hand at the same time count once.
  let span =
    measures.span(office(), friday, friday + 10 * hour, [
      #(friday + hour, friday + 3 * hour),
      #(friday + 2 * hour, friday + 4 * hour),
    ])
  assert span.touch == 3 * hour
  assert measures.lead(span) == 10 * hour
  // Stagnation in Working Time: 09:00–10:00 and 12:00–16:00 on Friday.
  assert span.stagnation_working == 4 * hour
  assert measures.lead_working(span) == 7 * hour
}

fn event(at: Int, kind: String, piece: String, station: String, from) {
  Event(at:, kind:, piece: Some(piece), station: Some(station), from:)
}

pub fn a_pause_is_not_touch_time_test() {
  let passes =
    measures.replay(
      [
        event(0, "piece_pulled", "p", "a", None),
        event(10, "piece_paused", "p", "", None),
        event(30, "piece_resumed", "p", "", None),
        event(40, "piece_put_in_blue_bin", "p", "a", None),
        event(100, "piece_pulled", "p", "b", Some("a")),
      ],
      dict.new(),
      200,
    )
  assert passes
    == [
      Pass(unit: "p", station: "a", start: 0, end: Some(100), touch: [
        #(30, 40),
        #(0, 10),
      ]),
      Pass(unit: "p", station: "b", start: 100, end: None, touch: [#(100, 200)]),
    ]
}

pub fn a_split_and_an_assembly_end_the_station_lead_time_test() {
  let children = dict.from_list([#("p", ["p-web", "p-ios"])])
  let passes =
    measures.replay(
      [
        event(0, "piece_pulled", "p", "trunk", None),
        event(5, "piece_put_in_blue_bin", "p", "trunk", None),
        event(10, "piece_pulled", "p-web", "web", Some("trunk")),
        event(20, "piece_pulled", "p-ios", "ios", Some("trunk")),
        event(20, "piece_split", "p", "trunk", None),
        event(30, "piece_put_in_blue_bin", "p-web", "web", None),
        event(40, "piece_put_in_blue_bin", "p-ios", "ios", None),
        event(50, "piece_assembled", "p", "uat", None),
      ],
      children,
      60,
    )
  let ends =
    list.map(passes, fn(pass) { #(pass.unit, pass.station, pass.end) })
    |> list.sort(fn(a, b) {
      string.compare(a.0 <> " " <> a.1, b.0 <> " " <> b.1)
    })
  assert ends
    == [
      #("p", "trunk", Some(20)),
      #("p", "uat", None),
      #("p-ios", "ios", Some(50)),
      #("p-web", "web", Some(50)),
    ]
}

pub fn starvation_lasts_while_a_kanban_is_held_test() {
  let kanban = fn(at, kind) {
    Event(at:, kind:, piece: None, station: Some("qa"), from: None)
  }
  let held =
    measures.kanban_held(
      [
        kanban(10, "kanban_sent"),
        kanban(20, "kanban_sent"),
        kanban(30, "kanban_spent"),
        kanban(40, "kanban_spent"),
        kanban(50, "kanban_sent"),
      ],
      90,
    )
  assert dict.get(held, "qa") == Ok([#(50, 90), #(10, 40)])
}

fn seeded(run: fn(sqlight.Connection) -> a) -> a {
  use connection <- db.with_connection_at(":memory:")
  let assert Ok(Nil) = db.prepare(connection)
  run(connection)
}

fn one(connection: sqlight.Connection, sql: String) -> String {
  let assert Ok([value]) =
    sqlight.query(
      sql,
      on: connection,
      with: [],
      expecting: decode.at([0], decode.string),
    )
  value
}

fn last_weeks(connection: sqlight.Connection) -> measures.Measures {
  let from = one(connection, "select date('now', '-30 day')")
  let to = one(connection, "select date('now')")
  let assert Ok(found) = measures.load(connection, from, to)
  found
}

pub fn every_produced_piece_of_the_seed_is_measured_exactly_test() {
  use connection <- seeded()
  let found = last_weeks(connection)
  assert list.length(found.pieces) == 11
  list.each(found.pieces, fn(piece) {
    assert piece.span.touch > 0
    assert piece.span.stagnation > 0
    assert measures.lead(piece.span) == piece.span.touch + piece.span.stagnation
  })
  let assert Ok(web) = list.find(found.stations, fn(s) { s.id == "ws-web" })
  assert list.length(web.passes) == 11
}

pub fn a_deviation_and_a_spent_kanban_reach_the_measures_test() {
  use connection <- seeded()
  // Analysis holds one Kanban: the first pull spends it, the second is a
  // Deviation.
  let assert Ok(_) = flow.pull(connection, "ws-analysis", None, None)
  let assert Ok(_) =
    flow.pull(connection, "ws-analysis", None, Some("Client demo"))
  let found = last_weeks(connection)
  let assert Ok(analysis) =
    list.find(found.stations, fn(s) { s.id == "ws-analysis" })
  assert analysis.deviations == 1
  assert analysis.pulls >= 2
  let assert [deviation] = found.deviations
  assert deviation.rule == "pull_without_kanban"
  assert deviation.reason == "Client demo"
}

pub fn a_period_must_be_two_days_in_order_test() {
  use connection <- seeded()
  assert measures.load(connection, "2026-11-05", "2026-11-01")
    == Error(measures.InvalidPeriod)
  assert measures.load(connection, "yesterday", "2026-11-01")
    == Error(measures.InvalidPeriod)
}

pub fn the_takt_time_follows_the_working_calendar_test() {
  use connection <- seeded()
  let assert Ok(before) = demand.list_active(connection)
  let assert Ok(Nil) =
    calendar.save(
      connection,
      Calendar(..office(), start: 9 * 60, end: 12 * 60 + 30),
    )
  let assert Ok(after) = demand.list_active(connection)
  let assert [first, ..] = before
  let assert [again, ..] = after
  assert again.hours_per_day == 3.5
  assert demand.takt_time_hours(again) == demand.takt_time_hours(first) /. 2.0
}

pub fn a_wrong_holiday_leaves_the_calendar_as_it_was_test() {
  use connection <- seeded()
  let wrong =
    Calendar(..office(), end: 17 * 60, holidays: [
      Holiday(day: "2026-12-25", label: "Christmas", index: 0),
      Holiday(day: "25/12", label: "Typo", index: 0),
    ])
  let assert Error(calendar.Invalid(_)) = calendar.save(connection, wrong)
  let assert Ok(kept) = calendar.load(connection)
  assert kept == office()

  let assert Error(calendar.Invalid(_)) =
    calendar.save(connection, Calendar(..office(), start: 16 * 60, end: 9 * 60))
  let assert Error(calendar.Invalid(_)) =
    calendar.save(connection, Calendar(..office(), days: []))
}

pub fn the_upgrade_dates_the_backlog_and_the_kanbans_held_test() {
  use connection <- db.with_connection_at(":memory:")
  let assert Ok(Nil) = db.migrate_to(connection, 7)
  let assert Ok(Nil) =
    sqlight.exec(
      "insert into demand values ('d-old', 'Old', 'Client', '2026-01-05', '2026-12-31', 1, 'active');
       insert into piece (id, demand_id, reference, state) values ('p-old', 'd-old', 'US-1', 'backlog');
       insert into work_station (id, name, position, blue_bins) values ('ws-a', 'A', 1, 2);
       insert into kanban (id, station_id) values ('kb-1', 'ws-a');",
      connection,
    )
  let assert Ok(Nil) = db.migrate(connection)
  assert one(connection, "select entered_at from piece")
    == "2026-01-05T00:00:00Z"
  assert one(
      connection,
      "select json_extract(payload, '$.station') from flow_event
        where kind = 'kanban_sent'",
    )
    == "ws-a"
}
