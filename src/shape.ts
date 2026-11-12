/**
 * The routes of a Line: where each Work Station pulls its Piece from.
 * Mirrors backend/src/bluebin/shape.gleam; the server stays the judge.
 *
 * A Line is a grid of steps. The trunk has one Work Station at a step; a Split
 * opens Branches that run side by side over the next steps, each with its own
 * number of Work Stations, until the trunk Work Station after them does the
 * Assembly. A Branch can open one nested Split, closed by a later Work Station
 * of the same Branch.
 */

export type ShapeNode = {
  id: string
  position: number
  /** Null on the trunk. */
  branch: string | null
  /** The outer Branch of a nested Branch. */
  parentBranch: string | null
}

export type Inflow =
  | { kind: "backlog" }
  | { kind: "straight"; from: string }
  | { kind: "split"; from: string; branches: string[] }
  | { kind: "assembly"; ends: string[] }

/** Code point order, as Gleam's `string.compare`. */
const byCodePoint = (a: string, b: string) => (a < b ? -1 : a > b ? 1 : 0)

/** A Work Station of a Branch that opens inside `lane`. */
function inside(node: ShapeNode, lane: string | null) {
  return lane === null
    ? node.branch !== null && node.parentBranch === null
    : node.parentBranch === lane
}

function splitSource(nodes: ShapeNode[], first: ShapeNode) {
  let found: ShapeNode | null = null
  for (const other of nodes) {
    if (other.position < first.position && other.branch === first.parentBranch) {
      if (!found || other.position > found.position) found = other
    }
  }
  return found
}

function firstOf(nodes: ShapeNode[], branch: string | null) {
  let found: ShapeNode | null = null
  for (const node of nodes) {
    if (node.branch === branch && (!found || node.position < found.position)) found = node
  }
  return found
}

/** Null when the shape is broken, as a draft can be. */
export function inflow(nodes: ShapeNode[], node: ShapeNode): Inflow | null {
  const lane = node.branch
  const before = nodes.filter(
    (other) => other.position < node.position && (other.branch === lane || inside(other, lane)),
  )
  if (before.length === 0) {
    if (lane === null) return { kind: "backlog" }
    const from = splitSource(nodes, node)
    if (!from) return null
    const branches = new Set<string>()
    for (const other of nodes) {
      if (other.branch === null || other.parentBranch !== node.parentBranch) continue
      const first = firstOf(nodes, other.branch)
      if (first && splitSource(nodes, first)?.id === from.id) branches.add(other.branch)
    }
    return { kind: "split", from: from.id, branches: [...branches].sort(byCodePoint) }
  }
  const nearest = Math.max(...before.map((other) => other.position))
  const straight = before.find((other) => other.position === nearest && other.branch === lane)
  if (straight) return { kind: "straight", from: straight.id }
  return { kind: "assembly", ends: ends(nodes, lane, node) }
}

/** The last Work Station of each Branch that opens inside `lane` and closes at `node`. */
function ends(nodes: ShapeNode[], lane: string | null, node: ShapeNode) {
  const floor = Math.max(
    -1,
    ...nodes
      .filter((other) => other.branch === lane && other.position < node.position)
      .map((other) => other.position),
  )
  const last = new Map<string, ShapeNode>()
  for (const other of nodes) {
    if (!inside(other, lane) || other.position <= floor || other.position >= node.position) continue
    const branch = other.branch ?? ""
    const found = last.get(branch)
    if (!found || other.position > found.position) last.set(branch, other)
  }
  return [...last.entries()].sort(([a], [b]) => byCodePoint(a, b)).map(([, one]) => one.id)
}

/** The Work Stations it pulls from: none from the Backlog, one, or each Branch end. */
export function upstream(nodes: ShapeNode[], node: ShapeNode): string[] {
  const found = inflow(nodes, node)
  if (!found || found.kind === "backlog") return []
  return found.kind === "assembly" ? found.ends : [found.from]
}

/** Every Piece that reaches `downstream` has passed `up` first. */
export function isUpstream(nodes: ShapeNode[], up: string, downstream: string): boolean {
  const byId = new Map(nodes.map((node) => [node.id, node]))
  const seen = new Set<string>()
  const pending = [downstream]
  while (pending.length > 0) {
    const node = byId.get(pending.pop() ?? "")
    if (!node) continue
    for (const one of upstream(nodes, node)) {
      if (seen.has(one)) continue
      seen.add(one)
      pending.push(one)
    }
  }
  return seen.has(up)
}

/**
 * One arrow from a Work Station to one it feeds. `branch` names the Branch
 * when `to` is its first Work Station, so the name shows on the first arrow.
 */
export type FlowLink = {
  from: string
  to: string
  kind: "straight" | "split" | "assembly"
  branch: string | null
}

/** Every arrow of the Line: one into each Work Station from each it pulls from. */
export function flowLinks(nodes: ShapeNode[]): FlowLink[] {
  return nodes.flatMap((node): FlowLink[] => {
    const found = inflow(nodes, node)
    if (!found || found.kind === "backlog") return []
    if (found.kind === "assembly") {
      return found.ends.map((from) => ({ from, to: node.id, kind: "assembly", branch: null }))
    }
    return [
      {
        from: found.from,
        to: node.id,
        kind: found.kind,
        branch: found.kind === "split" ? node.branch : null,
      },
    ]
  })
}

/**
 * The rows of the grid: at each step, the lanes it shows from top to bottom.
 * A trunk step shows the trunk (null); a step of a Split shows every Branch of
 * that Split, each nested Branch under its outer Branch, so a Branch keeps its
 * row across the Split and an empty cell shows where it skips a step.
 * `positions` lists every step, also the ones with no Work Station.
 */
export function laneRows(
  nodes: ShapeNode[],
  positions: number[],
): { lanes: Map<number, (string | null)[]>; rows: number } {
  const sorted = [...new Set(positions)].sort((a, b) => a - b)
  const trunkAt = new Set(nodes.filter((node) => node.branch === null).map((node) => node.position))
  const lanes = new Map<number, (string | null)[]>()
  let run: number[] = []
  const close = () => {
    if (run.length === 0) return
    const inRun = nodes
      .filter((node) => node.branch !== null && run.includes(node.position))
      .sort((a, b) => a.position - b.position || byCodePoint(a.branch ?? "", b.branch ?? ""))
    const outer = [
      ...new Set(inRun.filter((node) => node.parentBranch === null).map((n) => n.branch)),
    ]
    const order: string[] = []
    for (const branch of outer) {
      if (branch === null) continue
      order.push(branch)
      for (const child of new Set(
        inRun.filter((n) => n.parentBranch === branch).map((n) => n.branch),
      )) {
        if (child !== null) order.push(child)
      }
    }
    for (const position of run) lanes.set(position, order)
    run = []
  }
  for (const position of sorted) {
    if (trunkAt.has(position)) {
      close()
      lanes.set(position, [null])
    } else {
      run.push(position)
    }
  }
  close()
  const rows = Math.max(1, ...[...lanes.values()].map((one) => one.length))
  return { lanes, rows }
}
