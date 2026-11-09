import { simulatedFetch, simulation } from "./simulation/state"
import type { FlowConfirm } from "./types"
import type {
  AndonCloseInput,
  AndonInput,
  AssignInput,
  DeployInput,
  FinishInput,
  HelpInput,
  PullInput,
  ReleaseInput,
  RepairInput,
  ReworkInput,
  StopHelpingInput,
  UrgentInput,
} from "./wire"

/** The Line every account has; see `bluebin/lines` in the backend. */
export const firstLine = "main"

const lastLineKey = "bluebin.line"
/**
 * `/lines/<id>/<view>` in the Account's own Workspace, `/w/<owner-uid>/lines/<id>/<view>` in
 * another (H12), `/s/<owner-uid>/lines/<id>/<view>` for the look-only link of a Shared Line, which
 * opens with no sign-in (F53).
 */
const lineUrl = /^(?:\/([ws])\/([A-Za-z0-9_-]+))?\/lines\/([a-z0-9-]+)(\/.*)?$/

type Page = { owner: string | null; id: string; view: string; look: boolean }

function rememberedLine(): { owner: string | null; id: string } {
  const remembered = localStorage.getItem(lastLineKey) ?? firstLine
  const [owner, id] = remembered.includes("/") ? remembered.split("/", 2) : [null, remembered]
  return { owner, id }
}

function lineOfPage(): Page {
  if (simulation) {
    return {
      owner: null,
      id: "simulation",
      view: location.pathname,
      look: false,
    }
  }
  const match = lineUrl.exec(location.pathname)
  if (match) {
    return { owner: match[2] ?? null, id: match[3], view: match[4] ?? "/", look: match[1] === "s" }
  }
  return { ...rememberedLine(), view: location.pathname, look: false }
}

const page = lineOfPage()

/** The Line this page shows, read once: switching reloads the page. */
export const lineId = page.id

/** The owner of the Workspace this page shows; `null` for the Account's own. */
export const workspaceOwner = page.owner

export const lookOnly = page.look

export function viewPath(): string {
  if (simulation) return location.pathname
  return lineUrl.exec(location.pathname)?.[4] ?? location.pathname
}

export function pageUrl(
  view: string,
  line = lineId,
  owner = workspaceOwner,
  look = lookOnly,
): string {
  if (simulation) return view
  return `${owner ? `/${look ? "s" : "w"}/${owner}` : ""}/lines/${line}${view}`
}

/** Puts the Line in the URL of a page opened without it, as `/demands`. */
export function settleLineUrl() {
  if (!simulation && !lineUrl.test(location.pathname)) {
    history.replaceState(null, "", pageUrl(page.view) + location.search)
  }
}

export function rememberLine(line: string | null, owner: string | null = null) {
  if (line) localStorage.setItem(lastLineKey, owner ? `${owner}/${line}` : line)
  else localStorage.removeItem(lastLineKey)
}

export const lineApi = `/api${pageUrl("", lineId, workspaceOwner)}`

/** `/api/demands` → the same route inside the Line of this page. */
export function api(path: string): string {
  return `${lineApi}${path.slice("/api".length)}`
}

export function lineFetch(path: string, init?: RequestInit): Promise<Response> {
  return simulation ? simulatedFetch(path, init) : fetch(api(path), init)
}

export type ActionBodies = {
  "/api/pull": PullInput
  "/api/finish": FinishInput
  "/api/deploy": DeployInput
  "/api/release": ReleaseInput
  "/api/rework": ReworkInput
  "/api/rework/repair": RepairInput
  "/api/help": HelpInput
  "/api/help/stop": StopHelpingInput
  "/api/andon": AndonInput
  "/api/andon/close": AndonCloseInput
  "/api/assign": AssignInput
  "/api/backlog/urgent": UrgentInput
}

export async function postAction<P extends keyof ActionBodies>(
  path: P,
  body: ActionBodies[P],
): Promise<FlowConfirm | null> {
  const response = await lineFetch(path, {
    method: "POST",
    headers: { "content-type": "application/json" },
    body: JSON.stringify(body),
  })
  if (response.status === 409) {
    const answer = (await response.json()) as Partial<FlowConfirm> & { message: string }
    if (answer.confirm) {
      return { confirm: answer.confirm, message: answer.message, effects: answer.effects }
    }
    throw new Error(answer.message)
  }
  if (!response.ok) {
    throw new Error((await response.text()) || `API answered ${response.status}`)
  }
  return null
}
