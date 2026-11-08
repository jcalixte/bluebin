<script setup lang="ts">
import { ref } from "vue"
import type { HelpOffer, ReorderEffect } from "../types"
import AppModal from "./AppModal.vue"

const props = defineProps<{
  message: string
  effects?: ReorderEffect[]
  busy?: boolean
  /** Help the Rework, offered before the Deviation (F14). */
  helps?: HelpOffer[]
}>()

const emit = defineEmits<{ confirm: [reason: string]; cancel: []; help: [rework: string] }>()

const reason = ref("")

/** With a help to offer, the reason opens only when the Team Member goes on anyway. */
const goingOn = ref((props.helps ?? []).length === 0)

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
  <AppModal @close="emit('cancel')">
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
    <div v-if="!goingOn" class="grid gap-2">
      <template v-for="offer in helps" :key="offer.rework">
        <button
          class="btn btn-primary justify-start"
          :disabled="busy || offer.blocked !== null"
          :aria-describedby="offer.blocked ? `blocked-${offer.rework}` : undefined"
          @click="emit('help', offer.rework)"
        >
          {{ offer.label }}
        </button>
        <p v-if="offer.blocked" :id="`blocked-${offer.rework}`" class="text-xs opacity-70">
          {{ offer.blocked }}
        </p>
      </template>
      <div class="modal-action mt-2 items-center justify-between">
        <button class="btn btn-link btn-sm px-0" @click="goingOn = true">
          Go on anyway (Deviation) ›
        </button>
        <button class="btn btn-ghost" @click="emit('cancel')">Cancel</button>
      </div>
    </div>
    <label v-if="goingOn" class="form-control">
      <span class="label-text text-sm">Why do you go on? One line, seen by everyone.</span>
      <input
        v-model="reason"
        class="input input-bordered mt-1 w-full"
        maxlength="120"
        placeholder="The Client called: this one ships today"
        @keyup.enter="confirm"
      />
    </label>
    <div v-if="goingOn" class="modal-action">
      <button class="btn btn-ghost" @click="emit('cancel')">Cancel</button>
      <button class="btn btn-warning" :disabled="busy || reason.trim() === ''" @click="confirm">
        Record the Deviation
      </button>
    </div>
  </AppModal>
</template>
