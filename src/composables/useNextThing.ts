import { onMounted, ref, watch, type Ref } from "vue"
import { postAction } from "../api"
import type { FlowConfirm, Person, PersonView } from "../types"

export function useNextThing(personId: Ref<string>) {
  const people = ref<Person[]>([])
  const view = ref<PersonView | null>(null)
  const error = ref<string | null>(null)
  const loading = ref(true)

  async function loadPeople() {
    const response = await fetch("/api/people")
    if (!response.ok) {
      throw new Error(`API answered ${response.status}`)
    }
    people.value = (await response.json()) as Person[]
  }

  async function load() {
    loading.value = true
    error.value = null
    try {
      if (people.value.length === 0) {
        await loadPeople()
      }
      if (personId.value === "") {
        view.value = null
        return
      }
      const response = await fetch(`/api/people/${encodeURIComponent(personId.value)}/next`)
      if (!response.ok) {
        throw new Error(`API answered ${response.status}`)
      }
      view.value = (await response.json()) as PersonView
    } catch (cause) {
      error.value = cause instanceof Error ? cause.message : String(cause)
    } finally {
      loading.value = false
    }
  }

  async function act(path: string, body: Record<string, unknown>): Promise<FlowConfirm | null> {
    const confirm = await postAction(path, body)
    if (!confirm) {
      await load()
    }
    return confirm
  }

  const pull = (station: string, reason?: string) =>
    act("/api/pull", { station, person: personId.value, reason })

  const finish = (station: string, piece: string, reason?: string) =>
    act("/api/finish", { station, piece, reason })

  const repair = (rework: string) => act("/api/rework/repair", { rework })

  const assign = (kind: "piece" | "rework", id: string, person: string) =>
    act("/api/assign", { kind, id, person })

  watch(personId, load)
  onMounted(load)

  return { people, view, error, loading, load, pull, finish, repair, assign }
}
