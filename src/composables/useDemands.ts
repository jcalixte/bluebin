import { onMounted, ref } from "vue"
import type { Demand } from "../types"

export function useDemands() {
  const demands = ref<Demand[]>([])
  const error = ref<string | null>(null)
  const loading = ref(true)

  async function load() {
    loading.value = true
    error.value = null
    try {
      const response = await fetch("/api/demands")
      if (!response.ok) {
        throw new Error(`API answered ${response.status}`)
      }
      demands.value = (await response.json()) as Demand[]
    } catch (cause) {
      error.value = cause instanceof Error ? cause.message : String(cause)
    } finally {
      loading.value = false
    }
  }

  onMounted(load)

  return { demands, error, loading, load }
}
