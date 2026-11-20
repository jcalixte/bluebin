<script setup lang="ts">
import { ref } from "vue"
import AppModal from "./AppModal.vue"
import WorkingCalendarForm from "./WorkingCalendarForm.vue"
import type { WorkingCalendar } from "../types"
import { workingCalendarLabel } from "../workingCalendar"

defineProps<{
  calendar: WorkingCalendar | null
  error: string | null
  save: (calendar: WorkingCalendar) => Promise<void>
}>()

const editing = ref(false)
</script>

<template>
  <p v-if="error" class="text-sm text-error">The Working Calendar did not load: {{ error }}</p>
  <p v-else-if="calendar" class="flex flex-wrap items-center gap-x-2 text-sm">
    <span>
      <span class="opacity-70">Working Time:</span>
      {{ workingCalendarLabel(calendar) }}
    </span>
    <button
      type="button"
      class="btn btn-ghost btn-sm -my-1 px-2 font-normal underline decoration-dotted underline-offset-4 hover:decoration-solid"
      aria-haspopup="dialog"
      @click="editing = true"
    >
      Change<span class="sr-only"> the Working Calendar</span>
    </button>
  </p>
  <AppModal v-if="editing && calendar" @close="editing = false">
    <WorkingCalendarForm
      :calendar="calendar"
      :save="save"
      @saved="editing = false"
      @cancel="editing = false"
    />
  </AppModal>
</template>
