import { ref } from "vue"

/**
 * The build for try.bluebin.app (`vite --mode simulation`): one Line that lives only in this page,
 * with no sign-in and no server. The API's own routes run in the browser on an in-memory SQLite
 * (see `start.ts` and `sim/` at the root). A constant, so the real build drops all of it.
 */
export const simulation = import.meta.env.MODE === "simulation"

/** Each site links to the other: the real app for a Line that stays, the Simulation to try. */
export const appUrl = "https://bluebin.app"
export const simulationUrl = "https://try.bluebin.app/line"

/** The Team Member the visitor plays, or `""` for the owner of the Line. */
export const actingAs = ref("")

const joinKey = "bluebin.join"

/**
 * The code of a shared Simulation this tab joins as a Guest, from a `#join=<code>` link. Kept for
 * the tab, as the tabs of the app rewrite the URL and a reload must stay in the same Simulation.
 */
function readInvitation(): string | null {
  if (!simulation) return null
  const found = /^#join=([A-Za-z0-9_.-]+)$/.exec(location.hash)
  if (found) {
    sessionStorage.setItem(joinKey, found[1])
    history.replaceState(null, "", location.pathname + location.search)
  }
  return sessionStorage.getItem(joinKey)
}

export const invitation = readInvitation()

/** This page plays one Team Member in the Simulation of another page, its Host. */
export const guest = invitation !== null

/** Leaves the shared Simulation for one of this page only. */
export function playAlone() {
  sessionStorage.removeItem(joinKey)
  location.assign("/line")
}

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

/** A Guest sends each call to its Host, which answers the status and the body. */
type Remote = (method: string, path: string, body: string) => Promise<[number, string]>

let remote: Remote | null = null

export function plugRemote(found: Remote) {
  remote = found
}

/** Each screen reads again after a change, as the live stream of the API makes it do. */
export function onSimulatedChange(listener: () => void): () => void {
  changes.addEventListener("change", listener)
  return () => changes.removeEventListener("change", listener)
}

/** Tells each screen to read again; a Guest calls it when its Host announces a change. */
export function changed() {
  changes.dispatchEvent(new Event("change"))
}

/** One call to the Line of this page, as `teamMember`: the Host answers its Guests with it too. */
export function answer(
  method: string,
  path: string,
  body: string,
  teamMember: string,
): [number, string] {
  if (!engine) throw new Error("The Simulation is not ready.")
  const [status, text] = engine.call(method, path, body, teamMember)
  if (method !== "GET" && status >= 200 && status < 300) changed()
  return [status, text]
}

/** `fetch` for a route inside the Line, answered by the Simulation as `actingAs`. */
export async function simulatedFetch(path: string, init: RequestInit = {}): Promise<Response> {
  const method = (init.method ?? "GET").toUpperCase()
  const body = typeof init.body === "string" ? init.body : ""
  const [status, text] = remote
    ? await remote(method, path, body)
    : answer(method, path, body, actingAs.value)
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
