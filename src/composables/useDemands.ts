import { onMounted, ref } from "vue"
import type { Andon, Demand } from "../types"
import { useLiveUpdates } from "./useLiveUpdates"

export function useDemands() {
  const demands = ref<Demand[]>([])
  const andons = ref<Andon[]>([])
  const error = ref<string | null>(null)
  const loading = ref(true)

  async function load() {
    loading.value = true
    error.value = null
    try {
      const [demandsResponse, andonsResponse] = await Promise.all([
        fetch("/api/demands"),
        fetch("/api/andons"),
      ])
      for (const response of [demandsResponse, andonsResponse]) {
        if (!response.ok) {
          throw new Error(`API answered ${response.status}`)
        }
      }
      demands.value = (await demandsResponse.json()) as Demand[]
      andons.value = (await andonsResponse.json()) as Andon[]
    } catch (cause) {
      error.value = cause instanceof Error ? cause.message : String(cause)
    } finally {
      loading.value = false
    }
  }

  onMounted(load)
  useLiveUpdates(load)

  return { demands, andons, error, loading, load }
}
