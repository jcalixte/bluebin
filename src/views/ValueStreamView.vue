<script setup lang="ts">
import { computed, ref } from "vue"
import FlowConnectors from "../components/FlowConnectors.vue"
import StepName from "../components/StepName.vue"
import WorkStationCard from "../components/WorkStationCard.vue"
import { useValueStream } from "../composables/useValueStream"
import type { WorkStation } from "../types"

const { valueStream, error, loading, load, renameStep } = useValueStream()

/** The longest step name the API accepts; kept in step with the backend. */
const maxNameLength = 40

const renameError = ref<string | null>(null)

function stepName(position: number) {
  return (
    valueStream.value?.steps.find((step) => step.position === position)?.name ?? `Step ${position}`
  )
}

async function rename(position: number, name: string) {
  renameError.value = null
  try {
    await renameStep(position, name)
  } catch (cause) {
    renameError.value = cause instanceof Error ? cause.message : String(cause)
    await load()
  }
}

/** The element the connectors measure the cards against. */
const streamEl = ref<HTMLElement | null>(null)

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

    <div v-if="renameError" role="alert" class="alert alert-error mb-4">
      <span>The step was not renamed: {{ renameError }}</span>
    </div>

    <p v-if="loading" class="flex items-center gap-3 opacity-70">
      <span class="loading loading-spinner loading-sm" />
      Loading the Value Stream…
    </p>

    <div v-else-if="error" class="alert alert-error">
      <span>The API did not answer: {{ error }}</span>
    </div>

    <p v-else-if="columns.length === 0" class="opacity-70">No Work Station yet.</p>

    <div v-else class="overflow-x-auto pb-4">
      <div ref="streamEl" class="relative flex min-w-max gap-4">
        <template v-for="(column, index) in columns" :key="column.position">
          <div v-if="index > 0" class="w-24 shrink-0" />
          <div class="flex min-w-[15rem] flex-1 flex-col gap-3">
            <StepName
              :name="stepName(column.position)"
              :max-length="maxNameLength"
              @rename="(name) => rename(column.position, name)"
            />
            <div
              v-for="station in column.stations"
              :key="station.id"
              :data-column="index"
              :data-branch="station.branch ?? ''"
            >
              <WorkStationCard :station="station" />
            </div>
            <p v-if="column.stations.length > 1" class="text-xs italic opacity-50">
              {{ column.stations.length }} Branches in parallel
            </p>
          </div>
        </template>
        <FlowConnectors :container="streamEl" :columns="columns" />
      </div>
    </div>
  </section>
</template>
