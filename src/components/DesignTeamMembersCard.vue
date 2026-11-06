<script setup lang="ts">
import { ref } from "vue"
import { maxNameLength } from "../composables/useDesign"
import type { DesignTeamMember } from "../types"

const teamMembers = defineModel<DesignTeamMember[]>({ required: true })

const props = defineProps<{ add: (name: string) => Promise<boolean> }>()

defineEmits<{ remove: [id: string] }>()

const name = ref("")
const adding = ref(false)

async function submit() {
  const trimmed = name.value.trim()
  if (trimmed === "") return
  adding.value = true
  try {
    if (await props.add(trimmed)) {
      name.value = ""
    }
  } finally {
    adding.value = false
  }
}
</script>

<template>
  <div class="card border border-base-300 bg-base-100 shadow-sm">
    <div class="card-body gap-4 p-5">
      <h3 class="card-title text-base">Team Members</h3>
      <p class="text-sm opacity-70">
        A new Team Member is added now. A changed name or a removed Team Member is saved with the
        other changes.
      </p>

      <p v-if="teamMembers.length === 0" class="text-sm opacity-70">No Team Member yet.</p>
      <ul v-else class="flex flex-col gap-2">
        <li v-for="(teamMember, index) in teamMembers" :key="teamMember.id" class="flex gap-2">
          <label class="min-w-0 flex-1">
            <span class="sr-only">Name of Team Member {{ index + 1 }}</span>
            <input
              v-model="teamMember.name"
              type="text"
              class="input input-sm w-full"
              :class="teamMember.name.trim() === '' ? 'input-warning' : ''"
              :maxlength="maxNameLength"
            />
          </label>
          <button
            type="button"
            class="btn btn-ghost btn-sm shrink-0"
            title="Remove this Team Member from the Line and from each Work Station"
            :aria-label="`Remove ${teamMember.name || `Team Member ${index + 1}`}`"
            @click="$emit('remove', teamMember.id)"
          >
            Remove
          </button>
        </li>
      </ul>

      <form class="flex gap-2" @submit.prevent="submit">
        <label class="min-w-0 flex-1">
          <span class="sr-only">Name of the new Team Member</span>
          <input
            v-model="name"
            type="text"
            class="input input-sm w-full"
            :maxlength="maxNameLength"
            placeholder="Name"
          />
        </label>
        <button type="submit" class="btn btn-sm" :disabled="adding || name.trim() === ''">
          <span v-if="adding" class="loading loading-spinner loading-xs" />
          Add a Team Member
        </button>
      </form>
    </div>
  </div>
</template>
