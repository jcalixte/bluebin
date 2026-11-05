import { onMounted, ref } from "vue"
import { postAction } from "../api"
import type { FlowConfirm, ValueStream } from "../types"

/** Loads the Value Stream: Work Stations, Blue Bins, Kanbans, People, Rework. */
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

  /** Posts one flow action, then reloads the Value Stream unless a broken
   *  pull rule asks for a confirmation first. */
  async function act(path: string, body: Record<string, unknown>): Promise<FlowConfirm | null> {
    const confirm = await postAction(path, body)
    if (!confirm) {
      await load()
    }
    return confirm
  }

  /** A Work Station spends a Kanban and takes the first Piece upstream. The
   *  Person who takes it in hand is the author a later Rework goes to. */
  const pull = (station: string, person?: string, reason?: string) =>
    act("/api/pull", { station, person, reason })

  /** The Piece leaves the hands of the Work Station for one of its Blue Bins. */
  const finish = (station: string, piece: string, reason?: string) =>
    act("/api/finish", { station, piece, reason })

  /** Production pulls the Piece out of the last Blue Bin of the chain. */
  const deliver = (piece: string) => act("/api/deliver", { piece })

  /** The Work Station holding the Piece raises a Rework against the Work
   *  Station that made the defect (F12). */
  const raiseRework = (station: string, piece: string, madeBy: string, description: string) =>
    act("/api/rework", { station, piece, madeBy, description })

  /** The defect is repaired: the Rework closes and the paused Piece resumes. */
  const repairRework = (rework: string) => act("/api/rework/repair", { rework })

  /** Hand a Piece in hand or a Rework to another Person of the Work Station. */
  const assign = (kind: "piece" | "rework", id: string, person: string) =>
    act("/api/assign", { kind, id, person })

  /** Rename one step. The server trims and validates; its answer wins. */
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
  }
}
