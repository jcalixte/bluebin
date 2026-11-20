import type { WorkingCalendar } from "./wire.ts"

const names = ["Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"]

export function workingDaysLabel(days: number[]): string {
  if (days.length === 0) return "No working day"
  if (days.length === 7) return "Every day"
  const weekStart = days.includes(0) && !days.includes(6) ? 0 : 1
  const order = [0, 1, 2, 3, 4, 5, 6].map((offset) => (weekStart + offset) % 7)
  const runs: number[][] = []
  for (const day of order) {
    if (!days.includes(day)) continue
    const run = runs.at(-1)
    const last = run?.at(-1)
    if (run && last !== undefined && order.indexOf(last) === order.indexOf(day) - 1) run.push(day)
    else runs.push([day])
  }
  return runs
    .flatMap((run) =>
      run.length >= 3 ? [`${names[run[0]!]}–${names[run.at(-1)!]}`] : run.map((day) => names[day]!),
    )
    .join(", ")
}

export function workingCalendarLabel(calendar: WorkingCalendar): string {
  const holidays = calendar.holidays.length
  const parts = [workingDaysLabel(calendar.days), `${calendar.start}–${calendar.end} UTC`]
  if (holidays > 0) parts.push(`${holidays} ${holidays === 1 ? "holiday" : "holidays"}`)
  return parts.join(", ")
}
