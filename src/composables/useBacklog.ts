import { onMounted, ref } from "vue"
import { api, postAction } from "../api"
import type { Backlog } from "../types"
import { useLiveUpdates } from "./useLiveUpdates"

export function useBacklog() {
  const backlog = ref<Backlog | null>(null)
  const error = ref<string | null>(null)
  const loading = ref(true)

  async function load() {
    loading.value = true
    error.value = null
    try {
      const response = await fetch(api("/api/backlog"))
      if (!response.ok) {
        throw new Error(`API answered ${response.status}`)
      }
      backlog.value = (await response.json()) as Backlog
    } catch (cause) {
      error.value = cause instanceof Error ? cause.message : String(cause)
    } finally {
      loading.value = false
    }
  }

  async function makeUrgent(piece: string, reason?: string) {
    const confirm = await postAction("/api/backlog/urgent", { piece, reason })
    if (!confirm) {
      await load()
    }
    return confirm
  }

  onMounted(load)
  useLiveUpdates(load)

  return { backlog, error, loading, makeUrgent }
}
