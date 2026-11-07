import type { FlowConfirm } from "./types"

/** The Line every account has; see `bluebin/lines` in the backend. */
export const firstLine = "main"

const lastLineKey = "bluebin.line"
const lineUrl = /^\/lines\/([a-z0-9-]+)(\/.*)?$/

function lineOfPage(): { id: string; view: string } {
  const match = lineUrl.exec(location.pathname)
  if (match) {
    return { id: match[1], view: match[2] ?? "/" }
  }
  return { id: localStorage.getItem(lastLineKey) ?? firstLine, view: location.pathname }
}

const page = lineOfPage()

/** The Line this page shows, read once: switching reloads the page. */
export const lineId = page.id

/** The view part of the URL, without the `/lines/<id>` prefix. */
export function viewPath(): string {
  return lineUrl.exec(location.pathname)?.[2] ?? location.pathname
}

export function pageUrl(view: string, line = lineId): string {
  return `/lines/${line}${view}`
}

/** Puts the Line in the URL of a page opened without it, as `/demands`. */
export function settleLineUrl() {
  if (!lineUrl.test(location.pathname)) {
    history.replaceState(null, "", pageUrl(page.view) + location.search)
  }
}

export function rememberLine(line: string | null) {
  if (line) localStorage.setItem(lastLineKey, line)
  else localStorage.removeItem(lastLineKey)
}

/** `/api/demands` → the same route inside the Line of this page. */
export function api(path: string): string {
  return `/api/lines/${lineId}${path.slice("/api".length)}`
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
