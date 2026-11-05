import { onMounted, ref } from "vue"
import { postAction } from "../api"
import type { FlowConfirm, ValueStream } from "../types"
import { useLiveUpdates } from "./useLiveUpdates"

export function useValueStream() {
  const valueStream = ref<ValueStream | null>(null)
  const error = ref<string | null>(null)
  const loading = ref(true)

  async function load() {
    loading.value = true
    error.value = null
    try {
      const response = await fetch("/api/value-stream")
      if (!response.ok) {
        throw new Error(`API answered ${response.status}`)
      }
      valueStream.value = (await response.json()) as ValueStream
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

  const pull = (station: string, person?: string, reason?: string) =>
    act("/api/pull", { station, person, reason })

  const finish = (station: string, piece: string, reason?: string) =>
    act("/api/finish", { station, piece, reason })

  const deliver = (piece: string) => act("/api/deliver", { piece })

  const raiseRework = (station: string, piece: string, madeBy: string, description: string) =>
    act("/api/rework", { station, piece, madeBy, description })

  const repairRework = (rework: string) => act("/api/rework/repair", { rework })

  const assign = (kind: "piece" | "rework", id: string, person: string) =>
    act("/api/assign", { kind, id, person })

  const raiseAndon = (station: string, person?: string) => act("/api/andon", { station, person })

  const closeAndon = (station: string, person: string) =>
    act("/api/andon/close", { station, person })

  /** The server trims the name, so its answer wins over ours. */
  async function renameStep(position: number, name: string) {
    const response = await fetch(`/api/steps/${position}`, {
      method: "PUT",
      headers: { "content-type": "application/json" },
      body: JSON.stringify({ name }),
    })
    if (!response.ok) {
      throw new Error(await response.text())
    }
    const saved = (await response.json()) as { position: number; name: string }
    const step = valueStream.value?.steps.find((one) => one.position === saved.position)
    if (step) {
      step.name = saved.name
    }
  }

  onMounted(load)
  useLiveUpdates(load)

  return {
    valueStream,
    error,
    loading,
    load,
    renameStep,
    pull,
    finish,
    deliver,
    raiseRework,
    repairRework,
    assign,
    raiseAndon,
    closeAndon,
  }
}
