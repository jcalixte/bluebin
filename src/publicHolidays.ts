import type { Holiday } from "./types"

const api = "/api/holidays"

export type Country = { countryCode: string; name: string }

type NagerHoliday = {
  date: string
  localName: string
  global: boolean
  types: string[]
}

async function get<T>(path: string): Promise<T> {
  const response = await fetch(`${api}${path}`).catch(() => {
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

export async function fetchPublicHolidays(year: number, country: string): Promise<Holiday[]> {
  const holidays = await get<NagerHoliday[]>(`/${year}/${country}`)
  return holidays
    .filter((holiday) => holiday.global && holiday.types.includes("Public"))
    .map((holiday) => ({ day: holiday.date, label: holiday.localName }))
}
