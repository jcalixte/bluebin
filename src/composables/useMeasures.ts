import { onMounted, reactive, ref, watch } from "vue"
import { lineFetch } from "../api"
import type { LineChange, Measures } from "../types"
import { useLiveUpdates } from "./useLiveUpdates"
import { useLoad } from "./useLoad"
import { useWorkingCalendar } from "./useWorkingCalendar"

export type Period = { from: string; to: string }

/** How the two periods are picked: around a dated Line change, or by hand. */
export type CompareMode = "change" | "custom"

// Days are UTC days, as the API counts them.
const dayMs = 86_400_000
const time = (day: string) => Date.parse(`${day}T00:00:00Z`)
const dayOf = (ms: number) => new Date(ms).toISOString().slice(0, 10)

function daysAgo(days: number) {
  return dayOf(Date.now() - days * dayMs)
}

/** The number of days of a period, both ends included. */
export function periodDays(period: Period) {
  return Math.round((time(period.to) - time(period.from)) / dayMs) + 1
}

/**
 * Two periods of the same length on each side of the day of a change: After starts that
 * day. A recent change shortens both, so the totals stay comparable.
 */
export function periodsAround(day: string, days: number, today: string) {
  const length = Math.max(1, Math.min(days, periodDays({ from: day, to: today })))
  return {
    before: { from: dayOf(time(day) - length * dayMs), to: dayOf(time(day) - dayMs) },
    after: { from: day, to: dayOf(time(day) + (length - 1) * dayMs) },
  }
}

export function isValidPeriod(period: Period) {
  return period.from !== "" && period.to !== "" && period.from <= period.to
}

async function fetchMeasures(period: Period) {
  const query = new URLSearchParams({ from: period.from, to: period.to })
  const response = await lineFetch(`/api/measures?${query}`)
  if (!response.ok) {
    throw new Error(`API answered ${response.status}`)
  }
  return (await response.json()) as Measures
}

async function fetchLineChanges() {
  const response = await lineFetch("/api/line-changes")
  if (!response.ok) {
    throw new Error(`API answered ${response.status}`)
  }
  return (await response.json()) as LineChange[]
}

export function useMeasures() {
  const before = reactive<Period>({ from: daysAgo(13), to: daysAgo(7) })
  const after = reactive<Period>({ from: daysAgo(6), to: daysAgo(0) })
  const measures = ref<{ before: Measures; after: Measures } | null>(null)
  const changes = ref<LineChange[]>([])
  const mode = ref<CompareMode>("custom")
  const changeAt = ref<string | null>(null)
  const days = ref(7)
  let ready = false
  let shown = ""

  const {
    error,
    loading,
    load: read,
  } = useLoad(
    async () => {
      const [a, b] = await Promise.all([fetchMeasures(before), fetchMeasures(after)])
      return { before: a, after: b }
    },
    (value) => (measures.value = value),
  )

  async function load() {
    if (!ready || !isValidPeriod(before) || !isValidPeriod(after)) return
    shown = JSON.stringify([before, after])
    await read()
  }

  /** A watched change of the periods that `load` already read is not read again. */
  function periodsChanged() {
    if (JSON.stringify([before, after]) !== shown) void load()
  }

  /** Without the list, the periods are still picked by hand. */
  async function loadChanges() {
    changes.value = await fetchLineChanges().catch(() => changes.value)
  }

  function aroundChange() {
    const chosen = changes.value.find((one) => one.at === changeAt.value)
    if (mode.value !== "change" || !chosen) return
    const periods = periodsAround(chosen.at.slice(0, 10), days.value, daysAgo(0))
    Object.assign(before, periods.before)
    Object.assign(after, periods.after)
  }

  const { calendar, calendarError, saveCalendar } = useWorkingCalendar(load)

  watch([before, after], periodsChanged)
  watch([mode, changeAt, days], aroundChange)
  onMounted(async () => {
    await loadChanges()
    const latest = changes.value[0]
    if (latest) {
      mode.value = "change"
      changeAt.value = latest.at
      aroundChange()
    }
    ready = true
    await load()
  })
  useLiveUpdates(async () => {
    await loadChanges()
    aroundChange()
    await load()
  })

  return {
    before,
    after,
    changes,
    mode,
    changeAt,
    days,
    measures,
    error,
    loading,
    calendar,
    calendarError,
    saveCalendar,
  }
}
