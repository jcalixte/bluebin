import { onMounted, ref } from "vue"
import { lineFetch, postAction } from "../api"
import type { Backlog } from "../types"
import type { RouteInput } from "../wire"
import { useLiveUpdates } from "./useLiveUpdates"
import { useLoad } from "./useLoad"

export function useBacklog() {
  const backlog = ref<Backlog | null>(null)

  const { error, loading, load } = useLoad(
    async () => {
      const response = await lineFetch("/api/backlog")
      if (!response.ok) {
        throw new Error(`API answered ${response.status}`)
      }
      return (await response.json()) as Backlog
    },
    (value) => (backlog.value = value),
  )

  async function makeUrgent(piece: string, reason?: string) {
    const confirm = await postAction("/api/backlog/urgent", { piece, reason })
    if (!confirm) {
      await load()
    }
    return confirm
  }

  async function changeRoute(piece: string, skips: string[]) {
    const response = await lineFetch("/api/backlog/route", {
      method: "POST",
      headers: { "content-type": "application/json" },
      body: JSON.stringify({ piece, skips } satisfies RouteInput),
    })
    if (!response.ok) {
      throw new Error((await response.text()) || `API answered ${response.status}`)
    }
    await load()
  }

  onMounted(load)
  useLiveUpdates(load)

  return { backlog, error, loading, makeUrgent, changeRoute }
}
