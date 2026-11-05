<script setup lang="ts">
import { computed } from "vue"
import type { Demand } from "../types"

const props = defineProps<{ demand: Demand }>()

/** Past this count, one tick per Piece is too dense to read. */
const maxTicks = 60

const round = (value: number) => Math.round(value * 10) / 10

const status = computed(() => {
  if (props.demand.andon) return "andon"
  return props.demand.taktGap < 0 ? "behind" : "ok"
})

const gapLabel = computed(() => {
  const gap = props.demand.taktGap
  if (gap > 0) return `+${gap}`
  return gap < 0 ? `−${Math.abs(gap)}` : "0"
})

/** Same share as takt_gap in backend/src/bluebin/demand.gleam. */
const timeShare = computed(() => {
  const { workingDaysElapsed, workingDaysTotal } = props.demand
  return workingDaysTotal === 0 ? 0 : Math.min(1, workingDaysElapsed / workingDaysTotal)
})

const expected = computed(() => round(timeShare.value * props.demand.piecesAsked))

const percentOf = (pieces: number) =>
  props.demand.piecesAsked === 0 ? 0 : Math.min(100, (pieces / props.demand.piecesAsked) * 100)

const producedPercent = computed(() => percentOf(props.demand.piecesProduced))
const taktPercent = computed(() => timeShare.value * 100)

/** The Pieces the Takt Time asked for by now and that are not in production. */
const owedPercent = computed(() => Math.max(0, taktPercent.value - producedPercent.value))

const ticks = computed(() => {
  const asked = props.demand.piecesAsked
  return asked > 1 && asked <= maxTicks ? asked : 0
})

const taktLabel = computed(() => {
  const hours = props.demand.taktTimeHours
  return hours >= 7 ? `${round(hours / 7)} working days` : `${round(hours)} h`
})

const dueLabel = computed(() =>
  new Date(props.demand.dueOn).toLocaleDateString(undefined, {
    day: "numeric",
    month: "short",
    year: "numeric",
  }),
)

const barLabel = computed(
  () =>
    `${props.demand.piecesProduced} of ${props.demand.piecesAsked} Pieces in production. ` +
    `The Takt Time asks for ${expected.value} by now.`,
)
</script>

<template>
  <article
    class="card overflow-hidden border bg-base-100 shadow-sm"
    :class="status === 'andon' ? 'border-2 border-error' : 'border-base-300'"
  >
    <div
      class="card-body grid gap-x-8 gap-y-4 p-4 sm:p-5 lg:grid-cols-[minmax(12rem,18rem)_1fr_9rem] lg:items-center"
    >
      <header class="min-w-0">
        <h3 class="text-base font-semibold leading-tight">{{ demand.label }}</h3>
        <p class="mt-1 text-sm opacity-70">
          {{ demand.client }} · due <time :datetime="demand.dueOn">{{ dueLabel }}</time>
        </p>
        <p class="mt-1 text-xs opacity-70">
          Takt Time <span class="font-medium tabular-nums">{{ taktLabel }}</span> per Piece
        </p>
      </header>

      <div class="min-w-0">
        <div class="relative pt-2">
          <div
            role="img"
            :aria-label="barLabel"
            class="relative h-7 overflow-hidden rounded-field border border-base-content/30 bg-base-200"
          >
            <div
              class="absolute inset-y-0 left-0 bg-primary"
              :style="{ width: `${producedPercent}%` }"
            />
            <div
              v-if="owedPercent > 0"
              class="owed absolute inset-y-0"
              :class="status === 'andon' ? 'text-error' : 'text-warning-ink'"
              :style="{ left: `${producedPercent}%`, width: `${owedPercent}%` }"
            />
            <div
              v-if="ticks > 0"
              class="ticks absolute inset-0"
              :style="{ '--ticks': ticks }"
              aria-hidden="true"
            />
          </div>
          <!-- The Takt line stands out of the track so it stays visible over any fill. -->
          <div
            class="absolute top-0 bottom-[-0.25rem] w-0.5 -translate-x-1/2 rounded-full bg-base-content ring-2 ring-base-100"
            :style="{ left: `${taktPercent}%` }"
            aria-hidden="true"
          />
        </div>
        <p
          class="mt-2.5 flex flex-wrap items-center gap-x-4 gap-y-1 text-xs tabular-nums"
          aria-hidden="true"
        >
          <span class="flex items-center gap-1.5">
            <span class="size-2.5 rounded-xs bg-primary" />
            <span>
              <strong class="font-semibold">{{ demand.piecesProduced }}</strong>
              <span class="opacity-70">/{{ demand.piecesAsked }} in production</span>
            </span>
          </span>
          <span class="flex items-center gap-1.5">
            <span class="h-3 w-0.5 rounded-full bg-base-content" />
            <span>
              <strong class="font-semibold">{{ expected }}</strong>
              <span class="opacity-70"> asked by now</span>
            </span>
          </span>
          <span class="opacity-70 sm:ml-auto">
            working day {{ demand.workingDaysElapsed }} of {{ demand.workingDaysTotal }}
          </span>
        </p>
      </div>

      <div
        class="flex items-center justify-between gap-3 border-t border-base-300 pt-3 lg:flex-col lg:items-end lg:justify-center lg:gap-1 lg:border-t-0 lg:pt-0"
      >
        <p class="flex items-baseline gap-1.5 lg:flex-col lg:items-end lg:gap-0">
          <span
            class="text-3xl font-semibold leading-none tabular-nums"
            :class="{
              'text-error': status === 'andon',
              'text-warning-ink': status === 'behind',
            }"
          >
            {{ gapLabel }}
          </span>
          <span class="text-xs opacity-70">Takt Gap, in Pieces</span>
        </p>
        <span
          v-if="status === 'andon'"
          class="badge badge-error gap-1.5 font-semibold"
          title="A Takt Gap of −1 Piece or less raises an Andon"
        >
          <span class="size-2 rounded-full bg-current" aria-hidden="true" />
          Andon
        </span>
        <span v-else-if="status === 'behind'" class="badge badge-warning font-medium">
          Less than 1 Piece behind
        </span>
        <span v-else class="badge badge-success font-medium">On Takt</span>
      </div>
    </div>
  </article>
</template>

<style scoped>
.owed {
  background-image: repeating-linear-gradient(
    -45deg,
    currentColor 0 0.25rem,
    transparent 0.25rem 0.5rem
  );
}

/* One gap per Piece boundary: Pieces flow one at a time, so the bar counts them. */
.ticks {
  background: linear-gradient(to right, transparent calc(100% - 2px), var(--color-base-100) 0) 0 0 /
    calc(100% / var(--ticks)) 100% repeat-x;
}
</style>
