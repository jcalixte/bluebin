//// The JSON shapes the API sends, one custom type per shape. `gleam dev`
//// reads this file and writes the encoders (`bluebin/wire_json.gleam`) and
//// the TypeScript types (`src/wire.ts`), so the two sides cannot drift.
////
//// - A type with one variant and labelled fields is a JSON object. Field
////   types: `String`, `Int`, `Float`, `Bool`, `Option(t)`, `List(t)` and the
////   other types of this file. A field `due_on` is `dueOn` in JSON.
//// - A type whose variants have no fields is a JSON string: `Owner` is
////   `"owner"`.
//// - A type with several variants, some with fields, is a JSON object tagged
////   by `kind`, first: `TakeRework(..)` is `{"kind": "take_rework", ...}`.
////
//// A kind drops the last word of its type name from the end of the variant
//// name, so two types can share a kind: `ReworkItem` of `PriorityItem` is
//// `"rework"`. The `///` comment of a type or a field becomes its JSDoc.

import gleam/option.{type Option}

pub type Demand {
  Demand(
    id: String,
    /// The Demand Code, `CHK`: it starts the Piece Reference of each of its Pieces.
    code: String,
    label: String,
    client: String,
    due_on: String,
    pieces_asked: Int,
    pieces_deployed: Int,
    working_days_total: Int,
    working_days_elapsed: Int,
    takt_time_hours: Float,
    takt_gap: Float,
    andon: Bool,
    /// `YYYY-MM-DD`; null until a Piece of the Demand is deployed.
    forecast_on: Option(String),
    /// Working days from `dueOn` to `forecastOn`: above 0 is late, 0 or less is on time.
    forecast_late_days: Option(Int),
  )
}

pub type Holiday {
  Holiday(day: String, label: String)
}

/// `days` uses 0 for Sunday to 6 for Saturday; `start` and `end` are UTC "HH:MM".
pub type WorkingCalendar {
  WorkingCalendar(
    days: List(Int),
    start: String,
    end: String,
    holidays: List(Holiday),
  )
}

/// What the Account may do in a Line; the server checks it again (H10).
pub type LineRole {
  OwnerRole
  MemberRole
  ViewerRole
}

pub type LineEntry {
  LineEntry(
    id: String,
    name: String,
    /// Anyone with its look-only link sees a Shared Line, signed in or not.
    shared: Bool,
    role: LineRole,
    /// The Account's own Team Member, for a member.
    team_member: Option(String),
  )
}

/// One Workspace of the Line menu, from `GET /api/workspaces`.
pub type Workspace {
  Workspace(
    owner: String,
    /// The owner's name; null before their first sign-in.
    name: Option(String),
    own: Bool,
    lines: List(LineEntry),
  )
}

/// Hours, in each view; the whole Duration is null when there is nothing to average.
pub type Duration {
  Duration(calendar: Option(Float), working: Option(Float))
}

/// Averages per Piece released in the period.
pub type PieceMeasures {
  PieceMeasures(
    count: Int,
    lead_time: Option(Duration),
    touch_time: Option(Duration),
    stagnation_time: Option(Duration),
    backlog_time: Option(Duration),
  )
}

pub type DemandMeasures {
  DemandMeasures(
    id: String,
    label: String,
    client: String,
    pieces: Int,
    /// The Demand's own Lead Time: null until its last Piece is released.
    demand_lead_time: Option(Duration),
    lead_time: Option(Duration),
    touch_time: Option(Duration),
    stagnation_time: Option(Duration),
  )
}

/// `stationLeadTime` and `touchTime` are averages per pass; `starvationTime` and `andonTime` are totals.
pub type StationMeasures {
  StationMeasures(
    id: String,
    name: String,
    branch: Option(String),
    position: Int,
    passes: Int,
    station_lead_time: Option(Duration),
    touch_time: Option(Duration),
    /// 85th percentile of the passes that went in the Blue Bin in the period; null under 5 passes.
    replenishment_time: Option(Duration),
    /// A fraction in 0..1.
    touch_share: Option(Float),
    starvation_time: Option(Duration),
    /// The time an Andon stopped the Work Station inside the period.
    andon_time: Option(Duration),
    /// The Andons raised on the Work Station inside the period.
    andons: Int,
    pulls: Int,
    deviations: Int,
  )
}

