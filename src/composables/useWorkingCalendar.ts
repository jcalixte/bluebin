import { onMounted, ref } from "vue"
import type { WorkingCalendar } from "../types"

export function useWorkingCalendar(afterSave?: () => Promise<unknown>) {
  const calendar = ref<WorkingCalendar | null>(null)
  const calendarError = ref<string | null>(null)

  async function loadCalendar() {
    calendarError.value = null
    try {
      const response = await fetch("/api/calendar")
      if (!response.ok) {
        throw new Error(`API answered ${response.status}`)
      }
      calendar.value = (await response.json()) as WorkingCalendar
    } catch (cause) {
      calendarError.value = cause instanceof Error ? cause.message : String(cause)
    }
  }

  async function saveCalendar(next: WorkingCalendar) {
    const response = await fetch("/api/calendar", {
      method: "PUT",
      headers: { "content-type": "application/json" },
      body: JSON.stringify(next),
    })
    if (!response.ok) {
      throw new Error((await response.text()) || `API answered ${response.status}`)
    }
    calendar.value = (await response.json()) as WorkingCalendar
    await afterSave?.()
  }

  onMounted(loadCalendar)

  return { calendar, calendarError, saveCalendar }
}
