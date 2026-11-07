import type { FlowConfirm } from "./types"

/** The Line every account has; see `bluebin/lines` in the backend. */
export const firstLine = "main"

const lastLineKey = "bluebin.line"
/** `/lines/<id>/<view>` in the Account's own Workspace, `/w/<owner-uid>/lines/<id>/<view>` in another (H12). */
const lineUrl = /^(?:\/w\/([A-Za-z0-9_-]+))?\/lines\/([a-z0-9-]+)(\/.*)?$/

type Page = { owner: string | null; id: string; view: string }

/** The last Line opened: a bare id in the own Workspace, `<owner-uid>/<id>` in another. */
function rememberedLine(): { owner: string | null; id: string } {
  const remembered = localStorage.getItem(lastLineKey) ?? firstLine
  const [owner, id] = remembered.includes("/") ? remembered.split("/", 2) : [null, remembered]
  return { owner, id }
}

function lineOfPage(): Page {
  const match = lineUrl.exec(location.pathname)
  if (match) {
    return { owner: match[1] ?? null, id: match[2], view: match[3] ?? "/" }
  }
  return { ...rememberedLine(), view: location.pathname }
}

const page = lineOfPage()

/** The Line this page shows, read once: switching reloads the page. */
export const lineId = page.id

/** The owner of the Workspace this page shows; `null` for the Account's own. */
export const workspaceOwner = page.owner

/** The view part of the URL, without the Line prefix. */
export function viewPath(): string {
  return lineUrl.exec(location.pathname)?.[3] ?? location.pathname
}

export function pageUrl(view: string, line = lineId, owner = workspaceOwner): string {
  return `${owner ? `/w/${owner}` : ""}/lines/${line}${view}`
}

/** Puts the Line in the URL of a page opened without it, as `/demands`. */
export function settleLineUrl() {
  if (!lineUrl.test(location.pathname)) {
    history.replaceState(null, "", pageUrl(page.view) + location.search)
  }
}

export function rememberLine(line: string | null, owner: string | null = null) {
  if (line) localStorage.setItem(lastLineKey, owner ? `${owner}/${line}` : line)
  else localStorage.removeItem(lastLineKey)
}

/** The API root of the Line of this page. */
export const lineApi = `/api${pageUrl("", lineId, workspaceOwner)}`

/** `/api/demands` → the same route inside the Line of this page. */
export function api(path: string): string {
  return `${lineApi}${path.slice("/api".length)}`
}

export async function postAction(
  path: string,
  body: Record<string, unknown>,
): Promise<FlowConfirm | null> {
  const response = await fetch(api(path), {
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
    throw new Error(await response.text())
  }
  return null
}
