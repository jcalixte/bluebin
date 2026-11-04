import { onMounted, ref } from "vue"
import type { ValueStream } from "../types"

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

  return { valueStream, error, loading, load, renameStep }
}
