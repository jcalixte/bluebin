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
