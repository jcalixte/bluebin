import { onMounted, ref } from "vue"
import { lineFetch } from "../api"
import type { Andon, Demand } from "../types"
import { useLiveUpdates } from "./useLiveUpdates"
import { useLoad } from "./useLoad"

export function useDemands() {
  const demands = ref<Demand[]>([])
  const andons = ref<Andon[]>([])

  const { error, loading, load } = useLoad(
    async () => {
      const [demandsResponse, andonsResponse] = await Promise.all([
        lineFetch("/api/demands"),
        lineFetch("/api/andons"),
      ])
      for (const response of [demandsResponse, andonsResponse]) {
        if (!response.ok) {
          throw new Error(`API answered ${response.status}`)
        }
      }
      return {
        demands: (await demandsResponse.json()) as Demand[],
        andons: (await andonsResponse.json()) as Andon[],
      }
    },
    (value) => {
      demands.value = value.demands
      andons.value = value.andons
    },
  )

  onMounted(load)
  useLiveUpdates(load)

  return { demands, andons, error, loading, load }
}
