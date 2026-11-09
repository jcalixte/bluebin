<script setup lang="ts">
import { computed, ref } from "vue"
import type { LineChange, TimeView, WeekMeasures } from "../types"

const props = defineProps<{
  weeks: WeekMeasures[]
  view: TimeView
  changes: LineChange[]
  /** The Line change the periods are picked around; null with custom dates. */
  chosenAt: string | null
}>()

const width = 720
const height = 260
const margin = { top: 20, right: 92, bottom: 28, left: 56 }
const plotWidth = width - margin.left - margin.right
const plotHeight = height - margin.top - margin.bottom
/** Below this, the natural limits are noise themselves. */
const minimumWeeks = 5
const dayMs = 86_400_000

const today = new Date().toISOString().slice(0, 10)
const changeDay = computed(() => props.chosenAt?.slice(0, 10) ?? null)

function hours(value: number) {
  const minutes = Math.round(value * 60)
  return Math.abs(minutes) < 60 ? `${minutes} min` : `${value.toFixed(1)} h`
}

function dayLabel(day: string) {
  return new Date(`${day}T12:00:00Z`).toLocaleDateString(undefined, {
    day: "numeric",
    month: "short",
    timeZone: "UTC",
  })
}

const points = computed(() =>
  props.weeks.map((week, index) => ({
    index,
    week,
    value: week.leadTime?.[props.view] ?? null,
    partial: week.to >= today,
  })),
)

/**
 * XmR natural process limits (Wheeler): average ± 2.66 × the average moving range, from
 * the full weeks before the chosen Line change, or from all full weeks with custom dates.
 */
const limits = computed(() => {
  const baseline = points.value
    .filter((one) => !one.partial && (changeDay.value === null || one.week.to < changeDay.value))
    .map((one) => one.value)
    .filter((value): value is number => value !== null)
  if (baseline.length < minimumWeeks) return null
  const average = baseline.reduce((total, value) => total + value, 0) / baseline.length
  const ranges = baseline.slice(1).map((value, index) => Math.abs(value - baseline[index]!))
  const range = ranges.reduce((total, value) => total + value, 0) / ranges.length
  return {
    weeks: baseline.length,
    average,
    upper: average + 2.66 * range,
    lower: Math.max(0, average - 2.66 * range),
  }
})

type Side = "above" | "below"

/**
 * Wheeler's rules 1 and 3: a week outside the limits, or 3 of 4 weeks in a row past the
 * halfway line to the same limit. The second finds a moderate, lasting shift.
 */
const signals = computed(() => {
  const found = limits.value
  const marks = new Map<number, Side>()
  if (!found) return marks
  const valued = points.value.filter((one) => one.value !== null)
  for (const one of valued) {
    if (one.value! > found.upper) marks.set(one.index, "above")
    if (one.value! < found.lower) marks.set(one.index, "below")
  }
  const halfway = {
    above: (found.average + found.upper) / 2,
    below: (found.average + found.lower) / 2,
  }
  for (let start = 0; start + 4 <= valued.length; start++) {
    const window = valued.slice(start, start + 4)
    for (const side of ["above", "below"] as const) {
      const past = window.filter((one) =>
        side === "above" ? one.value! > halfway.above : one.value! < halfway.below,
      )
      if (past.length >= 3) for (const one of past) marks.set(one.index, side)
    }
  }
  return marks
})

const signal = (index: number) => signals.value.get(index) ?? null

const rule =
  "Circled: a signal, a week outside the limits or 3 of 4 weeks past halfway to one. Other weeks are noise."

/** Weeks since the chosen change, and those that signal against the weeks before it. */
const signalsAfter = computed(() => {
  if (!limits.value || changeDay.value === null) return null
  const after = points.value.filter(
    (one) => one.week.from >= changeDay.value! && one.value !== null,
  )
  return {
    weeks: after.length,
    below: after.filter((one) => signal(one.index) === "below").length,
    above: after.filter((one) => signal(one.index) === "above").length,
  }
})

const step = computed(() => plotWidth / Math.max(1, points.value.length))
const x = (index: number) => margin.left + (index + 0.5) * step.value

const scale = computed(() => {
  const values = points.value.map((one) => one.value).filter((value) => value !== null)
  const top = Math.max(...values, limits.value?.upper ?? 0, 0.1) * 1.1
  const magnitude = 10 ** Math.floor(Math.log10(top / 4))
  const tick = [1, 2, 5, 10].map((one) => one * magnitude).find((one) => top / one <= 5)!
  const max = Math.ceil(top / tick) * tick
  const ticks = Array.from({ length: Math.round(max / tick) + 1 }, (_, index) => index * tick)
  return { max, ticks }
})
const y = (value: number) => margin.top + plotHeight - (value / scale.value.max) * plotHeight

