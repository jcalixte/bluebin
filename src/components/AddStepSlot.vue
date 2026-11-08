<script setup lang="ts">
defineProps<{ label: string }>()
defineEmits<{ add: [] }>()
</script>

<template>
  <div class="flex shrink-0 flex-col items-center lg:h-10 lg:flex-row">
    <span class="h-3 w-px bg-base-content/30 lg:h-px lg:w-3" aria-hidden="true" />
    <button
      type="button"
      class="btn btn-circle btn-ghost btn-sm relative border border-dashed after:absolute after:-inset-1.5 border-base-content/40 hover:border-primary hover:text-primary"
      :title="label"
      :aria-label="label"
      @click="$emit('add')"
    >
      <svg
        class="size-4"
        viewBox="0 0 24 24"
        fill="none"
        stroke="currentColor"
        stroke-width="2"
        stroke-linecap="round"
        stroke-linejoin="round"
        aria-hidden="true"
      >
        <path d="M12 5l0 14" />
        <path d="M5 12l14 0" />
      </svg>
    </button>
    <span class="h-3 w-px bg-base-content/30 lg:h-px lg:w-3" aria-hidden="true" />
    <svg
      class="size-3 rotate-90 text-base-content/40 lg:rotate-0"
      viewBox="0 0 24 24"
      fill="currentColor"
      aria-hidden="true"
    >
      <path d="M8 4l10 8l-10 8z" />
    </svg>
  </div>
</template>
