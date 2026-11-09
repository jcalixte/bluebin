<script setup lang="ts">
import { computed, onBeforeUnmount, onMounted, ref } from "vue"
import type { LineChange, TimeView, WeekMeasures } from "../types"

const props = defineProps<{
  weeks: WeekMeasures[]
  view: TimeView
  changes: LineChange[]
  /** The Line change the periods are picked around; null with custom dates. */
  chosenAt: string | null
}>()

/** The chart draws at its real pixel width, so text and strokes keep their size. */
const frame = ref<HTMLElement | null>(null)
const width = ref(720)
const height = 260
/** Below this width, the limit labels get short to leave room for the weeks. */
const compactBelow = 480
const compact = computed(() => width.value < compactBelow)
const margin = computed(() => ({ top: 24, right: compact.value ? 52 : 84, bottom: 28, left: 52 }))
const plotWidth = computed(() => width.value - margin.value.left - margin.value.right)
const plotHeight = computed(() => height - margin.value.top - margin.value.bottom)
/** Space for one week label on the x axis. */
const labelSpace = 64
/** Least space between two limit labels, so they do not overlap. */
const labelGap = 14
/** Below this, the natural limits are noise themselves. */
const minimumWeeks = 5
const dayMs = 86_400_000

let observer: ResizeObserver | null = null
onMounted(() => {
  observer = new ResizeObserver(([entry]) => {
    if (entry) width.value = Math.max(240, Math.round(entry.contentRect.width))
  })
  if (frame.value) observer.observe(frame.value)
})
onBeforeUnmount(() => observer?.disconnect())

const today = new Date().toISOString().slice(0, 10)
const changeDay = computed(() => props.chosenAt?.slice(0, 10) ?? null)

function hours(value: number) {
  const minutes = Math.round(value * 60)
  return Math.abs(minutes) < 60 ? `${minutes} min` : `${value.toFixed(1)} h`
}

