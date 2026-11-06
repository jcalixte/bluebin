<script setup lang="ts">
import { ref } from "vue"
import { maxNameLength } from "../composables/useDesign"
import type { DesignPerson } from "../types"

const people = defineModel<DesignPerson[]>({ required: true })

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
      <h3 class="card-title text-base">People</h3>
      <p class="text-sm opacity-70">
        A new Person is added now. A changed name or a removed Person is saved with the other
        changes.
      </p>

      <p v-if="people.length === 0" class="text-sm opacity-70">No Person yet.</p>
      <ul v-else class="flex flex-col gap-2">
        <li v-for="(person, index) in people" :key="person.id" class="flex gap-2">
          <label class="min-w-0 flex-1">
            <span class="sr-only">Name of Person {{ index + 1 }}</span>
            <input
              v-model="person.name"
              type="text"
              class="input input-sm w-full"
              :class="person.name.trim() === '' ? 'input-warning' : ''"
              :maxlength="maxNameLength"
            />
          </label>
          <button
            type="button"
            class="btn btn-ghost btn-sm shrink-0"
            title="Remove this Person from the Line and from each Work Station"
            :aria-label="`Remove ${person.name || `Person ${index + 1}`}`"
            @click="$emit('remove', person.id)"
          >
            Remove
          </button>
        </li>
      </ul>

      <form class="flex gap-2" @submit.prevent="submit">
        <label class="min-w-0 flex-1">
          <span class="sr-only">Name of the new Person</span>
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
          Add a Person
        </button>
      </form>
    </div>
  </div>
</template>
