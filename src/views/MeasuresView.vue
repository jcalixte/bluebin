<script setup lang="ts">
import { computed, ref } from "vue"
import CompareCell, { type Verdict } from "../components/CompareCell.vue"
import VerdictPill from "../components/VerdictPill.vue"
import WorkingCalendarCard from "../components/WorkingCalendarCard.vue"
import { useLabels } from "../composables/useLabels"
import { isValidPeriod, periodDays, useMeasures, type Period } from "../composables/useMeasures"
import type { DemandMeasures, Duration, StationMeasures, TimeView } from "../types"

const {
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
} = useMeasures()

const { labels } = useLabels()

const view = ref<TimeView>("working")
const timeViews = [
  { id: "working", label: "Working Time" },
  { id: "calendar", label: "Calendar Time" },
] as const

const periods = [
  { name: "Before", period: before },
  { name: "After", period: after },
] as const

const compareModes = [
  { id: "change", label: "Around a Line change" },
  { id: "custom", label: "Custom dates" },
] as const

const dayOptions = [7, 14, 28]

const chosenChange = computed(() => changes.value.find((one) => one.at === changeAt.value))

/** Other Line changes inside the two periods: their effect mixes in. */
const otherChanges = computed(() =>
  changes.value.filter((one) => {
    const day = one.at.slice(0, 10)
    return one.at !== changeAt.value && day >= before.from && day <= after.to
  }),
)

const lengths = computed(() => [periodDays(before), periodDays(after)])

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

function percent(share: number | null | undefined) {
  return share === null || share === undefined ? "—" : `${Math.round(share * 100)} %`
}

type Kind = "hours" | "count" | "share"
/** Which way is an improvement; null when neither way is better (Touch Time is work content). */
type Better = "lower" | "higher" | null
type Comparison = { before: string; after: string; change: string; verdict: Verdict }

function format(value: number | null, kind: Kind) {
  if (value === null) return "—"
  if (kind === "hours") return hours(value)
  if (kind === "share") return percent(value)
  return String(value)
}

/** The change, rounded as it shows: a change under one displayed unit is no change. */
function rounded(difference: number, kind: Kind) {
  if (kind === "hours") return Math.round(difference * 60)
  if (kind === "share") return Math.round(difference * 100)
  return difference
}

