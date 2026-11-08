import { ref } from "vue"

/**
 * The build for try.bluebin.app (`vite --mode simulation`): one Line that lives only in this page,
 * with no sign-in and no server. The API's own routes run in the browser on an in-memory SQLite
 * (see `start.ts` and `sim/` at the root). A constant, so the real build drops all of it.
 */
export const simulation = import.meta.env.MODE === "simulation"

/** The Team Member the visitor plays, or `""` for the owner of the Line. */
export const actingAs = ref("")

/** The API of the Simulation, compiled from Gleam: `start.ts` plugs it in. */
export type Engine = {
  call(method: string, path: string, body: string, teamMember: string): [number, string]
  start(demo: boolean): void
}

let engine: Engine | null = null
const changes = new EventTarget()

export function plugEngine(found: Engine) {
  engine = found
}

/** Each screen reads again after a change, as the live stream of the API makes it do. */
export function onSimulatedChange(listener: () => void): () => void {
  changes.addEventListener("change", listener)
  return () => changes.removeEventListener("change", listener)
}

function changed() {
  changes.dispatchEvent(new Event("change"))
}

/** `fetch` for a route inside the Line, answered by the Simulation as `actingAs`. */
export async function simulatedFetch(path: string, init: RequestInit = {}): Promise<Response> {
  if (!engine) throw new Error("The Simulation is not ready.")
  const method = (init.method ?? "GET").toUpperCase()
  const body = typeof init.body === "string" ? init.body : ""
  const [status, text] = engine.call(method, path, body, actingAs.value)
  if (method !== "GET" && status >= 200 && status < 300) changed()
  // A 204 may carry no body at all, not even an empty one.
  return new Response(text === "" ? null : text, {
    status,
    headers: { "content-type": "application/json" },
  })
}

/** Starts the Line again from the demo data, or empty; the owner plays again. */
export function restartSimulation(demo: boolean) {
  if (!engine) throw new Error("The Simulation is not ready.")
  engine.start(demo)
  actingAs.value = ""
  changed()
}
