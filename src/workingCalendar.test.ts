import assert from "node:assert/strict"
import { test } from "node:test"
import { workingCalendarLabel, workingDaysLabel } from "./workingCalendar.ts"

test("working days fold into ranges of three or more", () => {
  assert.equal(workingDaysLabel([1, 2, 3, 4, 5]), "Mon–Fri")
  assert.equal(workingDaysLabel([1, 3, 5]), "Mon, Wed, Fri")
  assert.equal(workingDaysLabel([1, 2, 4, 5, 6]), "Mon, Tue, Thu–Sat")
  assert.equal(workingDaysLabel([6, 0]), "Sat, Sun")
})

test("a week that runs from Sunday starts on Sunday", () => {
  assert.equal(workingDaysLabel([0, 1, 2, 3, 4]), "Sun–Thu")
})

test("no day and every day read as words", () => {
  assert.equal(workingDaysLabel([]), "No working day")
  assert.equal(workingDaysLabel([0, 1, 2, 3, 4, 5, 6]), "Every day")
})

test("the calendar line leaves out holidays when there are none", () => {
  const calendar = { days: [1, 2, 3, 4, 5], start: "08:00", end: "17:00", holidays: [] }
  assert.equal(workingCalendarLabel(calendar), "Mon–Fri, 08:00–17:00 UTC")
  const one = { ...calendar, holidays: [{ day: "2026-12-25", label: "Christmas" }] }
  assert.equal(workingCalendarLabel(one), "Mon–Fri, 08:00–17:00 UTC, 1 holiday")
})
