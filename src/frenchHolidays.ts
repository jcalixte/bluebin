import type { Holiday } from "./types"

/** Easter Sunday of `year` (Gregorian calendar), as a UTC date. */
function easterSunday(year: number): Date {
  const a = year % 19
  const b = Math.floor(year / 100)
  const c = year % 100
  const d = Math.floor(b / 4)
  const e = b % 4
  const f = Math.floor((b + 8) / 25)
  const g = Math.floor((b - f + 1) / 3)
  const h = (19 * a + b - d - g + 15) % 30
  const i = Math.floor(c / 4)
  const k = c % 4
  const l = (32 + 2 * e + 2 * i - h - k) % 7
  const m = Math.floor((a + 11 * h + 22 * l) / 451)
  const month = Math.floor((h + l - 7 * m + 114) / 31)
  const day = ((h + l - 7 * m + 114) % 31) + 1
  return new Date(Date.UTC(year, month - 1, day))
}

function isoDay(date: Date): string {
  return date.toISOString().slice(0, 10)
}

function daysAfter(date: Date, days: number): string {
  return isoDay(new Date(date.getTime() + days * 86_400_000))
}

/** The 11 public holidays of metropolitan France in `year`, by date. */
export function frenchHolidays(year: number): Holiday[] {
  const easter = easterSunday(year)
  const fixed = (month: number, day: number) =>
    `${year}-${String(month).padStart(2, "0")}-${String(day).padStart(2, "0")}`
  return [
    { day: fixed(1, 1), label: "Jour de l'an" },
    { day: daysAfter(easter, 1), label: "Lundi de Pâques" },
    { day: fixed(5, 1), label: "Fête du Travail" },
    { day: fixed(5, 8), label: "Victoire 1945" },
    { day: daysAfter(easter, 39), label: "Ascension" },
    { day: daysAfter(easter, 50), label: "Lundi de Pentecôte" },
    { day: fixed(7, 14), label: "Fête nationale" },
    { day: fixed(8, 15), label: "Assomption" },
    { day: fixed(11, 1), label: "Toussaint" },
    { day: fixed(11, 11), label: "Armistice 1918" },
    { day: fixed(12, 25), label: "Noël" },
  ].sort((x, y) => x.day.localeCompare(y.day))
}
