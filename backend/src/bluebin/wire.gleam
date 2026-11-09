//// The JSON shapes the API sends, one record per shape. `gleam dev` reads
//// this file and writes the encoders (`bluebin/wire_json.gleam`) and the
//// TypeScript types (`src/wire.ts`), so the two sides cannot drift.
////
//// Field types: `String`, `Int`, `Float`, `Bool`, `Option(t)`, `List(t)` and
//// the other records of this file. A field `due_on` is `dueOn` in JSON.
//// The `///` comment of a field becomes its JSDoc.

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
