import { Result$Error$0 } from "../../sim/build/dev/javascript/simulation/gleam.mjs"
import * as gleam from "../../sim/build/dev/javascript/simulation/simulation.mjs"
import wasmUrl from "sql.js/dist/sql-wasm-browser.wasm?url"
import { loadSqlite } from "./sqlite"
import { plugEngine } from "./state"

/** Loaded only in the Simulation build: SQLite and the Gleam API stay out of the real app. */
export async function startSimulation() {
  await loadSqlite(wasmUrl)
  const engine = {
    call: gleam.call,
    start(demo: boolean) {
      const started = gleam.start(demo)
      if (!started.isOk())
        throw new Error(`The Simulation did not start: ${Result$Error$0(started)}`)
    },
  }
  engine.start(true)
  plugEngine(engine)
}