function tickLabel(tick: number) {
  if (tick === 0) return "0"
  return tick < 1 ? `${Math.round(tick * 60)} min` : `${tick} h`
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

/** The full weeks the limits come from: before the chosen change, or all with custom dates. */
const baseline = computed(() =>
  points.value.filter(
    (one) =>
      !one.partial &&
      one.value !== null &&
      (changeDay.value === null || one.week.to < changeDay.value),
  ),
)

/**
 * XmR natural process limits (Wheeler): average ± 2.66 × the average moving range, from
 * the baseline weeks.
 */
const limits = computed(() => {
  const values = baseline.value.map((one) => one.value!)
  if (values.length < minimumWeeks) return null
  const average = values.reduce((total, value) => total + value, 0) / values.length
  const ranges = values.slice(1).map((value, index) => Math.abs(value - values[index]!))
  const range = ranges.reduce((total, value) => total + value, 0) / ranges.length
  return {
    weeks: values.length,
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

const hasPartial = computed(() => points.value.some((one) => one.partial && one.value !== null))

const step = computed(() => plotWidth.value / Math.max(1, points.value.length))
const x = (index: number) => margin.value.left + (index + 0.5) * step.value

const scale = computed(() => {
  const values = points.value.map((one) => one.value).filter((value) => value !== null)
  const top = Math.max(...values, limits.value?.upper ?? 0, 0.1) * 1.1
  const magnitude = 10 ** Math.floor(Math.log10(top / 4))
  const tick = [1, 2, 5, 10].map((one) => one * magnitude).find((one) => top / one <= 5)!
  const max = Math.ceil(top / tick) * tick
  const ticks = Array.from({ length: Math.round(max / tick) + 1 }, (_, index) => index * tick)
  return { max, ticks }
})
const y = (value: number) =>
  margin.value.top + plotHeight.value - (value / scale.value.max) * plotHeight.value

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

/** The baseline weeks behind a light band, only when they are the weeks before a change. */
const baselineBand = computed(() => {
  if (!limits.value || changeDay.value === null) return null
  const first = baseline.value[0]
  const last = baseline.value.at(-1)
  if (!first || !last) return null
  const from = x(first.index) - step.value / 2
  return { x: from, width: x(last.index) + step.value / 2 - from }
})

/**
 * The limit lines with their labels at the right. Limits are dashed, as thresholds; the
 * average is solid. Labels move apart when lines are too close to read them.
 */
const limitLines = computed(() => {
  const found = limits.value
  if (!found) return []
  const lines = [
    { key: "upper", value: found.upper, label: compact.value ? "Upper" : "Upper limit" },
    { key: "average", value: found.average, label: compact.value ? "Avg" : "Average" },
    { key: "lower", value: found.lower, label: compact.value ? "Lower" : "Lower limit" },
  ].map((line) => ({ ...line, y: y(line.value), labelY: y(line.value) }))
  for (let index = 1; index < lines.length; index++) {
    lines[index]!.labelY = Math.max(lines[index]!.labelY, lines[index - 1]!.labelY + labelGap)
  }
  const bottom = margin.value.top + plotHeight.value
  for (let index = lines.length - 1; index >= 0; index--) {
    const below = index === lines.length - 1 ? bottom + labelGap : lines[index + 1]!.labelY
    lines[index]!.labelY = Math.min(lines[index]!.labelY, below - labelGap)
  }
  return lines
})

const markers = computed(() => {
  const first = points.value[0]?.week.from
  if (!first) return []
  const start = Date.parse(`${first}T00:00:00Z`)
  const left = margin.value.left
  const right = left + plotWidth.value
  return props.changes
    .map((change) => {
      const days = (Date.parse(`${change.at.slice(0, 10)}T00:00:00Z`) - start) / dayMs
      const at = left + (days / 7) * step.value
      return {
        at: change.at,
        x: at,
        chosen: change.at === props.chosenAt,
        label: `Change · ${dayLabel(change.at.slice(0, 10))}`,
        /** Near the right end, the label goes to the left of its line so it stays in view. */
        flip: at > left + plotWidth.value * 0.6,
      }
    })
    .filter((one) => one.x >= left && one.x <= right)
})

const labelEvery = computed(() =>
  Math.ceil(points.value.length / Math.max(1, Math.floor(plotWidth.value / labelSpace))),
)

const hovered = ref<number | null>(null)
const hoveredPoint = computed(() =>
  hovered.value === null ? null : (points.value[hovered.value] ?? null),
)

function pointAt(event: PointerEvent) {
  const box = (event.currentTarget as SVGElement).getBoundingClientRect()
  const svgX = ((event.clientX - box.left) / box.width) * width.value
  const index = Math.floor((svgX - margin.value.left) / step.value)
  hovered.value = Math.min(points.value.length - 1, Math.max(0, index))
}

function move(by: number) {
  const last = points.value.length - 1
  hovered.value = Math.min(last, Math.max(0, (hovered.value ?? last) + by))
}
</script>

<template>
  <div>
    <div ref="frame" class="relative">
      <svg
        :viewBox="`0 0 ${width} ${height}`"
        :width="width"
        :height="height"
        class="block max-w-full touch-none rounded-box outline-none select-none focus-visible:ring-2 focus-visible:ring-primary"
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
        <rect
          v-if="baselineBand"
          :x="baselineBand.x"
          :y="margin.top"
          :width="baselineBand.width"
          :height="plotHeight"
          class="fill-base-content opacity-[0.04]"
        />

        <g class="text-xs tabular-nums">
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
              class="fill-base-content opacity-70"
            >
              {{ tickLabel(tick) }}
            </text>
          </template>
          <template v-for="one in points" :key="one.week.from">
            <text
              v-if="one.index % labelEvery === (points.length - 1) % labelEvery"
              :x="x(one.index)"
              :y="height - 8"
              text-anchor="middle"
              class="fill-base-content opacity-70"
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
              :x="marker.flip ? marker.x - 4 : marker.x + 4"
              :y="margin.top - 8"
              :text-anchor="marker.flip ? 'end' : 'start'"
              class="fill-base-content font-medium"
            >
              {{ marker.label }}
            </text>
          </g>

          <g v-for="line in limitLines" :key="line.key">
            <line
              :x1="margin.left"
              :x2="margin.left + plotWidth"
              :y1="line.y"
              :y2="line.y"
              class="stroke-base-content"
              :class="line.key === 'average' ? 'opacity-40' : 'opacity-60'"
              :stroke-dasharray="line.key === 'average' ? undefined : '4 3'"
              stroke-width="1"
            />
            <text
              :x="margin.left + plotWidth + 6"
              :y="line.labelY"
              dominant-baseline="middle"
              class="fill-base-content opacity-70"
            >
              {{ line.label }}
            </text>
          </g>
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
        :style="{ left: `${x(hoveredPoint.index)}px` }"
        aria-live="polite"
      >
        <p class="text-base font-semibold">
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
      </template>
      <span v-if="limits" class="opacity-70">
        Limits from {{ limits.weeks }} full weeks{{
          changeDay ? " before the change, shaded" : ""
        }}: {{ hours(limits.lower) }} to {{ hours(limits.upper) }}, average
        {{ hours(limits.average) }}.
        {{ rule }}
      </span>
      <span v-if="hasPartial" class="opacity-70"> Hollow dot: this week so far.</span>
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
