<script setup lang="ts">
import { computed } from "vue"
import type { BacklogPiece } from "../types"

const props = defineProps<{ sequence: BacklogPiece[] }>()

/** The Piece under the pointer, here or in the sequence list. */
const hovered = defineModel<string | null>("hovered", { default: null })

type Lane = {
  demand: string
  label: string
  client: string
  dueOn: string
  waiting: number
  slots: (BacklogPiece | null)[]
}

/** One lane per Demand, in the order of its first Piece in the sequence. */
const lanes = computed(() => {
  const size = props.sequence.length
  const byDemand = new Map<string, Lane>()
  props.sequence.forEach((piece, index) => {
    let lane = byDemand.get(piece.demand)
    if (!lane) {
      lane = {
        demand: piece.demand,
        label: piece.demandLabel,
        client: piece.client,
        dueOn: piece.dueOn,
        waiting: 0,
        slots: Array.from({ length: size }, () => null),
      }
      byDemand.set(piece.demand, lane)
    }
    lane.slots[index] = piece
    lane.waiting += 1
  })
  return [...byDemand.values()]
})

const columns = computed(() => ({
  gridTemplateColumns: `var(--lane-head) repeat(${props.sequence.length}, minmax(0.75rem, 1fr))`,
}))

/** A mark on the first position and every fifth, so a position is easy to find. */
const marked = (index: number) => index === 0 || (index + 1) % 5 === 0

function dueLabel(day: string) {
  return new Date(`${day}T12:00:00`).toLocaleDateString(undefined, {
    day: "numeric",
    month: "short",
  })
}

function slotClass(piece: BacklogPiece | null, index: number) {
  if (!piece) return "bg-base-200"
  const ring =
    hovered.value === piece.id ? "ring-2 ring-base-content ring-offset-1 ring-offset-base-100" : ""
  if (index === 0) return `bg-primary ${ring}`
  if (piece.urgent) return `bg-warning ${ring}`
  return `bg-base-content/75 ${ring}`
}
</script>

<template>
  <figure class="heijunka-box overflow-x-auto pb-1">
    <div class="grid min-w-fit gap-y-1.5">
      <div class="grid items-end gap-x-0.5" :style="columns" aria-hidden="true">
        <span class="sticky left-0 z-10 bg-base-100 pr-3 text-xs opacity-70">Position</span>
        <span
          v-for="(_, index) in sequence"
          :key="index"
          class="text-center text-[0.6875rem] leading-none tabular-nums opacity-70"
          :class="index === 0 ? 'font-semibold' : ''"
        >
          {{ marked(index) ? index + 1 : "" }}
        </span>
      </div>

      <div
        v-for="lane in lanes"
        :key="lane.demand"
        class="grid items-center gap-x-0.5"
        :style="columns"
      >
        <p class="sticky left-0 z-10 min-w-0 bg-base-100 pr-3">
          <span class="block truncate text-sm font-semibold">{{ lane.label }}</span>
          <span class="block truncate text-xs opacity-70">
            {{ lane.waiting }} waiting · {{ lane.client }} · due {{ dueLabel(lane.dueOn) }}
          </span>
        </p>
        <span
          v-for="(piece, index) in lane.slots"
          :key="index"
          class="h-7 rounded-sm transition-[box-shadow,background-color] duration-150 motion-reduce:transition-none"
          :class="slotClass(piece, index)"
          :title="piece ? `${index + 1}. ${piece.reference} · ${piece.demandLabel}` : undefined"
          aria-hidden="true"
          @mouseenter="hovered = piece?.id ?? null"
          @mouseleave="hovered = null"
        />
      </div>
    </div>

    <figcaption class="mt-3 flex flex-wrap items-center gap-x-5 gap-y-2 text-xs opacity-80">
      <span>Read left to right: position 1 leaves on the next Kanban.</span>
      <span class="flex items-center gap-1.5">
        <span class="size-3 rounded-sm bg-primary" aria-hidden="true" />
        Next out
      </span>
      <span class="flex items-center gap-1.5">
        <span class="size-3 rounded-sm bg-base-content/75" aria-hidden="true" />
        Waiting
      </span>
      <span v-if="sequence.some((piece) => piece.urgent)" class="flex items-center gap-1.5">
        <span class="size-3 rounded-sm bg-warning" aria-hidden="true" />
        Urgent
      </span>
    </figcaption>
  </figure>
</template>

<style scoped>
.heijunka-box {
  --lane-head: clamp(8.5rem, 22vw, 16rem);
}
</style>
