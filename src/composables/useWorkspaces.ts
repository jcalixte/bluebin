import { computed, ref } from "vue"
import { lineId, lookOnly, workspaceOwner } from "../api"
import type { LineRole, Workspace } from "../types"

const workspaces = ref<Workspace[]>([])
const loaded = ref(false)
const problem = ref<string | null>(null)

async function fetchWorkspaces() {
  // A look-only visitor has no Account, so no Line menu.
  if (lookOnly) {
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

const current = computed(() => workspace.value?.lines.find((one) => one.id === lineId))

/** Until the menu loads, the own Workspace is the owner's and any other is look-only. */
const role = computed<LineRole>(() => current.value?.role ?? (workspaceOwner ? "viewer" : "owner"))

/** Not inside a Line: the Line menu and the role of this page's Line. */
export function useWorkspaces() {
  loading ??= fetchWorkspaces()
  return { workspaces, workspace, current, role, loaded, problem, ready: loading }
}
