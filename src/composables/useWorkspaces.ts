import { computed, ref } from "vue"
import { lineId, lookOnly, workspaceOwner } from "../api"
import { actingAs, simulation } from "../simulation/state"
import type { LineEntry, LineRole, Workspace } from "../types"

const workspaces = ref<Workspace[]>([])
const loaded = ref(false)
const problem = ref<string | null>(null)

async function fetchWorkspaces() {
  // A look-only visitor has no Account, so no Line menu; the Simulation has one Line only.
  if (lookOnly || simulation) {
    loaded.value = true
    return
  }
  try {
    const response = await fetch("/api/workspaces")
    if (!response.ok) {
      throw new Error((await response.text()) || `API answered ${response.status}`)
    }
    workspaces.value = (await response.json()) as Workspace[]
  } catch (cause) {
    problem.value = `The Lines did not load: ${cause instanceof Error ? cause.message : String(cause)}`
  } finally {
    loaded.value = true
  }
}

let loading: Promise<void> | null = null

const workspace = computed(() =>
  workspaces.value.find((one) => (workspaceOwner ? one.owner === workspaceOwner : one.own)),
)

const simulated = computed<LineEntry>(() => ({
  id: lineId,
  name: "Simulation",
  shared: false,
  role: actingAs.value === "" ? "owner" : "member",
  teamMember: actingAs.value === "" ? null : actingAs.value,
}))

const current = computed(() =>
  simulation ? simulated.value : workspace.value?.lines.find((one) => one.id === lineId),
)

/** Until the menu loads, the own Workspace is the owner's and any other is look-only. */
const role = computed<LineRole>(() => current.value?.role ?? (workspaceOwner ? "viewer" : "owner"))

const canAct = computed(() => role.value !== "viewer")

/**
 * Mirrors `access.actor` in the API: the owner acts for any Team Member, a Member only as their
 * own, a Viewer never. With no Team Member, a Member acts as their own.
 */
function canActAs(teamMember?: string): boolean {
  if (role.value === "owner") return true
  if (role.value === "viewer") return false
  return teamMember === undefined || teamMember === current.value?.teamMember
}

const ownWorkOnly = computed(() => role.value === "member" && !!current.value?.teamMember)

type Home = { owner: string | null; id: string; teamMember: string }

/**
 * Where the Account's own work is (F45): this page's Line if it is a Team Member there, else the
 * first Line where it is one, its own Workspace first. `null` when it is a Team Member nowhere.
 */
export function homeLine(all: Workspace[], owner: string | null, line: string): Home | null {
  const held = all.flatMap((one) =>
    one.lines.flatMap((entry) =>
      entry.teamMember
        ? [{ owner: one.own ? null : one.owner, id: entry.id, teamMember: entry.teamMember }]
        : [],
    ),
  )
  return held.find((one) => one.owner === owner && one.id === line) ?? held[0] ?? null
}

export function useWorkspaces() {
  loading ??= fetchWorkspaces()
  return {
    workspaces,
    workspace,
    current,
    role,
    canAct,
    canActAs,
    ownWorkOnly,
    loaded,
    problem,
    ready: loading,
  }
}
