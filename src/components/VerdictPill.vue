<script setup lang="ts">
import type { Verdict } from "./CompareCell.vue"

/** `plain` keeps the surrounding ink, for a filled surface where the primary colour does not read. */
defineProps<{ verdict: Verdict; plain?: boolean }>()
</script>

<template>
  <span
    v-if="verdict"
    class="rounded-full border border-current px-2 text-xs font-medium whitespace-nowrap"
    :class="plain ? '' : verdict === 'better' ? 'text-primary' : 'opacity-70'"
  >
    {{ verdict }}
  </span>
</template>
