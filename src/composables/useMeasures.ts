import { onMounted, reactive, ref, watch } from "vue"
import type { Measures, WorkingCalendar } from "../types"
import { useLiveUpdates } from "./useLiveUpdates"

export type Period = { from: string; to: string }

function daysAgo(days: number) {
  const date = new Date()
  date.setDate(date.getDate() - days)
  const month = String(date.getMonth() + 1).padStart(2, "0")
  const day = String(date.getDate()).padStart(2, "0")
  return `${date.getFullYear()}-${month}-${day}`
}

export function isValidPeriod(period: Period) {
  return period.from !== "" && period.to !== "" && period.from <= period.to
}

async function fetchMeasures(period: Period) {
  const query = new URLSearchParams({ from: period.from, to: period.to })
  const response = await fetch(`/api/measures?${query}`)
  if (!response.ok) {
    throw new Error(`API answered ${response.status}`)
  }
  return (await response.json()) as Measures
}

export function useMeasures() {
  const before = reactive<Period>({ from: daysAgo(13), to: daysAgo(7) })
  const after = reactive<Period>({ from: daysAgo(6), to: daysAgo(0) })
  const measures = ref<{ before: Measures; after: Measures } | null>(null)
  const error = ref<string | null>(null)
  const loading = ref(true)
  let latest = 0

  async function load() {
    if (!isValidPeriod(before) || !isValidPeriod(after)) return
    const request = ++latest
    loading.value = true
    error.value = null
    try {
      const [a, b] = await Promise.all([fetchMeasures(before), fetchMeasures(after)])
      if (request === latest) {
        measures.value = { before: a, after: b }
      }
    } catch (cause) {
      if (request === latest) {
        error.value = cause instanceof Error ? cause.message : String(cause)
      }
    } finally {
      if (request === latest) {
        loading.value = false
      }
    }
  }

  const calendar = ref<WorkingCalendar | null>(null)
  const calendarError = ref<string | null>(null)

  async function loadCalendar() {
    calendarError.value = null
    try {
      const response = await fetch("/api/calendar")
      if (!response.ok) {
        throw new Error(`API answered ${response.status}`)
      }
      calendar.value = (await response.json()) as WorkingCalendar
    } catch (cause) {
      calendarError.value = cause instanceof Error ? cause.message : String(cause)
    }
  }

  async function saveCalendar(next: WorkingCalendar) {
    const response = await fetch("/api/calendar", {
      method: "PUT",
      headers: { "content-type": "application/json" },
      body: JSON.stringify(next),
    })
    if (!response.ok) {
      throw new Error((await response.text()) || `API answered ${response.status}`)
    }
    calendar.value = (await response.json()) as WorkingCalendar
    await load()
  }

  watch([before, after], load)
  onMounted(() => Promise.all([load(), loadCalendar()]))
  useLiveUpdates(load)

  return { before, after, measures, error, loading, calendar, calendarError, saveCalendar }
}
