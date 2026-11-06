<script setup lang="ts">
import { computed, ref } from "vue"
import WorkingCalendarCard from "../components/WorkingCalendarCard.vue"
import { useLabels } from "../composables/useLabels"
import { isValidPeriod, useMeasures, type Period } from "../composables/useMeasures"
import type { DemandMeasures, Duration, StationMeasures, TimeView } from "../types"

const { before, after, measures, error, loading, calendar, calendarError, saveCalendar } =
  useMeasures()

const { labels } = useLabels()

const view = ref<TimeView>("calendar")
const timeViews = [
  { id: "calendar", label: "Calendar Time" },
  { id: "working", label: "Working Time" },
] as const

const periods = [
  { name: "Before", period: before },
  { name: "After", period: after },
] as const

const ruleLabels: Record<string, string> = {
  pull_without_kanban: "Pull without a Kanban",
  second_piece_in_a_blue_bin: "Second Piece in a Blue Bin",
  pull_with_an_open_rework: "Pull with an open Rework",
  reorder_heijunka_sequence: "Reorder of the Heijunka Sequence",
}

function ruleLabel(rule: string) {
  return ruleLabels[rule] ?? rule
}

function pick(duration: Duration | null | undefined) {
  return duration?.[view.value] ?? null
}

function hours(value: number | null) {
  if (value === null) return "—"
  const minutes = Math.round(value * 60)
  return Math.abs(minutes) < 60 ? `${minutes} min` : `${value.toFixed(1)} h`
}

function sign(difference: number) {
  return difference > 0 ? "+" : "−"
}

function hoursChange(a: number | null, b: number | null) {
  if (a === null || b === null) return "—"
  const difference = b - a
  if (Math.round(difference * 60) === 0) return "0 min"
  return `${sign(difference)}${hours(Math.abs(difference))}`
}

function countChange(a: number, b: number) {
  const difference = b - a
  return difference === 0 ? "0" : `${sign(difference)}${Math.abs(difference)}`
}

function percent(share: number | null | undefined) {
  return share === null || share === undefined ? "—" : `${Math.round(share * 100)} %`
}

function dayLabel(day: string) {
  return new Date(`${day}T12:00:00`).toLocaleDateString(undefined, {
    day: "numeric",
    month: "short",
  })
}

function periodLabel(period: Period) {
  return `${dayLabel(period.from)} – ${dayLabel(period.to)}`
}

function atLabel(at: string) {
  return new Date(at).toLocaleString(undefined, {
    weekday: "short",
    day: "numeric",
    month: "short",
    hour: "2-digit",
    minute: "2-digit",
  })
}

const summary = computed(() => {
  if (!measures.value) return []
  const a = measures.value.before.pieces
  const b = measures.value.after.pieces
  const stationsA = measures.value.before.stations
  const stationsB = measures.value.after.stations
  const andonsA = stationsA.reduce((total, station) => total + station.andons, 0)
  const andonsB = stationsB.reduce((total, station) => total + station.andons, 0)
  const stoppedA = pick(measures.value.before.andonTime)
  const stoppedB = pick(measures.value.after.andonTime)
  const durations = [
    { label: "Lead Time", a: pick(a.leadTime), b: pick(b.leadTime) },
    { label: "Touch Time", a: pick(a.touchTime), b: pick(b.touchTime) },
    { label: "Stagnation Time", a: pick(a.stagnationTime), b: pick(b.stagnationTime) },
    { label: "Backlog time", a: pick(a.backlogTime), b: pick(b.backlogTime) },
  ]
  return [
    {
      label: "Pieces reached production",
      before: String(a.count),
      after: String(b.count),
      change: countChange(a.count, b.count),
    },
    ...durations.map((row) => ({
      label: `${row.label} (average per Piece)`,
      before: hours(row.a),
      after: hours(row.b),
      change: hoursChange(row.a, row.b),
    })),
    {
      label: "Andons raised",
      before: String(andonsA),
      after: String(andonsB),
      change: countChange(andonsA, andonsB),
    },
    {
      label: "Andon Time (any Work Station stopped)",
      before: hours(stoppedA),
      after: hours(stoppedB),
      change: hoursChange(stoppedA, stoppedB),
    },
  ]
})

