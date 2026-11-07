<script setup lang="ts">
import { ref, watch } from "vue"
import type { WorkingCalendar } from "../types"
import { frenchHolidays } from "../frenchHolidays"

const props = defineProps<{
  calendar: WorkingCalendar
  save: (calendar: WorkingCalendar) => Promise<void>
}>()

const weekdays = [
  { value: 1, label: "Mon" },
  { value: 2, label: "Tue" },
  { value: 3, label: "Wed" },
  { value: 4, label: "Thu" },
  { value: 5, label: "Fri" },
  { value: 6, label: "Sat" },
  { value: 0, label: "Sun" },
]

function copy(calendar: WorkingCalendar): WorkingCalendar {
  return {
    days: [...calendar.days],
    start: calendar.start,
    end: calendar.end,
    holidays: calendar.holidays.map((holiday) => ({ ...holiday })),
  }
}

const draft = ref(copy(props.calendar))
watch(
  () => props.calendar,
  (calendar) => (draft.value = copy(calendar)),
)

const saving = ref(false)
const saveError = ref<string | null>(null)
const saved = ref(false)
watch(draft, () => (saved.value = false), { deep: true })

function addHoliday() {
  draft.value.holidays.push({ day: "", label: "" })
}

const frenchYear = ref(new Date().getFullYear())

/** Adds the French public holidays of the year the calendar does not hold yet. */
function addFrenchHolidays() {
  const days = new Set(draft.value.holidays.map((holiday) => holiday.day))
  for (const holiday of frenchHolidays(frenchYear.value)) {
    if (days.has(holiday.day)) continue
    days.add(holiday.day)
    draft.value.holidays.push(holiday)
  }
  draft.value.holidays.sort((a, b) => a.day.localeCompare(b.day))
}

function removeHoliday(index: number) {
  draft.value.holidays.splice(index, 1)
}

async function submit() {
  saving.value = true
  saveError.value = null
  saved.value = false
  try {
    await props.save({
      ...draft.value,
      days: [...draft.value.days].sort((a, b) => a - b),
      holidays: draft.value.holidays.filter(
        (holiday) => holiday.day !== "" || holiday.label !== "",
      ),
    })
    saved.value = true
  } catch (cause) {
    saveError.value = cause instanceof Error ? cause.message : String(cause)
  } finally {
    saving.value = false
  }
}
</script>

<template>
  <div class="card border border-base-300 bg-base-100 shadow-sm">
    <form class="card-body gap-4 p-5" @submit.prevent="submit">
      <h3 class="card-title text-base">Working Calendar</h3>
      <p class="text-sm opacity-70">
        Every measure and the Takt Time are recomputed from the flow log with the new calendar.
      </p>

      <fieldset>
        <legend class="mb-2 text-sm font-medium">Working days</legend>
        <div class="flex flex-wrap gap-3">
          <label
            v-for="weekday in weekdays"
            :key="weekday.value"
            class="flex items-center gap-1.5 text-sm"
          >
            <input
              v-model="draft.days"
              type="checkbox"
              class="checkbox checkbox-sm"
              :value="weekday.value"
            />
            {{ weekday.label }}
          </label>
        </div>
      </fieldset>

      <div class="flex flex-wrap gap-4">
        <label class="flex flex-col gap-1 text-sm">
          <span class="font-medium">Start (UTC)</span>
          <input v-model="draft.start" type="time" class="input input-sm" required />
        </label>
        <label class="flex flex-col gap-1 text-sm">
          <span class="font-medium">End (UTC)</span>
          <input v-model="draft.end" type="time" class="input input-sm" required />
        </label>
      </div>

      <fieldset>
        <legend class="mb-2 text-sm font-medium">Holidays</legend>
        <p v-if="draft.holidays.length === 0" class="mb-2 text-sm opacity-70">No holidays.</p>
        <ul v-else class="mb-2 flex flex-col gap-2">
          <li v-for="(holiday, index) in draft.holidays" :key="index" class="flex gap-2">
            <input
              v-model="holiday.day"
              type="date"
              class="input input-sm w-40"
              aria-label="Holiday date"
            />
            <input
              v-model="holiday.label"
              type="text"
              class="input input-sm min-w-0 flex-1"
              placeholder="Label"
              aria-label="Holiday label"
            />
            <button
              type="button"
              class="btn btn-ghost btn-sm"
              title="Remove this holiday"
              @click="removeHoliday(index)"
            >
              Remove
            </button>
          </li>
        </ul>
        <div class="flex flex-wrap items-center gap-2">
          <button type="button" class="btn btn-ghost btn-sm" @click="addHoliday">
            Add a holiday
          </button>
          <div class="join">
            <input
              v-model.number="frenchYear"
              type="number"
              min="1900"
              max="2100"
              class="input input-sm join-item w-24"
              aria-label="Year of the French holidays"
            />
            <button
              type="button"
              class="btn btn-ghost btn-sm join-item"
              title="Add the 11 public holidays of metropolitan France for this year"
              :disabled="!Number.isInteger(frenchYear)"
              @click="addFrenchHolidays"
            >
              Add French holidays
            </button>
          </div>
        </div>
      </fieldset>

      <div v-if="saveError" class="alert alert-error text-sm">
        <span>{{ saveError }}</span>
      </div>

      <div class="flex items-center gap-3">
        <button type="submit" class="btn btn-primary btn-sm" :disabled="saving">
          <span v-if="saving" class="loading loading-spinner loading-xs" />
          Save
        </button>
        <span v-if="saved && !saving" class="text-sm opacity-70">Saved.</span>
      </div>
    </form>
  </div>
</template>
