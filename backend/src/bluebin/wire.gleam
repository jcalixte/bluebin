//// The JSON shapes the API sends and reads, one custom type per shape.
//// `gleam dev` reads this file and writes the encoders and decoders
//// (`bluebin/wire_json.gleam`) and the TypeScript types (`src/wire.ts`), so
//// the two sides cannot drift.
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
////
//// A type whose name ends in `Input` is a request body: it gets a decoder
//// (`pull_input_decoder()`) and no encoder, and each type it reaches gets a
//// decoder too. An `Option` field of a request body may be absent or null.

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

/// The run chart (F38): the Line's first day, and its last weeks.
pub type WeekHistory {
  WeekHistory(
    /// The day of the first event of the Line, `YYYY-MM-DD` (UTC): no measure before it.
    started_on: String,
    weeks: List(WeekMeasures),
  )
}

/// One week of the run chart (F38), Monday to Sunday (UTC).
pub type WeekMeasures {
  WeekMeasures(
    from: String,
    to: String,
    /// Pieces released in the week.
    pieces: Int,
    /// Average per Piece released; null with no Piece released.
    lead_time: Option(Duration),
  )
}

/// One save of the Design that changes the flow: the pivot of a before/after comparison (F38).
pub type LineChange {
  LineChange(
    /// When the Design was saved, `YYYY-MM-DDTHH:MM:SSZ` (UTC).
    at: String,
    /// What changed, one sentence for each Work Station or Team Member.
    items: List(String),
  )
}

pub type BlueBin {
  BlueBin(
    slot: Int,
    id: Option(String),
    piece: Option(String),
    demand: Option(String),
    /// At a Split, the Branches that already pulled their Sub-Piece of it.
    pulled_by: Option(String),
  )
}

pub type Overflow {
  Overflow(id: String, piece: String, demand: String)
}

pub type Deviation {
  Deviation(rule: String, piece: Option(String), reason: String, at: String)
}

pub type Member {
  Member(id: String, name: String, busy: Bool)
}

pub type TeamMemberName {
  TeamMemberName(id: String, name: String)
}

pub type InProgressPiece {
  InProgressPiece(
    id: String,
    piece: String,
    demand: String,
    team_member: Option(String),
    team_member_id: Option(String),
    paused: Bool,
    /// An open Rework repairs it: finishing it accepts the repair.
    under_rework: Bool,
    /// The Team Members who Help the Rework on this Piece.
    helpers: List(TeamMemberName),
  )
}

pub type Rework {
  Rework(
    id: String,
    piece: String,
    description: String,
    /// The Work Station that found the defect and holds the Piece.
    found_by: String,
    found_by_id: Option(String),
    assignee: Option(String),
    assignee_id: Option(String),
    /// Its assignee repairs it now; their other open Reworks wait.
    started: Bool,
    helpers: List(TeamMemberName),
    /// Who may join as Helper now: the two Work Stations concerned, while someone repairs.
    can_help: List(TeamMemberName),
  )
}

pub type WorkStation {
  WorkStation(
    id: String,
    name: String,
    position: Int,
    branch: Option(String),
    blue_bin_count: Int,
    team_leader: Option(String),
    blue_bins: List(BlueBin),
    overflow: List(Overflow),
    team_members: List(Member),
    in_progress: List(InProgressPiece),
    rework: List(Rework),
    /// A fraction in 0..1; null until a Piece has left.
    first_pass_yield: Option(Float),
    rework_hours: Float,
    deviations: List(Deviation),
    kanbans: Int,
  )
}

/// The 409 answer of a flow action that breaks a rule: send it again with a
/// reason to record the Deviation.
pub type RuleConfirm {
  RuleConfirm(confirm: String, rules: List(String), message: String)
}

/// The 409 answer of a reorder of the Heijunka Sequence, with what it costs.
pub type ReorderConfirm {
  ReorderConfirm(confirm: String, message: String, effects: List(ReorderEffect))
}

pub type Step {
  Step(position: Int, name: String)
}

/// A stop raised by hand (F42), or a Rework that waits with nobody on it (F15).
pub type Andon {
  StopAndon(
    station: String,
    station_name: String,
    raised_by: Option(String),
    raised_at: String,
    team_leader_id: Option(String),
    team_leader: Option(String),
  )
  ReworkWaitsAndon(
    station: String,
    station_name: String,
    rework: String,
    piece: String,
    waiting_hours: Float,
  )
}

pub type AssignmentKind {
  PieceKind
  ReworkKind
}

/// An active Assignment with no event for more than one working day.
pub type StaleAssignment {
  StaleAssignment(kind: AssignmentKind, id: String)
}

/// `capacityHours` is the average Touch Time per Piece over the last 7 days, divided by its Team Members.
pub type Bottleneck {
  Bottleneck(
    station: String,
    capacity_hours: Option(Float),
    slower: Bool,
    full_in_front: Bool,
  )
}

/// A deployed Piece that waits for its Release; `waitingHours` since its Deployment, in Calendar Time.
pub type HeldForRelease {
  HeldForRelease(
    id: String,
    piece: String,
    demand: String,
    demand_label: String,
    waiting_hours: Float,
  )
}

