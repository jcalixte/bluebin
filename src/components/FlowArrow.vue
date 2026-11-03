<script setup lang="ts">
/** The link between two steps of the Value Stream: the Piece moves downstream,
 *  the Kanban that authorizes the next one travels back upstream. */
defineProps<{ kanbans: number }>()
</script>

<template>
  <div
    class="flex shrink-0 flex-col items-center justify-center gap-2 self-start pt-16 text-base-content/50"
  >
    <div class="flex flex-col items-center gap-0.5">
      <svg
        class="size-6 text-primary"
        viewBox="0 0 24 24"
        fill="none"
        stroke="currentColor"
        stroke-width="2"
        stroke-linecap="round"
        stroke-linejoin="round"
        aria-hidden="true"
      >
        <path d="M5 12h14" />
        <path d="M13 18l6 -6" />
        <path d="M13 6l6 6" />
      </svg>
      <span class="text-[0.625rem] uppercase tracking-wide">Piece</span>
    </div>

    <div class="flex flex-col items-center gap-0.5">
      <svg
        class="size-5"
        viewBox="0 0 24 24"
        fill="none"
        stroke="currentColor"
        stroke-width="2"
        stroke-linecap="round"
        stroke-linejoin="round"
        aria-hidden="true"
      >
        <path d="M5 12h14" />
        <path d="M5 12l6 6" />
        <path d="M5 12l6 -6" />
      </svg>
      <span class="text-[0.625rem] uppercase tracking-wide"> {{ kanbans }} Kanban </span>
    </div>
  </div>
</template>
