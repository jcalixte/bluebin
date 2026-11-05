<script setup lang="ts">
import { ref } from "vue"

defineProps<{ message: string; busy?: boolean }>()

const emit = defineEmits<{ confirm: [reason: string]; cancel: [] }>()

const reason = ref("")

function confirm() {
  if (reason.value.trim() !== "") {
    emit("confirm", reason.value)
  }
}
</script>

<template>
  <dialog class="modal modal-open">
    <div class="modal-box">
      <h3 class="text-lg font-semibold">This breaks a pull rule</h3>
      <p class="py-2 text-sm opacity-80">{{ message }}</p>
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
