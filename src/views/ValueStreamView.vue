<script setup lang="ts">
import { computed } from "vue"
import FlowArrow from "../components/FlowArrow.vue"
import WorkStationCard from "../components/WorkStationCard.vue"
import { useValueStream } from "../composables/useValueStream"
import type { WorkStation } from "../types"

const { valueStream, error, loading, load } = useValueStream()

/** One column per position in the chain; a Split shows as several Work
 *  Stations stacked in the same column, one per Branch. */
const columns = computed<{ position: number; stations: WorkStation[]; kanbans: number }[]>(() => {
  const byPosition = new Map<number, WorkStation[]>()
  for (const station of valueStream.value?.stations ?? []) {
    const column = byPosition.get(station.position) ?? []
    column.push(station)
    byPosition.set(station.position, column)
  }
  return [...byPosition.entries()]
    .sort(([a], [b]) => a - b)
    .map(([position, stations]) => ({
      position,
      stations,
      // The Kanbans this step holds are the signals it has already sent back
      // upstream, so they belong to the link coming into it.
      kanbans: stations.reduce((total, station) => total + station.kanbans, 0),
    }))
})

const taktLabel = computed(() => {
  const hours = valueStream.value?.taktTimeHours ?? 0
  return hours >= 7 ? `${Math.round((hours / 7) * 10) / 10} working days` : `${hours} h`
})
</script>

<template>
  <section>
    <header class="mb-6 flex flex-wrap items-end justify-between gap-4">
      <div>
        <h2 class="text-xl font-semibold">Value Stream</h2>
        <p class="text-sm opacity-70">
          Takt Time {{ taktLabel }} per Piece, across every active Demand
        </p>
      </div>
      <button class="btn btn-sm" :disabled="loading" @click="load">Refresh</button>
    </header>

    <p v-if="loading" class="flex items-center gap-3 opacity-70">
      <span class="loading loading-spinner loading-sm" />
      Loading the Value Stream…
    </p>

    <div v-else-if="error" class="alert alert-error">
      <span>The API did not answer: {{ error }}</span>
    </div>

    <p v-else-if="columns.length === 0" class="opacity-70">No Work Station yet.</p>

    <div v-else class="flex gap-4 overflow-x-auto pb-4">
      <template v-for="(column, index) in columns" :key="column.position">
        <FlowArrow v-if="index > 0" :kanbans="column.kanbans" />
        <div class="flex min-w-[15rem] flex-1 flex-col gap-3">
          <p class="text-xs uppercase tracking-wide opacity-50">
            {{ index === 0 ? "From the Backlog" : `Step ${column.position}` }}
          </p>
          <WorkStationCard
            v-for="station in column.stations"
            :key="station.id"
            :station="station"
          />
          <p v-if="column.stations.length > 1" class="text-xs italic opacity-50">
            {{ column.stations.length }} Branches in parallel
          </p>
        </div>
      </template>
    </div>
  </section>
</template>