pub type Line {
  Line(
    stations: List(WorkStation),
    steps: List(Step),
    takt_time_hours: Float,
    demands_behind: Int,
    andons: List(Andon),
    stale: List(StaleAssignment),
    active_assignments: Int,
    bottlenecks: List(Bottleneck),
    held_for_release: List(HeldForRelease),
  )
}

/// `stations` is ordered nearest to Deployment first.
pub type TeamMember {
  TeamMember(id: String, name: String, stations: List(String))
}

/// One Assignment of a Team Member is active; the others wait, paused.
pub type Assignment {
  ReworkAssignment(
    id: String,
    piece: String,
    station: String,
    station_name: String,
    found_by: String,
    description: String,
    active: Bool,
  )
  PieceAssignment(
    id: String,
    piece: String,
    station: String,
    station_name: String,
    active: Bool,
  )
}

pub type NextThing {
  Continue(assignment: Assignment)
  TakeRework(
    rework: String,
    piece: String,
    station: String,
    station_name: String,
  )
  TakeKanban(station: String, station_name: String)
  Helping(
    rework: String,
    piece: String,
    assignee: String,
    station: String,
    station_name: String,
  )
  HelpTheRework(
    rework: String,
    piece: String,
    assignee: String,
    station: String,
    station_name: String,
  )
  HelpDownstream(station: String, station_name: String, because: String)
  Wait
}

/// A Priority List is ordered Rework first, then the oldest Kanban.
pub type PriorityItem {
  ReworkItem(
    id: String,
    piece: String,
    description: String,
    assignee: Option(String),
  )
  KanbanItem(id: String, since: String)
}

pub type PriorityList {
  PriorityList(
    station: String,
    name: String,
    team_members: List(TeamMemberName),
    items: List(PriorityItem),
  )
}

pub type TeamMemberView {
  TeamMemberView(
    /// The Andons of the Team Member's Work Stations only.
    andons: List(Andon),
    team_member: TeamMemberName,
    next: NextThing,
    assignments: List(Assignment),
    priority_lists: List(PriorityList),
  )
}

// Request bodies ---------------------------------------------------------------

/// `PUT /api/account`.
pub type AccountInput {
  AccountInput(first_name: String, last_name: String)
}

/// The name of a new or renamed Line, Team Member or step.
pub type NameInput {
  NameInput(name: String)
}

/// `PUT /api/lines/<id>/sharing`.
pub type ShareInput {
  ShareInput(shared: Bool)
}

/// `label` is "" when absent.
pub type HolidayInput {
  HolidayInput(day: String, label: Option(String))
}

/// `PUT /api/calendar`; `start` and `end` are "HH:MM"; no `holidays` is none.
pub type WorkingCalendarInput {
  WorkingCalendarInput(
    days: List(Int),
    start: String,
    end: String,
    holidays: Option(List(HolidayInput)),
  )
}

/// A Team Member with no `email`, sent by an SPA older than the links, keeps
/// its link.
pub type DesignTeamMemberInput {
  DesignTeamMemberInput(id: String, name: String, email: Option(String))
}

/// `id` is null for a new Work Station.
pub type DesignStationInput {
  DesignStationInput(
    id: Option(String),
    name: String,
    branch: Option(String),
    blue_bins: Int,
    team_leader: String,
    team_members: List(String),
  )
}

pub type DesignStepInput {
  DesignStepInput(name: String, stations: List(DesignStationInput))
}

/// `PUT /api/design`: the body of `GET /api/design`, without what the server
/// computes.
pub type DesignInput {
  DesignInput(
    labels: Labels,
    team_members: List(DesignTeamMemberInput),
    steps: List(DesignStepInput),
  )
}

/// `POST /api/demands`.
pub type DemandInput {
  DemandInput(
    label: String,
    client: String,
    due_on: String,
    pieces: Int,
    code: Option(String),
  )
}

/// `PUT /api/demands/<id>/code`.
pub type DemandCodeInput {
  DemandCodeInput(code: String)
}

pub type UrgentInput {
  UrgentInput(piece: String, reason: Option(String))
}

/// `reason` confirms a pull that breaks a rule.
pub type PullInput {
  PullInput(
    station: String,
    team_member: Option(String),
    reason: Option(String),
  )
}

pub type FinishInput {
  FinishInput(station: String, piece: String, reason: Option(String))
}

/// `hold` is false when absent.
pub type DeployInput {
  DeployInput(piece: String, hold: Option(Bool))
}

pub type ReleaseInput {
  ReleaseInput(pieces: List(String))
}

pub type ReworkInput {
  ReworkInput(
    station: String,
    piece: String,
    made_by: String,
    description: String,
  )
}

pub type RepairInput {
  RepairInput(rework: String)
}

pub type HelpInput {
  HelpInput(rework: String, team_member: Option(String))
}

pub type StopHelpingInput {
  StopHelpingInput(team_member: Option(String))
}

pub type AndonInput {
  AndonInput(station: String, team_member: Option(String))
}

pub type AndonCloseInput {
  AndonCloseInput(station: String, team_member: String)
}

pub type AssignInput {
  AssignInput(kind: AssignmentKind, id: String, team_member: String)
}
