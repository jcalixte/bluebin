import { onMounted, ref, watch, type Ref } from "vue"
import { api, postAction } from "../api"
import type { FlowConfirm, TeamMember, TeamMemberView } from "../types"
import { useLiveUpdates } from "./useLiveUpdates"

export function useNextThing(teamMemberId: Ref<string>) {
  const teamMembers = ref<TeamMember[]>([])
  const view = ref<TeamMemberView | null>(null)
  const error = ref<string | null>(null)
  const loading = ref(true)

  async function loadTeamMembers() {
    const response = await fetch(api("/api/people"))
    if (!response.ok) {
      throw new Error(`API answered ${response.status}`)
    }
    teamMembers.value = (await response.json()) as TeamMember[]
  }

  async function load() {
    loading.value = true
    error.value = null
    try {
      if (teamMembers.value.length === 0) {
        await loadTeamMembers()
      }
      if (teamMemberId.value === "") {
        view.value = null
        return
      }
      const response = await fetch(
        api(`/api/people/${encodeURIComponent(teamMemberId.value)}/next`),
      )
      if (!response.ok) {
        throw new Error(`API answered ${response.status}`)
      }
      view.value = (await response.json()) as TeamMemberView
    } catch (cause) {
      error.value = cause instanceof Error ? cause.message : String(cause)
    } finally {
      loading.value = false
    }
  }

  async function act(path: string, body: Record<string, unknown>): Promise<FlowConfirm | null> {
    const confirm = await postAction(path, body)
    if (!confirm) {
      await load()
    }
    return confirm
  }

  const pull = (station: string, reason?: string) =>
    act("/api/pull", { station, person: teamMemberId.value, reason })

  const finish = (station: string, piece: string, reason?: string) =>
    act("/api/finish", { station, piece, reason })

  const repair = (rework: string) => act("/api/rework/repair", { rework })

  const assign = (kind: "piece" | "rework", id: string, teamMember: string) =>
    act("/api/assign", { kind, id, person: teamMember })

  const raiseAndon = (station: string) => act("/api/andon", { station, person: teamMemberId.value })

  const closeAndon = (station: string) =>
    act("/api/andon/close", { station, person: teamMemberId.value })

  watch(teamMemberId, load)
  onMounted(load)
  useLiveUpdates(load)

  return {
    teamMembers,
    view,
    error,
    loading,
    load,
    pull,
    finish,
    repair,
    assign,
    raiseAndon,
    closeAndon,
  }
}
