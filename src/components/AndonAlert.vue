<script setup lang="ts">
import type { Andon } from "../types"

defineProps<{
  andons: Andon[]
  /** The Team Member who looks: they close the stops they are Team Leader of. */
  teamMemberId?: string
  busy?: boolean
}>()

defineEmits<{ close: [station: string] }>()

function time(at: string) {
  return new Date(at).toLocaleTimeString(undefined, { hour: "2-digit", minute: "2-digit" })
}
</script>

<template>
  <div v-if="andons.length > 0" role="alert" class="alert alert-error mb-6 flex-col items-stretch">
    <p class="flex items-center gap-2 font-semibold">
      <span class="size-3 rounded-full bg-current motion-safe:animate-pulse" aria-hidden="true" />
      Andon
      <span v-if="andons.length > 1" class="badge badge-sm tabular-nums">
        {{ andons.length }}
      </span>
    </p>
    <!-- One row per Andon; on wider screens the rows share columns, so names,
         times and Team Leaders line up and the eye scans down, not across. -->
    <ul
      class="divide-y divide-error-content/20 text-sm sm:grid sm:grid-cols-[max-content_max-content_1fr_auto] sm:gap-x-4"
    >
      <li
        v-for="andon in andons"
        :key="andon.kind === 'stop' ? `stop-${andon.station}` : andon.rework"
        class="flex flex-wrap items-center gap-x-2 py-1.5 sm:col-span-full sm:grid sm:grid-cols-subgrid"
      >
        <strong>{{ andon.stationName }}</strong>
        <template v-if="andon.kind === 'stop'">
          <span class="tabular-nums">since {{ time(andon.raisedAt) }}</span>
          <span>
            <template v-if="andon.raisedBy">Raised by {{ andon.raisedBy }}. </template>
            <template v-if="andon.teamLeader"
              >Team Leader {{ andon.teamLeader }} is called.</template
            >
          </span>
          <button
            v-if="teamMemberId && teamMemberId === andon.teamLeaderId"
            class="btn btn-xs ml-auto"
            :disabled="busy"
            @click="$emit('close', andon.station)"
          >
            Close the Andon
          </button>
        </template>
        <template v-else>
          <span>Rework on {{ andon.piece }}</span>
          <span class="sm:col-span-2">
            Waits for {{ andon.waitingHours }} h of Working Time with nobody repairing it.
          </span>
        </template>
      </li>
    </ul>
  </div>
</template>
