import { onMounted, ref } from "vue"
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

  /** Posts one flow action. A broken pull rule comes back as a confirmation to
   *  ask for; anything else either reloads the Value Stream or throws. */
  async function act(path: string, body: Record<string, unknown>): Promise<FlowConfirm | null> {
    const response = await fetch(path, {
      method: "POST",
      headers: { "content-type": "application/json" },
      body: JSON.stringify(body),
    })
    if (response.status === 409) {
      const answer = (await response.json()) as Partial<FlowConfirm> & { message: string }
      if (answer.confirm) {
        return { confirm: answer.confirm, message: answer.message }
      }
      throw new Error(answer.message)
    }
    if (!response.ok) {
      throw new Error(await response.text())
    }
    await load()
    return null
  }

  /** A Work Station spends a Kanban and takes the first Piece upstream. */
  const pull = (station: string, reason?: string) => act("/api/pull", { station, reason })

  /** The Piece leaves the hands of the Work Station for one of its Blue Bins. */
  const finish = (station: string, piece: string, reason?: string) =>
    act("/api/finish", { station, piece, reason })

  /** Production pulls the Piece out of the last Blue Bin of the chain. */
  const deliver = (piece: string) => act("/api/deliver", { piece })

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

  return { valueStream, error, loading, load, renameStep, pull, finish, deliver }
}