/** The share of Demands to deliver by their due date. */
const onTimeTarget = 0.9

const onTime = computed(() => {
  if (!measures.value) return []
  const { before, after } = measures.value
  return [
    { name: "Before", period: before },
    { name: "After", period: after },
  ].map(({ name, period }) => {
    const { delivered, onTime: count } = period.onTime
    const share = delivered === 0 ? null : count / delivered
    return {
      name,
      period: periodLabel(period),
      delivered,
      onTime: count,
      // Floor, so a share under the target never reads as the target.
      percent: share === null ? null : Math.floor(share * 100),
      met: share !== null && share >= onTimeTarget,
    }
  })
})

type Paired<T> = { id: string; first: T; before?: T; after?: T }

function pair<T extends { id: string }>(a: T[], b: T[]): Paired<T>[] {
  const rows = new Map<string, Paired<T>>()
  for (const item of a) rows.set(item.id, { id: item.id, first: item, before: item })
  for (const item of b) {
    const row = rows.get(item.id)
    if (row) row.after = item
    else rows.set(item.id, { id: item.id, first: item, after: item })
  }
  return [...rows.values()]
}

const demands = computed<Paired<DemandMeasures>[]>(() =>
  measures.value ? pair(measures.value.before.demands, measures.value.after.demands) : [],
)

const showDemandLeadTime = computed(() =>
  demands.value.some(
    (row) => pick(row.before?.demandLeadTime) !== null || pick(row.after?.demandLeadTime) !== null,
  ),
)

const stations = computed<Paired<StationMeasures>[]>(() =>
  measures.value
    ? pair(measures.value.before.stations, measures.value.after.stations).sort(
        (x, y) =>
          x.first.position - y.first.position ||
          (x.first.branch ?? "").localeCompare(y.first.branch ?? ""),
      )
    : [],
)

const deviationCounts = computed(() => {
  if (!measures.value) return []
  const count = (list: { rule: string; count: number }[], rule: string) =>
    list.find((one) => one.rule === rule)?.count ?? 0
  const a = measures.value.before.deviations.byRule
  const b = measures.value.after.deviations.byRule
  const rules = new Set([...Object.keys(ruleLabels), ...a.map((one) => one.rule)])
  for (const one of b) rules.add(one.rule)
  return [...rules].map((rule) => ({
    rule,
    before: count(a, rule),
    after: count(b, rule),
  }))
})

const deviationList = computed(() =>
  measures.value
    ? [
        ...measures.value.before.deviations.list.map((one) => ({ period: "Before", ...one })),
        ...measures.value.after.deviations.list.map((one) => ({ period: "After", ...one })),
      ]
    : [],
)
</script>