function compare(a: number | null, b: number | null, kind: Kind, better: Better): Comparison {
  const shown = { before: format(a, kind), after: format(b, kind) }
  if (a === null || b === null) return { ...shown, change: "—", verdict: null }
  const difference = b - a
  const step = rounded(difference, kind)
  if (step === 0) {
    const zero = { hours: "0 min", share: "0 pt", count: "0" }[kind]
    return { ...shown, change: zero, verdict: null }
  }
  const magnitude = kind === "share" ? `${Math.abs(step)} pt` : format(Math.abs(difference), kind)
  const verdict =
    better === null ? null : difference < 0 === (better === "lower") ? "better" : "worse"
  return { ...shown, change: `${difference > 0 ? "+" : "−"}${magnitude}`, verdict }
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

const andons = (list: StationMeasures[]) => list.reduce((total, one) => total + one.andons, 0)

const headline = computed(() => {
  if (!measures.value) return null
  const { before, after } = measures.value
  return {
    leadTime: compare(pick(before.pieces.leadTime), pick(after.pieces.leadTime), "hours", "lower"),
    others: [
      {
        label: "Pieces released",
        hint: "",
        ...compare(before.pieces.count, after.pieces.count, "count", "higher"),
      },
      {
        label: "Andon Time",
        hint: "any Work Station stopped",
        ...compare(pick(before.andonTime), pick(after.andonTime), "hours", "lower"),
      },
    ],
  }
})

const summary = computed(() => {
  if (!measures.value) return []
  const a = measures.value.before
  const b = measures.value.after
  const durations = [
    { label: "Lead Time", a: a.pieces.leadTime, b: b.pieces.leadTime, better: "lower" },
    { label: "Touch Time", a: a.pieces.touchTime, b: b.pieces.touchTime, better: null },
    {
      label: "Stagnation Time",
      a: a.pieces.stagnationTime,
      b: b.pieces.stagnationTime,
      better: "lower",
    },
    { label: "Backlog time", a: a.pieces.backlogTime, b: b.pieces.backlogTime, better: "lower" },
  ] as const
  return [
    {
      label: "Pieces released",
      ...compare(a.pieces.count, b.pieces.count, "count", "higher"),
    },
    ...durations.map((row) => ({
      label: `${row.label} (average per Piece)`,
      ...compare(pick(row.a), pick(row.b), "hours", row.better),
    })),
    {
      label: "Andons raised",
      ...compare(andons(a.stations), andons(b.stations), "count", "lower"),
    },
    {
      label: "Andon Time (any Work Station stopped)",
      ...compare(pick(a.andonTime), pick(b.andonTime), "hours", "lower"),
    },
  ]
})

/** The share of Demands to deliver by their due date. */
const onTimeTarget = 0.9

const onTime = computed(() => {
  if (!measures.value) return null
  const [a, b] = [measures.value.before, measures.value.after].map(({ onTime }) => {
    const share = onTime.delivered === 0 ? null : onTime.onTime / onTime.delivered
    return {
      ...onTime,
      // Floor, so a share under the target never reads as the target.
      percent: share === null ? null : Math.floor(share * 100),
      met: share !== null && share >= onTimeTarget,
    }
  })
  const shown = (one: typeof a) => (one.percent === null ? "—" : `${one.percent} %`)
  const step = a.percent === null || b.percent === null ? null : b.percent - a.percent
  return {
    after: b,
    before: shown(a),
    change:
      step === null ? "—" : step === 0 ? "0 pt" : `${step > 0 ? "+" : "−"}${Math.abs(step)} pt`,
    verdict: (step === null || step === 0 ? null : step > 0 ? "better" : "worse") as Verdict,
  }
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

type Column<T> = { label: string; cell: (before?: T, after?: T) => Comparison }

function duration<T>(label: string, of: (one: T) => Duration | null, better: Better): Column<T> {
  return {
    label,
    cell: (x, y) => compare(x ? pick(of(x)) : null, y ? pick(of(y)) : null, "hours", better),
  }
}

const demands = computed<Paired<DemandMeasures>[]>(() =>
  measures.value ? pair(measures.value.before.demands, measures.value.after.demands) : [],
)

const showDemandLeadTime = computed(() =>
  demands.value.some(
    (row) => pick(row.before?.demandLeadTime) !== null || pick(row.after?.demandLeadTime) !== null,
  ),
)

const demandColumns = computed<Column<DemandMeasures>[]>(() => [
  {
    label: "Pieces",
    cell: (x, y) => compare(x?.pieces ?? 0, y?.pieces ?? 0, "count", null),
  },
  duration("Lead Time", (one) => one.leadTime, "lower"),
  duration("Touch Time", (one) => one.touchTime, null),
  duration("Stagnation Time", (one) => one.stagnationTime, "lower"),
  ...(showDemandLeadTime.value
    ? [duration<DemandMeasures>("Demand Lead Time", (one) => one.demandLeadTime, "lower")]
    : []),
])

const stations = computed<Paired<StationMeasures>[]>(() =>
  measures.value
    ? pair(measures.value.before.stations, measures.value.after.stations).sort(
        (x, y) =>
          x.first.position - y.first.position ||
          (x.first.branch ?? "").localeCompare(y.first.branch ?? ""),
      )
    : [],
)

const stationColumns: Column<StationMeasures>[] = [
  duration("Station Lead Time", (one) => one.stationLeadTime, "lower"),
  duration("Replenishment Time", (one) => one.replenishmentTime, "lower"),
  duration("Touch Time", (one) => one.touchTime, null),
  {
    label: "Touch share",
    cell: (x, y) => compare(x?.touchShare ?? null, y?.touchShare ?? null, "share", "higher"),
  },
  duration("Starvation Time", (one) => one.starvationTime, "lower"),
  duration("Andon Time", (one) => one.andonTime, "lower"),
  {
    label: "Andons raised",
    cell: (x, y) => compare(x?.andons ?? null, y?.andons ?? null, "count", "lower"),
  },
  {
    label: "Deviations / pulls",
    cell: (x, y) => ({
      before: x ? `${x.deviations} / ${x.pulls}` : "—",
      after: y ? `${y.deviations} / ${y.pulls}` : "—",
      change: "—",
      verdict: null,
    }),
  },
]

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
    ...compare(count(a, rule), count(b, rule), "count", "lower"),
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
          Lead Time, Touch Time and Stagnation Time of the Pieces released, before and after a
          change
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

    <div class="card mb-6 border border-base-300 bg-base-100 shadow-sm">
      <div class="card-body gap-4 p-5">
        <div class="flex flex-wrap items-center justify-between gap-3">
          <h3 class="text-sm font-semibold">Compare two periods</h3>
          <div
            v-if="changes.length > 0"
            class="tabs tabs-box tabs-sm"
            role="group"
            aria-label="How to pick the periods"
          >
            <button
              v-for="option in compareModes"
              :key="option.id"
              type="button"
              class="tab"
              :class="mode === option.id ? 'tab-active font-medium' : 'opacity-70'"
              :aria-pressed="mode === option.id"
              @click="mode = option.id"
            >
              {{ option.label }}
            </button>
          </div>
          <p v-else class="text-sm opacity-70">
            No Line change saved yet: pick the two periods by hand.
          </p>
        </div>

        <template v-if="mode === 'change' && chosenChange">
          <div class="flex flex-wrap items-end gap-3">
            <label class="flex min-w-0 flex-col gap-1 text-sm">
              <span class="opacity-70">Line change</span>
              <select v-model="changeAt" class="select w-auto max-w-full">
                <option v-for="one in changes" :key="one.at" :value="one.at">
                  {{ atLabel(one.at) }} · {{ one.items[0]
                  }}{{ one.items.length > 1 ? ` (+${one.items.length - 1})` : "" }}
                </option>
              </select>
            </label>
            <label class="flex flex-col gap-1 text-sm">
              <span class="opacity-70">Days on each side</span>
              <select v-model="days" class="select w-auto">
                <option v-for="count in dayOptions" :key="count" :value="count">
                  {{ count }} days
                </option>
              </select>
            </label>
          </div>
          <ul class="list-inside list-disc text-sm">
            <li v-for="item in chosenChange.items" :key="item">{{ item }}</li>
          </ul>
          <p class="text-sm tabular-nums">
            <span class="font-medium">Before</span> {{ periodLabel(before) }}
            <span class="opacity-60">compared with</span>
            <span class="font-medium">After</span> {{ periodLabel(after) }}
            <span class="opacity-70"
              >· {{ lengths[1] }} {{ lengths[1] === 1 ? "day" : "days" }} each</span
            >
          </p>
          <p aria-live="polite" class="text-sm text-warning-ink empty:hidden">
            <template v-if="lengths[1] < days">
              The change is {{ lengths[1] }} {{ lengths[1] === 1 ? "day" : "days" }} old: each
              period has {{ lengths[1] }} {{ lengths[1] === 1 ? "day" : "days" }} so far.
            </template>
            <template v-if="otherChanges.length > 0">
              Another Line change falls in these periods ({{
                otherChanges.map((one) => atLabel(one.at)).join(", ")
              }}): its effect mixes in.
            </template>
          </p>
        </template>

        <template v-else>
          <div class="flex flex-row flex-wrap items-start gap-x-8 gap-y-4">
            <template v-for="(one, index) in periods" :key="one.name">
              <span
                v-if="index > 0"
                class="hidden self-center pt-6 text-sm font-medium opacity-60 md:block"
                aria-hidden="true"
              >
                compared with
              </span>
              <fieldset class="min-w-0">
                <legend class="mb-2 text-sm font-semibold">{{ one.name }}</legend>
                <div class="flex flex-wrap gap-3">
                  <label class="flex flex-col gap-1 text-sm">
                    <span class="opacity-70">From</span>
                    <input v-model="one.period.from" type="date" class="input w-auto" />
                  </label>
                  <label class="flex flex-col gap-1 text-sm">
                    <span class="opacity-70">To (included)</span>
                    <input v-model="one.period.to" type="date" class="input w-auto" />
                  </label>
                </div>
                <p aria-live="polite" class="mt-2 text-sm text-warning-ink empty:hidden">
                  <template v-if="!isValidPeriod(one.period)">
                    Pick a start date on or before the end date.
                  </template>
                </p>
              </fieldset>
            </template>
          </div>
          <p
            v-if="isValidPeriod(before) && isValidPeriod(after) && lengths[0] !== lengths[1]"
            class="text-sm text-warning-ink"
          >
            The periods have different lengths ({{ lengths[0] }} and {{ lengths[1] }} days): the
            counts and totals do not compare, the averages do.
          </p>
        </template>
      </div>
    </div>

    <p v-if="loading && !measures" class="flex items-center gap-3 opacity-70">
      <span class="loading loading-spinner loading-sm" />
      Loading the measures…
    </p>

    <div v-else-if="error" class="alert alert-error">
      <span>The API did not answer: {{ error }}</span>
    </div>

    <div v-else-if="measures && headline && onTime" class="flex flex-col gap-6">
      <section aria-label="Key measures" class="grid gap-4 sm:grid-cols-2 xl:grid-cols-4">
        <article class="rounded-box bg-primary p-5 text-primary-content shadow-sm">
          <h3 class="text-sm font-semibold">
            Lead Time <span class="font-normal opacity-80">· average per Piece</span>
          </h3>
          <p class="mt-2 text-4xl font-semibold tabular-nums">{{ headline.leadTime.after }}</p>
          <p class="mt-2 flex flex-wrap items-center gap-x-2 gap-y-1 text-sm tabular-nums">
            <span class="opacity-80">Before {{ headline.leadTime.before }}</span>
            <span aria-hidden="true" class="opacity-50">·</span>
            <span class="font-medium">{{ headline.leadTime.change }}</span>
            <VerdictPill :verdict="headline.leadTime.verdict" plain />
          </p>
        </article>

        <article class="rounded-box border border-base-300 bg-base-100 p-5 shadow-sm">
          <h3 class="text-sm font-semibold">
            On-time delivery
            <span class="font-normal opacity-70">· target {{ onTimeTarget * 100 }} %</span>
          </h3>
          <p
            v-if="onTime.after.percent === null"
            class="mt-2 flex min-h-10 items-center opacity-70"
          >
            No {{ labels.demand }} delivered.
          </p>
          <p v-else class="mt-2 flex flex-wrap items-center gap-x-3 gap-y-1">
            <span class="text-4xl font-semibold tabular-nums">{{ onTime.after.percent }} %</span>
            <span
              class="badge font-medium whitespace-nowrap"
              :class="onTime.after.met ? 'badge-success' : 'badge-error'"
            >
              {{ onTime.after.met ? "On target" : "Below target" }}
            </span>
          </p>
          <p class="mt-2 flex flex-wrap items-center gap-x-2 gap-y-1 text-sm tabular-nums">
            <span v-if="onTime.after.delivered > 0">
              {{ onTime.after.onTime }} of {{ onTime.after.delivered }}
              <span class="opacity-70">{{ labels.demands }}</span>
            </span>
            <span v-if="onTime.after.delivered > 0" aria-hidden="true" class="opacity-40">·</span>
            <span class="opacity-70">Before {{ onTime.before }}</span>
            <template v-if="onTime.change !== '—'">
              <span aria-hidden="true" class="opacity-40">·</span>
              <span class="font-medium">{{ onTime.change }}</span>
            </template>
            <VerdictPill :verdict="onTime.verdict" />
          </p>
        </article>

        <article
          v-for="one in headline.others"
          :key="one.label"
          class="rounded-box border border-base-300 bg-base-100 p-5 shadow-sm"
        >
          <h3 class="text-sm font-semibold">
            {{ one.label }}
            <span v-if="one.hint" class="font-normal opacity-70">· {{ one.hint }}</span>
          </h3>
          <p class="mt-2 text-4xl font-semibold tabular-nums">{{ one.after }}</p>
          <p class="mt-2 flex flex-wrap items-center gap-x-2 gap-y-1 text-sm tabular-nums">
            <span class="opacity-70">Before {{ one.before }}</span>
            <span aria-hidden="true" class="opacity-40">·</span>
            <span class="font-medium">{{ one.change }}</span>
            <VerdictPill :verdict="one.verdict" />
          </p>
        </article>
      </section>
      <p class="-mt-3 text-xs opacity-60">
        After: {{ periodLabel(measures.after) }}, compared with Before:
        {{ periodLabel(measures.before) }}. On-time delivery counts the {{ labels.demands }}
        delivered in the period by their due date.
      </p>

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
                    <td class="text-right tabular-nums opacity-70">{{ row.before }}</td>
                    <td class="text-right font-medium tabular-nums">{{ row.after }}</td>
                    <td class="text-right whitespace-nowrap tabular-nums">
                      {{ row.change }}
                      <VerdictPill class="ml-1" :verdict="row.verdict" />
                    </td>
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
          <h3 class="card-title text-base">Per Demand</h3>
          <p class="text-sm opacity-70">Averages per Piece released.</p>
          <p class="text-xs opacity-60">
            Each cell: After ({{ periodLabel(measures.after) }}) on top, Before ({{
              periodLabel(measures.before)
            }}) below. Blue: better than before.
          </p>
          <p v-if="demands.length === 0" class="opacity-70">No Piece released.</p>
          <div v-else class="overflow-x-auto">
            <table class="table table-sm">
              <thead>
                <tr>
                  <th>Demand</th>
                  <th v-for="column in demandColumns" :key="column.label" class="text-right">
                    {{ column.label }}
                  </th>
                </tr>
              </thead>
              <tbody>
                <tr v-for="row in demands" :key="row.id">
                  <th class="font-medium">
                    {{ row.first.label }}
                    <span class="block text-xs font-normal opacity-60">{{ row.first.client }}</span>
                  </th>
                  <CompareCell
                    v-for="column in demandColumns"
                    :key="column.label"
                    v-bind="column.cell(row.before, row.after)"
                  />
                </tr>
              </tbody>
            </table>
          </div>
          <p v-if="showDemandLeadTime" class="text-xs opacity-60">
            Demand Lead Time is the Lead Time of the whole Demand, known once its last Piece is
            released.
          </p>
        </div>
      </div>

      <div class="card border border-base-300 bg-base-100 shadow-sm">
        <div class="card-body gap-3 p-5">
          <h3 class="card-title text-base">Per Work Station</h3>
          <p class="text-sm opacity-70">
            Station Lead Time and Touch Time are averages per pass. Replenishment Time is the 85th
            percentile of the passes, from the pull in to the Blue Bin, and shows from 5 passes.
            Starvation Time and Andon Time are totals of the period.
          </p>
          <p class="text-xs opacity-60">
            Each cell: After ({{ periodLabel(measures.after) }}) on top, Before ({{
              periodLabel(measures.before)
            }}) below. Blue: better than before.
          </p>
          <p v-if="stations.length === 0" class="opacity-70">No Work Station.</p>
          <div v-else class="overflow-x-auto">
            <table class="table table-sm">
              <thead>
                <tr>
                  <th>Work Station</th>
                  <th v-for="column in stationColumns" :key="column.label" class="text-right">
                    {{ column.label }}
                  </th>
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
                  <CompareCell
                    v-for="column in stationColumns"
                    :key="column.label"
                    v-bind="column.cell(row.before, row.after)"
                  />
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
                  <td class="text-right tabular-nums opacity-70">{{ row.before }}</td>
                  <td class="text-right font-medium tabular-nums">{{ row.after }}</td>
                  <td class="text-right whitespace-nowrap tabular-nums">
                    {{ row.change }}
                    <VerdictPill class="ml-1" :verdict="row.verdict" />
                  </td>
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
