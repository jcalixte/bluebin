<script setup lang="ts">
import { computed } from "vue"
import type { Demand } from "../types"

const props = defineProps<{ demand: Demand }>()

const gap = computed(() => props.demand.taktGap)

const gapLabel = computed(() => (gap.value > 0 ? `+${gap.value}` : String(gap.value)))

const gapTone = computed(() => {
  if (props.demand.andon) return "text-error"
  if (gap.value < 0) return "text-warning"
  return "text-success"
})

const taktLabel = computed(() => {
  const hours = props.demand.taktTimeHours
  return hours >= 7 ? `${round(hours / 7)} working days` : `${round(hours)} h`
})

const progress = computed(() =>
  props.demand.piecesAsked === 0
    ? 0
    : (props.demand.piecesProduced / props.demand.piecesAsked) * 100,
)

const dueLabel = computed(() =>
  new Date(props.demand.dueOn).toLocaleDateString(undefined, {
    day: "numeric",
    month: "short",
    year: "numeric",
  }),
)

function round(value: number) {
  return Math.round(value * 10) / 10
}
</script>

<template>
  <article
    class="card border border-base-300 bg-base-100 shadow-sm"
    :class="demand.andon ? 'border-error border-2' : ''"
  >
    <div class="card-body gap-4 p-5">
      <header class="flex flex-wrap items-start justify-between gap-3">
        <div>
          <h2 class="card-title text-lg">{{ demand.label }}</h2>
          <p class="text-sm opacity-70">{{ demand.client }} · due {{ dueLabel }}</p>
        </div>
        <span v-if="demand.andon" class="badge badge-error gap-2 font-semibold uppercase">
          <span class="inline-block size-2 rounded-full bg-current" />
          Andon
        </span>
      </header>

      <div class="grid grid-cols-2 gap-4 sm:grid-cols-4">
        <div>
          <p class="text-xs uppercase tracking-wide opacity-60">Takt Gap</p>
          <p class="text-2xl font-semibold tabular-nums" :class="gapTone">
            {{ gapLabel }}
          </p>
          <p class="text-xs opacity-60">Pieces</p>
        </div>
        <div>
          <p class="text-xs uppercase tracking-wide opacity-60">Takt Time</p>
          <p class="text-2xl font-semibold tabular-nums">{{ taktLabel }}</p>
          <p class="text-xs opacity-60">per Piece</p>
        </div>
        <div>
          <p class="text-xs uppercase tracking-wide opacity-60">Pieces</p>
          <p class="text-2xl font-semibold tabular-nums">
            {{ demand.piecesProduced }}/{{ demand.piecesAsked }}
          </p>
          <p class="text-xs opacity-60">in production</p>
        </div>
        <div>
          <p class="text-xs uppercase tracking-wide opacity-60">Working days</p>
          <p class="text-2xl font-semibold tabular-nums">
            {{ demand.workingDaysElapsed }}/{{ demand.workingDaysTotal }}
          </p>
          <p class="text-xs opacity-60">spent</p>
        </div>
      </div>

      <progress class="progress progress-primary w-full" :value="progress" max="100" />
    </div>
  </article>
</template>
