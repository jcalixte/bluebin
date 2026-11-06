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
      <span class="inline-block size-3 rounded-full bg-current" />
      Andon
    </p>
    <ul class="space-y-1 text-sm">
      <li
        v-for="andon in andons"
        :key="andon.kind === 'stop' ? `stop-${andon.station}` : andon.rework"
        class="flex flex-wrap items-center gap-2"
      >
        <template v-if="andon.kind === 'stop'">
          <span>
            <strong>{{ andon.stationName }}</strong> stopped at {{ time(andon.raisedAt) }}
            <template v-if="andon.raisedBy"> by {{ andon.raisedBy }}</template
            >.
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
        <span v-else>
          <strong>{{ andon.stationName }}</strong
          >: the Rework on {{ andon.piece }} waits for {{ andon.waitingHours }} h of Working Time
          with nobody repairing it.
        </span>
      </li>
    </ul>
  </div>
</template>
