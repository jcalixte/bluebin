import { ref } from "vue"
import { lineFetch } from "../api"
import type { Labels } from "../types"

const labels = ref<Labels>({
  demand: "Demand",
  demands: "Demands",
  piece: "Piece",
  pieces: "Pieces",
})
let loaded: Promise<void> | null = null

async function fetchLabels() {
  try {
    const response = await lineFetch("/api/labels")
    if (response.ok) {
      labels.value = (await response.json()) as Labels
    }
  } catch {
    return
  }
}

/** Until the API answers, the labels are the defaults. */
export function useLabels() {
  loaded ??= fetchLabels()

  function reload() {
    loaded = fetchLabels()
    return loaded
  }

  return { labels, reload }
}