/** One path piece for each run of weeks with a value: a week with no Piece is a gap. */
const path = computed(() =>
  points.value
    .map((one, index) => {
      if (one.value === null) return ""
      const previous = points.value[index - 1]
      const move = index === 0 || previous?.value === null ? "M" : "L"
      return `${move}${x(index).toFixed(1)},${y(one.value).toFixed(1)}`
    })
    .join(" "),
)

const markers = computed(() => {
  const first = points.value[0]?.week.from
  if (!first) return []
  const start = Date.parse(`${first}T00:00:00Z`)
  return props.changes
    .map((change) => {
      const days = (Date.parse(`${change.at.slice(0, 10)}T00:00:00Z`) - start) / dayMs
      return {
        at: change.at,
        x: margin.left + (days / 7) * step.value,
        chosen: change.at === props.chosenAt,
        label: dayLabel(change.at.slice(0, 10)),
      }
    })
    .filter((one) => one.x >= margin.left && one.x <= margin.left + plotWidth)
})

const labelEvery = computed(() => Math.ceil(points.value.length / 8))

const hovered = ref<number | null>(null)
const hoveredPoint = computed(() =>
  hovered.value === null ? null : (points.value[hovered.value] ?? null),
)

function pointAt(event: PointerEvent) {
  const box = (event.currentTarget as SVGElement).getBoundingClientRect()
  const svgX = ((event.clientX - box.left) / box.width) * width
  const index = Math.floor((svgX - margin.left) / step.value)
  hovered.value = Math.min(points.value.length - 1, Math.max(0, index))
}

function move(by: number) {
  const last = points.value.length - 1
  hovered.value = Math.min(last, Math.max(0, (hovered.value ?? last) + by))
}
</script>

