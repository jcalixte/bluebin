import { ref } from "vue"
import { lookOnly } from "../api"
import { simulation } from "../simulation/state"
import type { Account } from "../types"
import type { AccountInput } from "../wire"

const account = ref<Account | null>(null)
const checked = ref(false)

async function fetchAccount() {
  // authentik guards `/api/account`: a look-only visitor or one in the Simulation would get its
  // sign-in page.
  if (lookOnly || simulation) {
    checked.value = true
    return
  }
  try {
    const response = await fetch("/api/account")
    if (response.ok) {
      account.value = (await response.json()) as Account
    }
  } catch {
    // The app still works without an Account; the first sign-in asks again later.
  } finally {
    checked.value = true
  }
}

let loaded: Promise<void> | null = null

/** Not inside a Line: one Account for every Line and Workspace. */
export function useAccount() {
  loaded ??= fetchAccount()

  async function saveName(firstName: string, lastName: string) {
    const response = await fetch("/api/account", {
      method: "PUT",
      headers: { "content-type": "application/json" },
      body: JSON.stringify({ firstName, lastName } satisfies AccountInput),
    })
    if (!response.ok) {
      throw new Error((await response.text()) || `API answered ${response.status}`)
    }
    account.value = (await response.json()) as Account
  }

  return { account, checked, saveName }
}
