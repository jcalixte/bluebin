<script setup lang="ts">
import { computed, ref } from "vue"
import { lineFetch } from "../api"
import { useLabels } from "../composables/useLabels"
import AppModal from "./AppModal.vue"

const emit = defineEmits<{ created: []; close: [] }>()

const { labels } = useLabels()

/** Must match the limits of POST /api/demands in the backend. */
const maxNameLength = 60
const maxPieces = 200

function today() {
  const date = new Date()
  const month = String(date.getMonth() + 1).padStart(2, "0")
  const day = String(date.getDate()).padStart(2, "0")
  return `${date.getFullYear()}-${month}-${day}`
}

const minDueOn = today()

const label = ref("")
const client = ref("")
const dueOn = ref("")
const pieces = ref(1)
const saving = ref(false)
const problem = ref<string | null>(null)

const ready = computed(
  () =>
    label.value.trim() !== "" &&
    client.value.trim() !== "" &&
    dueOn.value >= minDueOn &&
    Number.isInteger(pieces.value) &&
    pieces.value >= 1 &&
    pieces.value <= maxPieces,
)

async function create() {
  if (!ready.value || saving.value) return
  saving.value = true
  problem.value = null
  try {
    const response = await lineFetch("/api/demands", {
      method: "POST",
      headers: { "content-type": "application/json" },
      body: JSON.stringify({
        label: label.value.trim(),
        client: client.value.trim(),
        dueOn: dueOn.value,
        pieces: pieces.value,
      }),
    })
    if (!response.ok) {
      throw new Error((await response.text()) || `API answered ${response.status}`)
    }
    emit("created")
  } catch (cause) {
    problem.value = cause instanceof Error ? cause.message : String(cause)
  } finally {
    saving.value = false
  }
}
</script>

<template>
  <AppModal @close="emit('close')">
    <form class="grid gap-3" @submit.prevent="create">
      <h3 class="text-lg font-semibold">New {{ labels.demand }}</h3>
      <p class="text-sm opacity-80">
        Its {{ labels.pieces }} enter the Backlog now, and the Heijunka Sequence mixes them with the
        others.
      </p>
      <label class="flex flex-col gap-1 text-sm">
        <span class="font-medium">Name</span>
        <input
          v-model="label"
          class="input w-full"
          :maxlength="maxNameLength"
          placeholder="Offline mode"
          required
        />
      </label>
      <label class="flex flex-col gap-1 text-sm">
        <span class="font-medium">Client</span>
        <input
          v-model="client"
          class="input w-full"
          :maxlength="maxNameLength"
          placeholder="Mobile team"
          required
        />
      </label>
      <div class="grid gap-3 sm:grid-cols-2">
        <label class="flex flex-col gap-1 text-sm">
          <span class="font-medium">Due date</span>
          <input v-model="dueOn" type="date" class="input w-full" :min="minDueOn" required />
        </label>
        <label class="flex flex-col gap-1 text-sm">
          <span class="font-medium">Number of {{ labels.pieces }}</span>
          <input
            v-model.number="pieces"
            type="number"
            class="input w-full"
            min="1"
            :max="maxPieces"
            step="1"
            required
          />
        </label>
      </div>
      <div v-if="problem" role="alert" class="alert alert-error text-sm">
        <span>The {{ labels.demand }} was not created: {{ problem }}</span>
      </div>
      <div class="modal-action mt-1">
        <button type="button" class="btn btn-ghost" @click="emit('close')">Cancel</button>
        <button type="submit" class="btn btn-primary" :disabled="!ready || saving">
          Create the {{ labels.demand }}
        </button>
      </div>
    </form>
  </AppModal>
</template>