<template>
  <div>
    <div class="relative">
      <svg
        :viewBox="`0 0 ${width} ${height}`"
        class="h-auto w-full touch-none outline-none select-none focus-visible:ring-2 focus-visible:ring-primary"
        role="img"
        tabindex="0"
        aria-label="Lead Time, average per Piece, for each week. Arrow keys read each week."
        @pointermove="pointAt"
        @pointerleave="hovered = null"
        @focus="move(0)"
        @blur="hovered = null"
        @keydown.left.prevent="move(-1)"
        @keydown.right.prevent="move(1)"
      >
        <g class="text-[11px]">
          <template v-for="tick in scale.ticks" :key="tick">
            <line
              :x1="margin.left"
              :x2="margin.left + plotWidth"
              :y1="y(tick)"
              :y2="y(tick)"
              class="stroke-base-300"
              stroke-width="1"
            />
            <text
              :x="margin.left - 8"
              :y="y(tick)"
              text-anchor="end"
              dominant-baseline="middle"
              class="fill-base-content opacity-60"
            >
              {{ tick === 0 ? "0" : tick < 1 ? `${Math.round(tick * 60)} min` : `${tick} h` }}
            </text>
          </template>
          <template v-for="one in points" :key="one.week.from">
            <text
              v-if="one.index % labelEvery === (points.length - 1) % labelEvery"
              :x="x(one.index)"
              :y="height - 8"
              text-anchor="middle"
              class="fill-base-content opacity-60"
            >
              {{ dayLabel(one.week.from) }}
            </text>
          </template>

          <g v-for="marker in markers" :key="marker.at">
            <line
              :x1="marker.x"
              :x2="marker.x"
              :y1="margin.top"
              :y2="margin.top + plotHeight"
              class="stroke-base-content"
              :class="marker.chosen ? 'opacity-70' : 'opacity-25'"
              stroke-width="1"
            />
            <text
              v-if="marker.chosen"
              :x="marker.x + 4"
              :y="margin.top - 6"
              class="fill-base-content font-medium"
            >
              Change · {{ marker.label }}
            </text>
          </g>

          <template v-if="limits">
            <g
              v-for="line in [
                { key: 'upper', value: limits.upper, label: 'Upper limit' },
                { key: 'average', value: limits.average, label: 'Average' },
                { key: 'lower', value: limits.lower, label: 'Lower limit' },
              ]"
              :key="line.key"
            >
              <line
                :x1="margin.left"
                :x2="margin.left + plotWidth"
                :y1="y(line.value)"
                :y2="y(line.value)"
                class="stroke-base-content"
                :class="line.key === 'average' ? 'opacity-40' : 'opacity-60'"
                stroke-width="1"
              />
              <text
                :x="margin.left + plotWidth + 6"
                :y="y(line.value)"
                dominant-baseline="middle"
                class="fill-base-content opacity-70"
              >
                {{ line.label }}
              </text>
            </g>
          </template>
        </g>

        <line
          v-if="hoveredPoint"
          :x1="x(hoveredPoint.index)"
          :x2="x(hoveredPoint.index)"
          :y1="margin.top"
          :y2="margin.top + plotHeight"
          class="stroke-base-content opacity-30"
          stroke-width="1"
        />

        <path
          :d="path"
          fill="none"
          class="stroke-primary"
          stroke-width="2"
          stroke-linejoin="round"
          stroke-linecap="round"
        />
        <template v-for="one in points" :key="one.week.from">
          <g v-if="one.value !== null">
            <circle
              v-if="signal(one.index)"
              :cx="x(one.index)"
              :cy="y(one.value)"
              r="8"
              fill="none"
              class="stroke-primary"
              stroke-width="1.5"
            />
            <circle
              :cx="x(one.index)"
              :cy="y(one.value)"
              :r="hovered === one.index ? 5.5 : 4"
              :class="one.partial ? 'fill-base-100 stroke-primary' : 'fill-primary stroke-base-100'"
              stroke-width="2"
            />
          </g>
        </template>
      </svg>

      <div
        v-if="hoveredPoint"
        class="pointer-events-none absolute top-2 z-10 rounded-box border border-base-300 bg-base-100 px-3 py-2 text-sm shadow-md"
        :class="hoveredPoint.index > points.length / 2 ? '-translate-x-full' : ''"
        :style="{ left: `${(x(hoveredPoint.index) / width) * 100}%` }"
        aria-live="polite"
      >
        <p class="text-base font-semibold tabular-nums">
          {{ hoveredPoint.value === null ? "No Piece released" : hours(hoveredPoint.value) }}
        </p>
        <p class="opacity-70">
          Week of {{ dayLabel(hoveredPoint.week.from) }}
          <template v-if="hoveredPoint.partial"> · so far</template>
        </p>
        <p class="tabular-nums opacity-70">
          {{ hoveredPoint.week.pieces }}
          {{ hoveredPoint.week.pieces === 1 ? "Piece" : "Pieces" }} released
        </p>
        <p v-if="signal(hoveredPoint.index)" class="font-medium">
          Signal: {{ signal(hoveredPoint.index) === "above" ? "higher" : "lower" }} Lead Time
        </p>
      </div>
    </div>

    <p class="mt-2 text-sm" aria-live="polite">
      <template v-if="!limits">
        The natural limits need {{ minimumWeeks }} full weeks with a Piece released
        {{ changeDay ? "before the change" : "" }}.
      </template>
      <template v-else-if="signalsAfter && signalsAfter.weeks > 0">
        Since the change:
        <span class="font-medium">
          {{ signalsAfter.below }} of {{ signalsAfter.weeks }}
          {{ signalsAfter.weeks === 1 ? "week signals" : "weeks signal" }} a lower Lead Time,
          {{ signalsAfter.above }} a higher one.
        </span>
        <span class="opacity-70">{{ rule }}</span>
      </template>
      <template v-else>
        <span class="opacity-70">
          Limits from {{ limits.weeks }} full weeks{{ changeDay ? " before the change" : "" }}.
          {{ rule }}
        </span>
      </template>
    </p>

    <details class="mt-2 text-sm">
      <summary class="cursor-pointer opacity-70">Show as a table</summary>
      <div class="overflow-x-auto">
        <table class="table table-sm mt-2">
          <thead>
            <tr>
              <th>Week of</th>
              <th class="text-right">Pieces released</th>
              <th class="text-right">Lead Time</th>
              <th>Signal</th>
            </tr>
          </thead>
          <tbody>
            <tr v-for="one in points" :key="one.week.from">
              <th class="font-medium">
                {{ dayLabel(one.week.from) }}
                <span v-if="one.partial" class="font-normal opacity-60">· so far</span>
              </th>
              <td class="text-right tabular-nums">{{ one.week.pieces }}</td>
              <td class="text-right tabular-nums">
                {{ one.value === null ? "—" : hours(one.value) }}
              </td>
              <td>
                {{
                  signal(one.index) === "above"
                    ? "Higher"
                    : signal(one.index) === "below"
                      ? "Lower"
                      : ""
                }}
              </td>
            </tr>
          </tbody>
        </table>
      </div>
    </details>
  </div>
</template>
