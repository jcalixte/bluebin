import { ref } from "vue"

/** A constant, so the real build drops the Simulation (`vite --mode simulation`). */
export const simulation = import.meta.env.MODE === "simulation"

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

export const guest = invitation !== null

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

type Remote = (method: string, path: string, body: string) => Promise<[number, string]>

let remote: Remote | null = null

export function plugRemote(found: Remote) {
  remote = found
}

export function onSimulatedChange(listener: () => void): () => void {
  changes.addEventListener("change", listener)
  return () => changes.removeEventListener("change", listener)
}

export function changed() {
  changes.dispatchEvent(new Event("change"))
}

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

export function restartSimulation(demo: boolean) {
  if (!engine) throw new Error("The Simulation is not ready.")
  engine.start(demo)
  actingAs.value = ""
  changed()
}
