<script setup lang="ts">
import { computed } from "vue"
import type { WorkStation } from "../types"

const props = defineProps<{ station: WorkStation }>()

const hasRework = computed(() => props.station.rework.length > 0)

/** A Work Station with every Blue Bin full holds the flow up: it can finish
 *  nothing more until the downstream Work Station pulls. */
const binsFull = computed(
  () =>
    props.station.blueBins.length > 0 && props.station.blueBins.every((bin) => bin.piece !== null),
)
</script>

<template>
  <article
    class="card h-full border bg-base-100 shadow-sm"
    :class="hasRework ? 'border-error border-2' : 'border-base-300'"
  >
    <div class="card-body gap-3 p-4">
      <header class="flex items-start justify-between gap-2">
        <div>
          <h3 class="font-semibold leading-tight">{{ station.name }}</h3>
          <p v-if="station.teamLeader" class="text-xs opacity-60">
            Team Leader {{ station.teamLeader }}
          </p>
        </div>
        <span
          class="badge badge-sm shrink-0"
          :class="station.kanbans > 0 ? 'badge-primary' : 'badge-ghost'"
          :title="`${station.kanbans} Kanban(s)`"
        >
          {{ station.kanbans }} Kanban
        </span>
      </header>

      <div>
        <p class="text-xs uppercase tracking-wide opacity-60">Blue Bins</p>
        <ul class="mt-1 flex flex-wrap gap-1">
          <li
            v-for="bin in station.blueBins"
            :key="bin.slot"
            class="rounded border px-2 py-1 text-xs"
            :class="
              bin.piece
                ? 'border-primary bg-primary text-primary-content'
                : 'border-dashed border-base-300 opacity-60'
            "
            :title="bin.demand ?? 'Empty Blue Bin'"
          >
            {{ bin.piece ?? "empty" }}
          </li>
        </ul>
        <p v-if="binsFull" class="mt-1 text-xs font-medium text-warning">Every Blue Bin is full</p>
      </div>

      <div v-if="station.inProgress.length > 0">
        <p class="text-xs uppercase tracking-wide opacity-60">In the hands of</p>
        <ul class="mt-1 space-y-1 text-sm">
          <li v-for="item in station.inProgress" :key="item.piece">
            <span class="font-medium">{{ item.piece }}</span>
            <span class="opacity-60"> · {{ item.person ?? "unassigned" }}</span>
          </li>
        </ul>
      </div>

      <div v-if="hasRework" class="rounded bg-error/10 p-2">
        <p class="text-xs font-semibold uppercase tracking-wide text-error">Rework</p>
        <ul class="mt-1 space-y-1 text-sm">
          <li v-for="item in station.rework" :key="item.piece">
            <span class="font-medium">{{ item.piece }}</span>
            <span class="opacity-70"> — {{ item.description }}</span>
          </li>
        </ul>
      </div>

      <footer class="flex flex-wrap gap-1">
        <span
          v-for="person in station.people"
          :key="person.name"
          class="badge badge-sm badge-outline gap-1"
        >
          <span
            class="inline-block size-1.5 rounded-full"
            :class="person.busy ? 'bg-primary' : 'bg-base-content/30'"
          />
          {{ person.name }}
        </span>
      </footer>
    </div>
  </article>
</template>
