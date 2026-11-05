<script setup lang="ts">
import { ref } from "vue"
import type { ReorderEffect } from "../types"

defineProps<{ message: string; effects?: ReorderEffect[]; busy?: boolean }>()

const emit = defineEmits<{ confirm: [reason: string]; cancel: [] }>()

const reason = ref("")

function confirm() {
  if (reason.value.trim() !== "") {
    emit("confirm", reason.value)
  }
}

function places(effect: ReorderEffect) {
  const count = Math.abs(effect.places)
  return `${count} ${count === 1 ? "place" : "places"} ${effect.places > 0 ? "later" : "earlier"}`
}

function signed(value: number) {
  return value > 0 ? `+${value}` : String(value)
}
</script>

<template>
  <dialog class="modal modal-open">
    <div class="modal-box">
      <h3 class="text-lg font-semibold">This is a Deviation</h3>
      <p class="py-2 text-sm opacity-80">{{ message }}</p>
      <div v-if="effects && effects.length > 0" class="mb-3">
        <p class="text-sm font-medium">What each Demand gets</p>
        <ul class="mt-1 grid gap-1 text-sm">
          <li v-for="effect in effects" :key="effect.demand" class="flex flex-wrap gap-x-2">
            <span class="font-medium">{{ effect.label }}</span>
            <span class="opacity-80">
              next Piece {{ places(effect) }} · {{ signed(effect.hours) }} h · Takt Gap
              {{ signed(effect.taktGap) }}
            </span>
          </li>
        </ul>
      </div>
      <label class="form-control">
        <span class="label-text text-sm">Why do you go on? One line, seen by everyone.</span>
        <input
          v-model="reason"
          class="input input-bordered mt-1 w-full"
          maxlength="120"
          placeholder="The Client called: this one ships today"
          @keyup.enter="confirm"
        />
      </label>
      <div class="modal-action">
        <button class="btn btn-ghost" @click="emit('cancel')">Cancel</button>
        <button class="btn btn-warning" :disabled="busy || reason.trim() === ''" @click="confirm">
          Record the Deviation
        </button>
      </div>
    </div>
  </dialog>
</template>
