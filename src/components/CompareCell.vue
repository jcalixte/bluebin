<script setup lang="ts">
export type Verdict = "better" | "worse" | null

defineProps<{ after: string; before: string; verdict?: Verdict }>()
</script>

<template>
  <td class="text-right tabular-nums">
    <span class="font-medium" :class="{ 'text-primary': verdict === 'better' }">{{ after }}</span>
    <span v-if="verdict" class="sr-only">, {{ verdict }} than before</span>
    <span class="block text-xs opacity-60"><span class="sr-only">before </span>{{ before }}</span>
  </td>
</template>
