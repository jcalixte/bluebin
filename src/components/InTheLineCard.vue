<script setup lang="ts">
import { computed } from "vue"
import { useLabels } from "../composables/useLabels"
import type { Line } from "../types"

const props = defineProps<{ line: Line }>()

const { labels } = useLabels()

type Row = {
  key: string
  piece: string
  demand: string
  station: string
  state: string
  who: string | null
}

/** Flow order: the first Work Station first, Deployment last. */
const rows = computed<Row[]>(() => {
  const stations = [...props.line.stations].sort((a, b) => a.position - b.position)
  const atStations = stations.flatMap((station) => [
    ...station.inProgress.map((item) => ({
      key: `work:${item.id}`,
      piece: item.piece,
      demand: item.demand,
      station: station.name,
      state: item.underRework ? "Under Rework" : item.paused ? "Paused" : "In progress",
      who: item.teamMember,
    })),
    ...station.blueBins.flatMap((bin) =>
      bin.piece === null
        ? []
        : [
            {
              key: `bin:${station.id}:${bin.slot}`,
              piece: bin.piece,
              demand: bin.demand ?? "",
              station: station.name,
              state: "Finished, in a Blue Bin",
              who: null,
            },
          ],
    ),
    ...station.overflow.map((extra) => ({
      key: `over:${extra.id}`,
      piece: extra.piece,
      demand: extra.demand,
      station: station.name,
      state: "Finished, over the Blue Bin count",
      who: null,
    })),
  ])
  const deployed = props.line.heldForRelease.map((held) => ({
    key: `held:${held.id}`,
    piece: held.piece,
    demand: held.demandLabel,
    station: "Deployment",
    state: "Waits for its Release",
    who: null,
  }))
  return [...atStations, ...deployed]
})
</script>

<template>
  <div class="card border border-base-300 bg-base-100 shadow-sm">
    <div class="card-body gap-3 p-5">
      <div>
        <h3 class="card-title text-base">In the Line</h3>
        <p class="text-sm opacity-70">
          {{ labels.pieces }} that left the Backlog, and the Work Station where each one is now.
        </p>
      </div>
      <p v-if="rows.length === 0" class="text-sm opacity-70">
        No {{ labels.piece }} is in the Line.
      </p>
      <div v-else class="overflow-x-auto">
        <table class="table table-sm">
          <thead>
            <tr>
              <th>{{ labels.piece }}</th>
              <th>{{ labels.demand }}</th>
              <th>Work Station</th>
              <th>State</th>
            </tr>
          </thead>
          <tbody>
            <tr v-for="row in rows" :key="row.key">
              <td class="font-mono">{{ row.piece }}</td>
              <td class="max-w-48 truncate opacity-70">{{ row.demand }}</td>
              <td class="font-medium">{{ row.station }}</td>
              <td>
                {{ row.state }}
                <span v-if="row.who" class="opacity-70">· {{ row.who }}</span>
              </td>
            </tr>
          </tbody>
        </table>
      </div>
    </div>
  </div>
</template>
