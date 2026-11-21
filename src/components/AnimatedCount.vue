<script setup lang="ts">
import { computed } from "vue"

const props = defineProps<{ value: number }>()

/** daisyUI countdown only draws whole numbers from 0 to 999. */
const rolls = computed(
  () => Number.isInteger(props.value) && props.value >= 0 && props.value <= 999,
)
</script>

<template>
  <template v-if="rolls">
    <!-- The hidden text inside gives the box a text baseline, so the digits line up. -->
    <span class="countdown" aria-hidden="true">
      <span :style="{ '--value': value }">{{ value }}</span>
    </span>
    <span class="sr-only">{{ value }}</span>
  </template>
  <template v-else>{{ value }}</template>
</template>
