<script setup lang="ts">
import { onBeforeUnmount, watch } from "vue"

const message = defineModel<string | null>({ required: true })

withDefaults(defineProps<{ tone?: "info" | "warning" | "error" }>(), { tone: "warning" })

let timer: ReturnType<typeof setTimeout> | undefined

watch(message, (now) => {
  clearTimeout(timer)
  if (now) {
    timer = setTimeout(() => (message.value = null), 8000)
  }
})

onBeforeUnmount(() => clearTimeout(timer))
</script>

<template>
  <div v-if="message" class="toast toast-end toast-bottom z-50">
    <div
      role="alert"
      class="alert max-w-sm whitespace-normal shadow-lg"
      :class="{
        'alert-error': tone === 'error',
        'alert-warning': tone === 'warning',
        'alert-info': tone === 'info',
      }"
    >
      <span>{{ message }}</span>
      <button
        type="button"
        class="btn btn-ghost btn-sm btn-square"
        aria-label="Dismiss"
        @click="message = null"
      >
        ✕
      </button>
    </div>
  </div>
</template>
