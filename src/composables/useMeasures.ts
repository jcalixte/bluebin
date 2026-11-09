import { onMounted, reactive, ref, watch } from "vue"
import { lineFetch } from "../api"
import type { LineChange, Measures, WeekHistory, WeekMeasures } from "../types"
import { useLiveUpdates } from "./useLiveUpdates"
import { useLoad } from "./useLoad"
import { useWorkingCalendar } from "./useWorkingCalendar"

export type Period = { from: string; to: string }

export type CompareMode = "change" | "custom"

// Days are UTC days, as the API counts them.
const dayMs = 86_400_000
const time = (day: string) => Date.parse(`${day}T00:00:00Z`)
const dayOf = (ms: number) => new Date(ms).toISOString().slice(0, 10)

function daysAgo(days: number) {
  return dayOf(Date.now() - days * dayMs)
}

/** Both ends included. */
export function periodDays(period: Period) {
  return Math.round((time(period.to) - time(period.from)) / dayMs) + 1
}

/**
 * Two periods of the same length on each side of the day of a change: After starts that
 * day. A recent change, or one soon after the Line started, shortens both, so the totals
 * stay comparable.
 */
export function periodsAround(day: string, days: number, today: string, started: string | null) {
  const before = started === null ? days : periodDays({ from: started, to: day }) - 1
  const length = Math.max(1, Math.min(days, before, periodDays({ from: day, to: today })))
  return {
    before: { from: dayOf(time(day) - length * dayMs), to: dayOf(time(day) - dayMs) },
    after: { from: day, to: dayOf(time(day) + (length - 1) * dayMs) },
  }
}

export type PeriodProblem = "missing" | "order" | "future" | "before_start"

export function periodProblem(
  period: Period,
  started: string | null,
  today: string,
): PeriodProblem | null {
  if (period.from === "" || period.to === "") return "missing"
  if (period.from > period.to) return "order"
  if (period.to > today) return "future"
  if (started !== null && period.from < started) return "before_start"
  return null
}

async function fetchMeasures(period: Period) {
  const query = new URLSearchParams({ from: period.from, to: period.to })
  const response = await lineFetch(`/api/measures?${query}`)
  if (!response.ok) {
    throw new Error(`API answered ${response.status}`)
  }
  return (await response.json()) as Measures
}

async function fetchWeeks(count: number) {
  const response = await lineFetch(`/api/measures/weeks?weeks=${count}`)
  if (!response.ok) {
    throw new Error(`API answered ${response.status}`)
  }
  return (await response.json()) as WeekHistory
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
  const weekCount = ref(12)
  const weeks = ref<WeekMeasures[]>([])
  /** The Line's first day; unknown until the weeks load. */
  const startedOn = ref<string | null>(null)
  const today = daysAgo(0)
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

  const {
    error: weeksError,
    loading: weeksLoading,
    load: loadWeeks,
  } = useLoad(
    () => fetchWeeks(weekCount.value),
    (value) => {
      weeks.value = value.weeks
      startedOn.value = value.startedOn
    },
  )

  async function load() {
    const problem = [before, after].some((one) => periodProblem(one, startedOn.value, today))
    if (!ready || problem) return
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
    const periods = periodsAround(chosen.at.slice(0, 10), days.value, today, startedOn.value)
    Object.assign(before, periods.before)
    Object.assign(after, periods.after)
  }

  /** On a Line younger than the default periods, its days so far split in two halves. */
  function fitDefaults() {
    if (startedOn.value === null || periodProblem(before, startedOn.value, today) === null) return
    const half = Math.floor(periodDays({ from: startedOn.value, to: today }) / 2)
    if (half < 1) return
    Object.assign(before, {
      from: startedOn.value,
      to: dayOf(time(startedOn.value) + (half - 1) * dayMs),
    })
    Object.assign(after, { from: dayOf(time(today) - (half - 1) * dayMs), to: today })
  }

  const { calendar, calendarError, saveCalendar } = useWorkingCalendar(() =>
    Promise.all([load(), loadWeeks()]),
  )

  watch([before, after], periodsChanged)
  watch([mode, changeAt, days], aroundChange)
  watch(weekCount, loadWeeks)
  onMounted(async () => {
    await Promise.all([loadChanges(), loadWeeks()])
    const latest = changes.value[0]
    if (latest) {
      mode.value = "change"
      changeAt.value = latest.at
      aroundChange()
    } else fitDefaults()
    ready = true
    await load()
  })
  useLiveUpdates(async () => {
    await Promise.all([loadChanges(), loadWeeks()])
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
    startedOn,
    today,
    weekCount,
    weeks,
    weeksError,
    weeksLoading,
    measures,
    error,
    loading,
    calendar,
    calendarError,
    saveCalendar,
  }
}