pub type RecordedDeviation {
  RecordedDeviation(
    at: String,
    rule: String,
    station: String,
    station_name: String,
    piece: Option(String),
    reason: String,
  )
}

pub type OnTime {
  OnTime(delivered: Int, on_time: Int)
}

/// The Deviations recorded in the period: how many per rule, most first, then each one.
pub type DeviationMeasures {
  DeviationMeasures(by_rule: List(RuleCount), list: List(RecordedDeviation))
}

pub type RuleCount {
  RuleCount(rule: String, count: Int)
}

pub type Measures {
  Measures(
    from: String,
    to: String,
    pieces: PieceMeasures,
    demands: List(DemandMeasures),
    stations: List(StationMeasures),
    /// The time at least one Work Station is stopped by an Andon; stops at the same time count once.
    andon_time: Option(Duration),
    /// Demands delivered in the period, and those delivered by their due date.
    on_time: OnTime,
    deviations: DeviationMeasures,
  )
}

/// What a reorder of the Heijunka Sequence costs one Demand.
pub type ReorderEffect {
  ReorderEffect(
    demand: String,
    label: String,
    /// Places its next Piece moves: positive is later.
    places: Int,
    hours: Float,
    takt_gap: Float,
  )
}

pub type BacklogPiece {
  BacklogPiece(
    id: String,
    reference: String,
    demand: String,
    demand_label: String,
    client: String,
    due_on: String,
    slot_hours: Float,
    urgent: Bool,
    can_be_urgent: Bool,
  )
}

pub type MixCell {
  MixCell(day: String, planned: Float, real: Int, on_plan: Bool)
}

pub type MixTotal {
  MixTotal(planned: Float, real: Int, on_plan: Bool)
}

pub type MixRow {
  MixRow(
    demand: String,
    label: String,
    cells: List(MixCell),
    /// The days shown, added up.
    total: MixTotal,
  )
}

/// `sequence` is the Heijunka Sequence: its first Piece leaves the Backlog next.
pub type Backlog {
  Backlog(
    takt_time_hours: Float,
    sequence: List(BacklogPiece),
    mix: List(MixRow),
  )
}

/// The names a Line gives to its Demands and Pieces (F41).
pub type Labels {
  Labels(demand: String, demands: String, piece: String, pieces: String)
}

pub type AccountName {
  AccountName(first_name: String, last_name: String)
}

/// `email` links the Team Member to the Account that has it; `account` stays
/// null until that Account signs in ("not linked yet"). Both are empty while
/// nobody is signed in.
pub type DesignTeamMember {
  DesignTeamMember(
    id: String,
    name: String,
    email: String,
    account: Option(AccountName),
  )
}

/// Suggested Blue Bins (DESIGN.md F55): the last `passes` (at most 20) that went
/// in the Blue Bin. `replenishmentHours` is their 85th percentile in Working
/// Time, without the pauses while the Team Member held another Piece; null
/// under 5 passes. `blueBins` is null without it or without a Takt Time.
pub type BlueBinSuggestion {
  BlueBinSuggestion(
    passes: Int,
    replenishment_hours: Option(Float),
    blue_bins: Option(Int),
  )
}

/// `locked`: the Work Station holds a Piece, an open Rework or an open Andon.
/// `minBlueBins`: max(1, Pieces in its Blue Bins).
pub type DesignStation {
  DesignStation(
    id: String,
    name: String,
    branch: Option(String),
    blue_bins: Int,
    team_leader: String,
    team_members: List(String),
    locked: Bool,
    min_blue_bins: Int,
    suggestion: BlueBinSuggestion,
  )
}

/// Steps are in flow order: the first step pulls from the Backlog.
pub type DesignStep {
  DesignStep(name: String, stations: List(DesignStation))
}

pub type Design {
  Design(
    labels: Labels,
    /// The Takt Time of the Line, in hours of Working Time; 0 with no active Demand.
    takt_time_hours: Float,
    team_members: List(DesignTeamMember),
    steps: List(DesignStep),
  )
}
