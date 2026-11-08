import { simulation } from "./simulation/state"
import type { Holiday } from "./types"

/** The server asks Nager.Date (https://date.nager.at) and keeps its answers a month. */
const api = "/api/holidays"
/** The Simulation has no server: it asks Nager.Date itself, which allows any origin. */
const nager = "https://date.nager.at/api/v3"

/** `/countries` or `/2026/FR`, at the server or, in the Simulation, at Nager.Date. */
function urlOf(path: string): string {
  if (!simulation) return `${api}${path}`
  return path === "/countries" ? `${nager}/AvailableCountries` : `${nager}/PublicHolidays${path}`
}

export type Country = { countryCode: string; name: string }

type NagerHoliday = {
  date: string
  localName: string
  global: boolean
  types: string[]
}

async function get<T>(path: string): Promise<T> {
  const response = await fetch(urlOf(path)).catch(() => {
    throw new Error("Cannot reach the server.")
  })
  if (response.status === 404) {
    throw new Error("No public holidays for this country.")
  }
  if (!response.ok) {
    throw new Error("The public holiday service did not answer. Try again later.")
  }
  return response.json()
}

export async function fetchCountries(): Promise<Country[]> {
  const countries = await get<Country[]>("/countries")
  return countries.sort((a, b) => a.name.localeCompare(b.name))
}

/** The nationwide public holidays of `country` in `year`, by date. */
export async function fetchPublicHolidays(year: number, country: string): Promise<Holiday[]> {
  const holidays = await get<NagerHoliday[]>(`/${year}/${country}`)
  return holidays
    .filter((holiday) => holiday.global && holiday.types.includes("Public"))
    .map((holiday) => ({ day: holiday.date, label: holiday.localName }))
}
