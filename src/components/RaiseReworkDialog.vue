<script setup lang="ts">
import { computed, ref } from "vue"
import AppModal from "./AppModal.vue"
import { isUpstream } from "../shape"
import type { WorkStation } from "../types"

const props = defineProps<{
  /** The Work Station that found the defect and holds the Piece. */
  station: string
  /** The name of the Piece, for the title. */
  reference: string
  stations: WorkStation[]
  busy: boolean
}>()

const emit = defineEmits<{ raise: [madeBy: string, description: string]; close: [] }>()

const choices = computed(() => {
  const nodes = props.stations.map((one) => ({
    id: one.id,
    position: one.position,
    branch: one.branch,
    parentBranch: one.parentBranch ?? null,
  }))
  return props.stations.filter((one) => isUpstream(nodes, one.id, props.station))
})

const [only, ...others] = choices.value
const madeBy = ref(only && others.length === 0 ? only.id : "")
const defect = ref("")

function raise() {
  if (madeBy.value === "" || defect.value.trim() === "") {
    return
  }
  emit("raise", madeBy.value, defect.value.trim())
}
</script>

<template>
  <AppModal @close="emit('close')">
    <h3 class="text-lg font-semibold">A defect in {{ reference }}</h3>
    <template v-if="choices.length > 0">
      <p class="py-2 text-sm opacity-80">
        The Piece stays here: name the Work Station that made the defect, and one of its Team
        Members comes to repair it.
      </p>
      <label class="form-control">
        <span class="label-text text-sm">Made by</span>
        <select v-model="madeBy" class="select select-bordered mt-1 w-full">
          <option value="" disabled>Pick a Work Station</option>
          <option v-for="one in choices" :key="one.id" :value="one.id">
            {{ one.name }}
          </option>
        </select>
      </label>
      <label class="form-control mt-2">
        <span class="label-text text-sm">What is wrong? One line.</span>
        <input
          v-model="defect"
          class="input input-bordered mt-1 w-full"
          maxlength="120"
          placeholder="Sync retries lose the last edit"
          @keyup.enter="raise"
        />
      </label>
    </template>
    <p v-else class="py-2 text-sm opacity-80">
      No Work Station is upstream of this one, so the defect was made here: fix it as part of this
      Piece.
    </p>
    <div class="modal-action">
      <button class="btn btn-ghost" @click="emit('close')">Cancel</button>
      <button
        v-if="choices.length > 0"
        class="btn btn-error"
        :disabled="busy || madeBy === '' || defect.trim() === ''"
        @click="raise"
      >
        Raise the Rework
      </button>
    </div>
  </AppModal>
</template>