<template>
  <section>
    <header class="mb-6 flex flex-wrap items-end justify-between gap-4">
      <div>
        <h2 class="text-xl font-semibold">Measures</h2>
        <p class="text-sm opacity-70">
          Lead Time, Touch Time and Stagnation Time of the Pieces that reached production, before
          and after a change
        </p>
      </div>
      <div class="tabs tabs-box tabs-sm bg-base-100" role="group" aria-label="Time view">
        <button
          v-for="option in timeViews"
          :key="option.id"
          type="button"
          class="tab"
          :class="view === option.id ? 'tab-active font-medium' : 'opacity-70'"
          :aria-pressed="view === option.id"
          @click="view = option.id"
        >
          {{ option.label }}
        </button>
      </div>
    </header>

    <div class="mb-6 grid gap-4 md:grid-cols-2">
      <div
        v-for="one in periods"
        :key="one.name"
        class="card border border-base-300 bg-base-100 shadow-sm"
      >
        <div class="card-body gap-3 p-5">
          <h3 class="card-title text-base">{{ one.name }}</h3>
          <div class="flex flex-wrap gap-4">
            <label class="flex flex-col gap-1 text-sm">
              <span class="font-medium">From</span>
              <input v-model="one.period.from" type="date" class="input input-sm" />
            </label>
            <label class="flex flex-col gap-1 text-sm">
              <span class="font-medium">To (included)</span>
              <input v-model="one.period.to" type="date" class="input input-sm" />
            </label>
          </div>
          <p v-if="!isValidPeriod(one.period)" class="text-sm opacity-70">
            Pick a start date on or before the end date.
          </p>
        </div>
      </div>
    </div>

    <p v-if="loading && !measures" class="flex items-center gap-3 opacity-70">
      <span class="loading loading-spinner loading-sm" />
      Loading the measures…
    </p>

    <div v-else-if="error" class="alert alert-error">
      <span>The API did not answer: {{ error }}</span>
    </div>

    <div v-else-if="measures" class="flex flex-col gap-6">
      <div class="grid gap-6 xl:grid-cols-[minmax(0,3fr)_minmax(0,2fr)]">
        <div class="card border border-base-300 bg-base-100 shadow-sm">
          <div class="card-body gap-3 p-5">
            <h3 class="card-title text-base">Summary</h3>
            <div class="overflow-x-auto">
              <table class="table table-sm">
                <thead>
                  <tr>
                    <th>Measure</th>
                    <th class="text-right">Before · {{ periodLabel(measures.before) }}</th>
                    <th class="text-right">After · {{ periodLabel(measures.after) }}</th>
                    <th class="text-right">Change</th>
                  </tr>
                </thead>
                <tbody>
                  <tr v-for="row in summary" :key="row.label">
                    <th class="font-medium">{{ row.label }}</th>
                    <td class="text-right tabular-nums">{{ row.before }}</td>
                    <td class="text-right tabular-nums">{{ row.after }}</td>
                    <td class="text-right tabular-nums">{{ row.change }}</td>
                  </tr>
                </tbody>
              </table>
            </div>
            <p class="text-xs opacity-60">Touch Time is net time: it is the same in both views.</p>
          </div>
        </div>

        <div v-if="calendarError" class="alert alert-error">
          <span>The Working Calendar did not load: {{ calendarError }}</span>
        </div>
        <WorkingCalendarCard v-else-if="calendar" :calendar="calendar" :save="saveCalendar" />
      </div>

      <div class="card border border-base-300 bg-base-100 shadow-sm">
        <div class="card-body gap-3 p-5">
          <h3 class="card-title text-base">On-time delivery</h3>
          <p class="text-sm opacity-70">
            The share of {{ labels.demands }} delivered by their due date, among those delivered in
            the period. Target: {{ onTimeTarget * 100 }} % or more.
          </p>
          <div class="grid gap-4 md:grid-cols-2">
            <div v-for="row in onTime" :key="row.name" class="rounded-box bg-base-200 p-4">
              <p class="text-xs font-semibold uppercase tracking-wide opacity-70">
                {{ row.name }} · {{ row.period }}
              </p>
              <p v-if="row.percent === null" class="mt-2 opacity-70">
                No {{ labels.demand }} delivered in this period.
              </p>
              <template v-else>
                <p class="mt-2 flex flex-wrap items-center gap-x-3 gap-y-1">
                  <span class="text-3xl font-semibold tabular-nums">{{ row.percent }} %</span>
                  <span
                    class="badge font-medium whitespace-nowrap"
                    :class="row.met ? 'badge-success' : 'badge-error'"
                  >
                    {{ row.met ? "On target" : "Below target" }}
                  </span>
                </p>
                <p class="mt-1 text-sm tabular-nums">
                  {{ row.onTime }} of {{ row.delivered }}
                  <span class="opacity-70">{{ labels.demands }} on time</span>
                </p>
              </template>
            </div>
          </div>
        </div>
      </div>

      <div class="card border border-base-300 bg-base-100 shadow-sm">
        <div class="card-body gap-3 p-5">
          <h3 class="card-title text-base">Per Demand</h3>
          <p class="text-sm opacity-70">Averages per Piece that reached production.</p>
          <p v-if="demands.length === 0" class="opacity-70">No Piece reached production.</p>
          <div v-else class="overflow-x-auto">
            <table class="table table-sm">
              <thead>
                <tr>
                  <th rowspan="2">Demand</th>
                  <th colspan="2" class="text-center">Pieces</th>
                  <th colspan="2" class="text-center">Lead Time</th>
                  <th colspan="2" class="text-center">Touch Time</th>
                  <th colspan="2" class="text-center">Stagnation Time</th>
                  <th v-if="showDemandLeadTime" colspan="2" class="text-center">
                    Demand Lead Time
                  </th>
                </tr>
                <tr>
                  <template v-for="n in showDemandLeadTime ? 5 : 4" :key="n">
                    <th class="text-right">Before</th>
                    <th class="text-right">After</th>
                  </template>
                </tr>
              </thead>
              <tbody>
                <tr v-for="row in demands" :key="row.id">
                  <th class="font-medium">
                    {{ row.first.label }}
                    <span class="block text-xs font-normal opacity-60">{{ row.first.client }}</span>
                  </th>
                  <td class="text-right tabular-nums">{{ row.before?.pieces ?? 0 }}</td>
                  <td class="text-right tabular-nums">{{ row.after?.pieces ?? 0 }}</td>
                  <td class="text-right tabular-nums">{{ hours(pick(row.before?.leadTime)) }}</td>
                  <td class="text-right tabular-nums">{{ hours(pick(row.after?.leadTime)) }}</td>
                  <td class="text-right tabular-nums">{{ hours(pick(row.before?.touchTime)) }}</td>
                  <td class="text-right tabular-nums">{{ hours(pick(row.after?.touchTime)) }}</td>
                  <td class="text-right tabular-nums">
                    {{ hours(pick(row.before?.stagnationTime)) }}
                  </td>
                  <td class="text-right tabular-nums">
                    {{ hours(pick(row.after?.stagnationTime)) }}
                  </td>
                  <template v-if="showDemandLeadTime">
                    <td class="text-right tabular-nums">
                      {{ hours(pick(row.before?.demandLeadTime)) }}
                    </td>
                    <td class="text-right tabular-nums">
                      {{ hours(pick(row.after?.demandLeadTime)) }}
                    </td>
                  </template>
                </tr>
              </tbody>
            </table>
          </div>
          <p v-if="showDemandLeadTime" class="text-xs opacity-60">
            Demand Lead Time is the Lead Time of the whole Demand, known once its last Piece reached
            production.
          </p>
        </div>
      </div>

      <div class="card border border-base-300 bg-base-100 shadow-sm">
        <div class="card-body gap-3 p-5">
          <h3 class="card-title text-base">Per Work Station</h3>
          <p class="text-sm opacity-70">
            Station Lead Time and Touch Time are averages per pass; Starvation Time and Andon Time
            are totals of the period.
          </p>
          <p v-if="stations.length === 0" class="opacity-70">No Work Station.</p>
          <div v-else class="overflow-x-auto">
            <table class="table table-sm">
              <thead>
                <tr>
                  <th rowspan="2">Work Station</th>
                  <th colspan="2" class="text-center">Station Lead Time</th>
                  <th colspan="2" class="text-center">Touch Time</th>
                  <th colspan="2" class="text-center">Touch share</th>
                  <th colspan="2" class="text-center">Starvation Time</th>
                  <th colspan="2" class="text-center">Andon Time</th>
                  <th colspan="2" class="text-center">Deviations / pulls</th>
                </tr>
                <tr>
                  <template v-for="n in 6" :key="n">
                    <th class="text-right">Before</th>
                    <th class="text-right">After</th>
                  </template>
                </tr>
              </thead>
              <tbody>
                <tr v-for="row in stations" :key="row.id">
                  <th class="font-medium">
                    {{ row.first.name }}
                    <span
                      v-if="row.first.branch && row.first.branch !== row.first.name"
                      class="block text-xs font-normal opacity-60"
                    >
                      Branch {{ row.first.branch }}
                    </span>
                  </th>
                  <td class="text-right tabular-nums">
                    {{ hours(pick(row.before?.stationLeadTime)) }}
                  </td>
                  <td class="text-right tabular-nums">
                    {{ hours(pick(row.after?.stationLeadTime)) }}
                  </td>
                  <td class="text-right tabular-nums">{{ hours(pick(row.before?.touchTime)) }}</td>
                  <td class="text-right tabular-nums">{{ hours(pick(row.after?.touchTime)) }}</td>
                  <td class="text-right tabular-nums">{{ percent(row.before?.touchShare) }}</td>
                  <td class="text-right tabular-nums">{{ percent(row.after?.touchShare) }}</td>
                  <td class="text-right tabular-nums">
                    {{ hours(pick(row.before?.starvationTime)) }}
                  </td>
                  <td class="text-right tabular-nums">
                    {{ hours(pick(row.after?.starvationTime)) }}
                  </td>
                  <td class="text-right tabular-nums">
                    {{ hours(pick(row.before?.andonTime)) }}
                    <span v-if="row.before?.andons" class="block text-xs opacity-60">
                      {{ row.before.andons }} raised
                    </span>
                  </td>
                  <td class="text-right tabular-nums">
                    {{ hours(pick(row.after?.andonTime)) }}
                    <span v-if="row.after?.andons" class="block text-xs opacity-60">
                      {{ row.after.andons }} raised
                    </span>
                  </td>
                  <td class="text-right tabular-nums">
                    {{ row.before ? `${row.before.deviations} / ${row.before.pulls}` : "—" }}
                  </td>
                  <td class="text-right tabular-nums">
                    {{ row.after ? `${row.after.deviations} / ${row.after.pulls}` : "—" }}
                  </td>
                </tr>
              </tbody>
            </table>
          </div>
        </div>
      </div>

      <div class="card border border-base-300 bg-base-100 shadow-sm">
        <div class="card-body gap-3 p-5">
          <h3 class="card-title text-base">Deviations</h3>
          <div class="overflow-x-auto">
            <table class="table table-sm">
              <thead>
                <tr>
                  <th>Rule</th>
                  <th class="text-right">Before</th>
                  <th class="text-right">After</th>
                  <th class="text-right">Change</th>
                </tr>
              </thead>
              <tbody>
                <tr v-for="row in deviationCounts" :key="row.rule">
                  <th class="font-medium">{{ ruleLabel(row.rule) }}</th>
                  <td class="text-right tabular-nums">{{ row.before }}</td>
                  <td class="text-right tabular-nums">{{ row.after }}</td>
                  <td class="text-right tabular-nums">{{ countChange(row.before, row.after) }}</td>
                </tr>
              </tbody>
            </table>
          </div>

          <h4 class="mt-2 text-sm font-medium">Each Deviation with its reason</h4>
          <p v-if="deviationList.length === 0" class="opacity-70">No Deviation.</p>
          <div v-else class="overflow-x-auto">
            <table class="table table-sm">
              <thead>
                <tr>
                  <th>Period</th>
                  <th>When</th>
                  <th>Work Station</th>
                  <th>Rule</th>
                  <th>Piece</th>
                  <th>Reason</th>
                </tr>
              </thead>
              <tbody>
                <tr
                  v-for="(one, index) in deviationList"
                  :key="`${one.period}-${one.at}-${one.station}-${index}`"
                >
                  <td>{{ one.period }}</td>
                  <td class="whitespace-nowrap">{{ atLabel(one.at) }}</td>
                  <td>{{ one.stationName }}</td>
                  <td>{{ ruleLabel(one.rule) }}</td>
                  <td>{{ one.piece ?? "—" }}</td>
                  <td>{{ one.reason }}</td>
                </tr>
              </tbody>
            </table>
          </div>
        </div>
      </div>
    </div>
  </section>
</template>
