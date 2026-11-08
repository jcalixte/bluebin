import { onMounted, ref } from "vue"
import { lineFetch, postAction } from "../api"
import type { FlowConfirm, Line } from "../types"
import { useLiveUpdates } from "./useLiveUpdates"
import { useLoad } from "./useLoad"

export function useLine() {
  const line = ref<Line | null>(null)

  const { error, loading, load } = useLoad(
    async () => {
      const response = await lineFetch("/api/line")
      if (!response.ok) {
        throw new Error(`API answered ${response.status}`)
      }
      return (await response.json()) as Line
    },
    (value) => (line.value = value),
  )

  async function act(path: string, body: Record<string, unknown>): Promise<FlowConfirm | null> {
    const confirm = await postAction(path, body)
    if (!confirm) {
      await load()
    }
    return confirm
  }

  const pull = (station: string, teamMember?: string, reason?: string) =>
    act("/api/pull", { station, teamMember, reason })

  const finish = (station: string, piece: string, reason?: string) =>
    act("/api/finish", { station, piece, reason })

  const deploy = (piece: string, hold = false) => act("/api/deploy", { piece, hold })

  const release = (pieces: string[]) => act("/api/release", { pieces })

  const raiseRework = (station: string, piece: string, madeBy: string, description: string) =>
    act("/api/rework", { station, piece, madeBy, description })

  const repairRework = (rework: string) => act("/api/rework/repair", { rework })

  const assign = (kind: "piece" | "rework", id: string, teamMember: string) =>
    act("/api/assign", { kind, id, teamMember })

  const helpTheRework = (rework: string, teamMember: string) =>
    act("/api/help", { rework, teamMember })

  const stopHelping = (teamMember: string) => act("/api/help/stop", { teamMember })

  const raiseAndon = (station: string, teamMember?: string) =>
    act("/api/andon", { station, teamMember })

  const closeAndon = (station: string, teamMember: string) =>
    act("/api/andon/close", { station, teamMember })

  /** The server trims the name, so its answer wins over ours. */
  async function renameStep(position: number, name: string) {
    const response = await lineFetch(`/api/steps/${position}`, {
      method: "PUT",
      headers: { "content-type": "application/json" },
      body: JSON.stringify({ name }),
    })
    if (!response.ok) {
      throw new Error((await response.text()) || `API answered ${response.status}`)
    }
    const saved = (await response.json()) as { position: number; name: string }
    const step = line.value?.steps.find((one) => one.position === saved.position)
    if (step) {
      step.name = saved.name
    }
  }

  onMounted(load)
  useLiveUpdates(load)

  return {
    line,
    error,
    loading,
    load,
    renameStep,
    pull,
    finish,
    deploy,
    release,
    raiseRework,
    repairRework,
    assign,
    helpTheRework,
    stopHelping,
    raiseAndon,
    closeAndon,
  }
}
