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
  Event(
    at:,
    kind:,
    piece: Some(piece),
    station: Some(station),
    from:,
    cause: None,
  )
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
      Pass(
        unit: "p",
        station: "a",
        start: 0,
        end: Some(100),
        touch: [#(30, 40), #(0, 10)],
        filled: Some(40),
        held: [#(10, 30)],
      ),
      Pass(
        unit: "p",
        station: "b",
        start: 100,
        end: None,
        touch: [#(100, 200)],
        filled: None,
        held: [],
      ),
    ]
}

pub fn only_a_pause_for_rework_counts_in_the_suggestion_test() {
  let paused = fn(at, cause) {
    Event(
      at:,
      kind: "piece_paused",
      piece: Some("p"),
      station: None,
      from: None,
      cause:,
    )
  }
  let assert [pass, _] =
    measures.replay(
      [
        event(0, "piece_pulled", "p", "a", None),
        paused(1 * hour, Some("held")),
        event(3 * hour, "piece_resumed", "p", "", None),
        paused(4 * hour, Some("rework")),
        event(5 * hour, "piece_resumed", "p", "", None),
        // Before the cause was recorded: read as held.
        paused(6 * hour, None),
        event(7 * hour, "piece_resumed", "p", "", None),
        event(8 * hour, "piece_put_in_blue_bin", "p", "a", None),
        event(20 * hour, "piece_pulled", "p", "b", Some("a")),
      ],
      dict.new(),
      30 * hour,
    )
  assert pass.filled == Some(8 * hour)
  assert pass.held == [#(6 * hour, 7 * hour), #(1 * hour, 3 * hour)]
  let always =
    Calendar(..office(), days: [0, 1, 2, 3, 4, 5, 6], start: 0, end: 24 * 60)
  // The wait in the Blue Bin (8 h to 20 h) is not Replenishment Time.
  let assert Ok(one) = measures.replenishment(always, pass)
  assert one.calendar == 8 * hour
  assert one.working == 8 * hour
  assert one.working_without_held == 5 * hour
}

pub fn p85_is_the_nearest_rank_test() {
  assert measures.p85(span_of(20, 1)) == Ok(17)
  assert measures.p85([5, 1, 4, 2, 3]) == Ok(5)
  assert measures.p85([7]) == Ok(7)
  assert measures.p85([]) == Error(Nil)
}

/// `from` to `to`, both included, in that order.
fn span_of(from: Int, to: Int) -> List(Int) {
  case from == to, from < to {
    True, _ -> [from]
    False, True -> [from, ..span_of(from + 1, to)]
    False, False -> [from, ..span_of(from - 1, to)]
  }
}

fn filled_at(filled: Int, hours: Int) -> measures.Replenishment {
  measures.Replenishment(
    filled:,
    calendar: hours * hour,
    working: hours * hour,
    working_without_held: hours * hour,
  )
}

pub fn the_suggestion_covers_the_replenishment_time_at_takt_test() {
  let five = fn(hours) { list.map(span_of(1, 5), filled_at(_, hours)) }
  // Exactly 2 Takt Times: 2 Blue Bins, with no float rounding up to 3.
  assert measures.suggest(five(8), 4.0)
    == measures.Suggestion(
      passes: 5,
      replenishment: Some(8 * hour),
      blue_bins: Some(2),
    )
  assert { measures.suggest(five(10), 4.0) }.blue_bins == Some(3)
  assert { measures.suggest(five(7), 0.7) }.blue_bins == Some(10)
  // Never fewer than one Blue Bin.
  assert { measures.suggest(five(1), 4.0) }.blue_bins == Some(1)
}

pub fn no_suggestion_without_flow_or_takt_test() {
  let four = list.map(span_of(1, 4), filled_at(_, 8))
  assert measures.suggest(four, 4.0)
    == measures.Suggestion(passes: 4, replenishment: None, blue_bins: None)
  let five = [filled_at(5, 8), ..four]
  assert measures.suggest(five, 0.0)
    == measures.Suggestion(
      passes: 5,
      replenishment: Some(8 * hour),
      blue_bins: None,
    )
}

pub fn the_suggestion_reads_the_last_twenty_passes_test() {
  // 20 recent passes of 4 h, and 10 old ones of 40 h that no longer count.
  let recent = list.map(span_of(101, 120), filled_at(_, 4))
  let old = list.map(span_of(1, 10), filled_at(_, 40))
  let found = measures.suggest(list.append(old, recent), 4.0)
  assert found.passes == 20
  assert found.blue_bins == Some(1)
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
    Event(at:, kind:, piece: None, station: Some("qa"), from: None, cause: None)
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
  let assert Ok(Nil) = db.prepare(connection, db.Demo)
  run(connection)
}

fn exec(connection: sqlight.Connection, sql: String) -> Nil {
  let assert Ok(Nil) = sqlight.exec(sql, connection)
  Nil
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

pub fn every_deployed_piece_of_the_seed_is_measured_exactly_test() {
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

pub fn the_lead_time_ends_at_the_release_test() {
  use connection <- seeded()
  let measured = fn() {
    let assert Ok(piece) =
      list.find(last_weeks(connection).pieces, fn(p) { p.id == "p-checkout-7" })
    piece.span
  }
  let at_deployment = measured()
  // Held for 12 hours after its Deployment, then released.
  exec(
    connection,
    "update piece set released_at =
       strftime('%Y-%m-%dT%H:%M:%SZ', deployed_at, '+12 hours')
     where id = 'p-checkout-7'",
  )
  let held = measured()
  assert held.touch == at_deployment.touch
  assert held.stagnation == at_deployment.stagnation + 12 * hour
  assert measures.lead(held) == held.touch + held.stagnation
}

pub fn a_held_piece_has_no_lead_time_yet_test() {
  use connection <- seeded()
  exec(
    connection,
    "update piece set released_at = null where id = 'p-checkout-7'",
  )
  let found = last_weeks(connection)
  assert !list.any(found.pieces, fn(p) { p.id == "p-checkout-7" })
  assert list.length(found.pieces) == 10
}

pub fn the_seed_gets_a_replenishment_time_and_a_suggestion_test() {
  use connection <- seeded()
  let assert Ok(web) =
    list.find(last_weeks(connection).stations, fn(s) { s.id == "ws-web" })
  assert list.length(web.replenishments) == 11
  list.each(web.replenishments, fn(one) {
    assert one.working_without_held <= one.working
    assert one.working <= one.calendar
  })
  let assert Ok(demands) = demand.list_active(connection)
  let assert Ok(suggestions) =
    measures.suggestions(connection, demand.line_takt_hours(demands))
  let assert Ok(suggestion) = dict.get(suggestions, "ws-web")
  assert suggestion.passes == 11
  let assert Some(bins) = suggestion.blue_bins
  assert bins >= 1
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

pub fn a_pause_for_helping_counts_in_the_suggestion_like_rework_test() {
  // A Helper's Piece waits because of a defect, not because of WIP (R14).
  let assert [pass, _] =
    measures.replay(
      [
        event(0, "piece_pulled", "p", "a", None),
        Event(
          at: 1 * hour,
          kind: "piece_paused",
          piece: Some("p"),
          station: None,
          from: None,
          cause: Some("helping"),
        ),
        event(3 * hour, "piece_resumed", "p", "", None),
        event(4 * hour, "piece_put_in_blue_bin", "p", "a", None),
        event(20 * hour, "piece_pulled", "p", "b", Some("a")),
      ],
      dict.new(),
      30 * hour,
    )
  assert pass.held == []
}
