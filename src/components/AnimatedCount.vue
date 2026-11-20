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
    <span class="countdown" aria-hidden="true">
      <span :style="{ '--value': value }" />
    </span>
    <span class="sr-only">{{ value }}</span>
  </template>
  <template v-else>{{ value }}</template>
</template>
