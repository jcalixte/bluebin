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
