import { onMounted, ref, watch, type Ref } from "vue"
import { lineFetch, postAction } from "../api"
import type { FlowConfirm, TeamMember, TeamMemberView } from "../types"
import { useLiveUpdates } from "./useLiveUpdates"
import { useLoad } from "./useLoad"

export function useNextThing(teamMemberId: Ref<string>) {
  const teamMembers = ref<TeamMember[]>([])
  const view = ref<TeamMemberView | null>(null)

  async function loadTeamMembers() {
    const response = await lineFetch("/api/team-members")
    if (!response.ok) {
      throw new Error(`API answered ${response.status}`)
    }
    teamMembers.value = (await response.json()) as TeamMember[]
  }

  const { error, loading, load } = useLoad(
    async () => {
      if (teamMembers.value.length === 0) {
        await loadTeamMembers()
      }
      if (teamMemberId.value === "") {
        return null
      }
      const response = await lineFetch(
        `/api/team-members/${encodeURIComponent(teamMemberId.value)}/next`,
      )
      if (!response.ok) {
        throw new Error(`API answered ${response.status}`)
      }
      return (await response.json()) as TeamMemberView
    },
    (value) => (view.value = value),
  )

  async function act(path: string, body: Record<string, unknown>): Promise<FlowConfirm | null> {
    const confirm = await postAction(path, body)
    if (!confirm) {
      await load()
    }
    return confirm
  }

  const pull = (station: string, reason?: string) =>
    act("/api/pull", { station, teamMember: teamMemberId.value, reason })

  const finish = (station: string, piece: string, reason?: string) =>
    act("/api/finish", { station, piece, reason })

  const repair = (rework: string) => act("/api/rework/repair", { rework })

  const helpTheRework = (rework: string) =>
    act("/api/help", { rework, teamMember: teamMemberId.value })

  const stopHelping = () => act("/api/help/stop", { teamMember: teamMemberId.value })

  const assign = (kind: "piece" | "rework", id: string, teamMember: string) =>
    act("/api/assign", { kind, id, teamMember })

  const raiseAndon = (station: string) =>
    act("/api/andon", { station, teamMember: teamMemberId.value })

  const closeAndon = (station: string) =>
    act("/api/andon/close", { station, teamMember: teamMemberId.value })

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
    helpTheRework,
    stopHelping,
    assign,
    raiseAndon,
    closeAndon,
  }
}
