<script setup lang="ts">
import { onBeforeUnmount, onMounted, ref } from "vue"
import { lineFetch } from "../api"
import { actingAs, onSimulatedChange } from "../simulation/state"
import type { TeamMember } from "../types"

defineEmits<{ restart: [] }>()

const teamMembers = ref<TeamMember[]>([])

async function load() {
  const response = await lineFetch("/api/team-members")
  if (!response.ok) return
  teamMembers.value = (await response.json()) as TeamMember[]
  // A Team Member removed in Design can no longer be played.
  if (actingAs.value !== "" && !teamMembers.value.some((one) => one.id === actingAs.value)) {
    actingAs.value = ""
  }
}

let stop = () => {}
onMounted(() => {
  void load()
  stop = onSimulatedChange(() => void load())
})
onBeforeUnmount(() => stop())
</script>

<template>
  <div class="flex flex-wrap items-center gap-2">
    <span class="badge badge-neutral">Simulation</span>
    <label class="flex items-center gap-2 text-sm">
      <span>Play as</span>
      <select v-model="actingAs" class="select select-sm w-auto min-w-44 text-base-content">
        <option value="">The owner of the Line</option>
        <option v-for="one in teamMembers" :key="one.id" :value="one.id">
          {{ one.name || "Unnamed Team Member" }}
        </option>
      </select>
    </label>
    <button
      type="button"
      class="btn btn-sm btn-ghost [--btn-rest-fg:var(--color-primary-content)]"
      title="Load the demo data again, or start empty"
      @click="$emit('restart')"
    >
      Restart…
    </button>
  </div>
</template>
