import { computed, onMounted, ref } from "vue"
import { api } from "../api"
import type { Design, DesignInput, DesignTeamMember, DesignStationInput, Labels } from "../types"
import { useLabels } from "./useLabels"
import { useLiveUpdates } from "./useLiveUpdates"

/** Must match max_name_length in backend/src/bluebin/line.gleam. */
export const maxNameLength = 40

export type DraftStation = DesignStationInput & {
  key: string
  locked: boolean
  minBlueBins: number
}

export type DraftStep = {
  key: string
  name: string
  stations: DraftStation[]
}

export type DesignDraft = {
  labels: Labels
  teamMembers: DesignTeamMember[]
  steps: DraftStep[]
}

type DesignShape = {
  labels: Labels
  teamMembers: DesignTeamMember[]
  steps: { name: string; stations: DesignStationInput[] }[]
}

let nextKey = 0
const newKey = () => `new-${nextKey++}`

function toDraft(design: Design): DesignDraft {
  return {
    labels: { ...design.labels },
    teamMembers: design.teamMembers.map((teamMember) => ({ ...teamMember })),
    steps: design.steps.map((step) => ({
      key: newKey(),
      name: step.name,
      stations: step.stations.map((station) => ({
        ...station,
        key: station.id,
        teamMembers: [...station.teamMembers],
      })),
    })),
  }
}

function toPayload(design: DesignShape): DesignInput {
  return {
    labels: {
      demand: design.labels.demand.trim(),
      demands: design.labels.demands.trim(),
      piece: design.labels.piece.trim(),
      pieces: design.labels.pieces.trim(),
    },
    teamMembers: design.teamMembers.map((teamMember) => ({
      id: teamMember.id,
      name: teamMember.name.trim(),
      email: teamMember.email.trim(),
    })),
    steps: design.steps.map((step) => ({
      name: step.name.trim(),
      stations: step.stations.map((station) => ({
        id: station.id,
        name: station.name.trim(),
        branch: station.branch === null ? null : station.branch.trim(),
        blueBins: Number(station.blueBins),
        teamLeader: station.teamLeader,
        teamMembers: [...station.teamMembers].sort(),
      })),
    })),
  }
}

export function newStation(branch: string | null): DraftStation {
  return {
    key: newKey(),
    id: null,
    name: "New Work Station",
    branch,
    blueBins: 1,
    teamLeader: "",
    teamMembers: [],
    locked: false,
    minBlueBins: 1,
  }
}

export function isBranchStep(step: DraftStep) {
  return step.stations.some((station) => station.branch !== null)
}

function branchSet(step: DraftStep) {
  return step.stations.map((station) => (station.branch ?? "").trim()).sort()
}

function freshBranch(taken: string[]) {
  let n = 1
  while (taken.includes(`Branch ${n}`)) n++
  return `Branch ${n}`
}

/** The rules the server checks, as hints. The server stays the judge. */
export function designProblems(draft: DesignDraft): string[] {
  const problems: string[] = []
  const steps = draft.steps
  const labels = Object.values(draft.labels)
  if (labels.some((label) => label.trim() === "")) {
    problems.push("Give a name to each label.")
  }
  if (draft.teamMembers.some((teamMember) => teamMember.name.trim() === "")) {
    problems.push("Give a name to each Team Member.")
  }
  if (steps.length === 0) {
    problems.push("The Line needs one step or more.")
  }
  steps.forEach((step, index) => {
    const name = step.name.trim() === "" ? `Step ${index + 1}` : `"${step.name.trim()}"`
    if (step.name.trim() === "") {
      problems.push(`Give a name to step ${index + 1}.`)
    }
    if (step.stations.length === 0) {
      problems.push(`${name} has no Work Station. Add one or remove the step.`)
      return
    }
    const branches = branchSet(step)
    if (step.stations.length === 1 && step.stations[0].branch !== null) {
      problems.push(`${name} has only one Branch. Add a Branch, or make it one Work Station.`)
    }
    if (step.stations.length > 1) {
      if (branches.some((branch) => branch === "")) {
        problems.push(`Give a name to each Branch in ${name}.`)
      } else if (new Set(branches).size !== branches.length) {
        problems.push(`Each Branch in ${name} must have a different name.`)
      }
    }
    const branch = isBranchStep(step)
    if (branch && (index === 0 || index === steps.length - 1)) {
      problems.push(
        `${name} has Branches. The first and the last step must each have one Work Station.`,
      )
    }
    const previous = steps[index - 1]
    if (branch && previous && isBranchStep(previous)) {
      if (branchSet(previous).join("\n") !== branches.join("\n")) {
        problems.push(`${name} must have the same Branches as the step before it.`)
      }
    }
    for (const station of step.stations) {
      const label = station.name.trim() === "" ? `A Work Station in ${name}` : station.name.trim()
      if (station.name.trim() === "") {
        problems.push(`Give a name to each Work Station in ${name}.`)
      }
      if (!(Number(station.blueBins) >= station.minBlueBins)) {
        problems.push(`${label} needs ${station.minBlueBins} Blue Bins or more.`)
      }
      if (station.teamMembers.length === 0) {
        problems.push(`${label} needs one Team Member or more.`)
      } else if (!station.teamMembers.includes(station.teamLeader)) {
        problems.push(`Pick a Team Leader for ${label} from its Team Members.`)
      }
    }
  })
  return problems
}

function message(cause: unknown) {
  return cause instanceof Error ? cause.message : String(cause)
}

export function useDesign() {
  const saved = ref<Design | null>(null)
  const draft = ref<DesignDraft | null>(null)
  const error = ref<string | null>(null)
  const loading = ref(true)
  const saving = ref(false)
  const { reload: reloadLabels } = useLabels()

  const dirty = computed(
    () =>
      saved.value !== null &&
      draft.value !== null &&
      JSON.stringify(toPayload(draft.value)) !== JSON.stringify(toPayload(saved.value)),
  )

  const problems = computed(() => (draft.value ? designProblems(draft.value) : []))

  function apply(design: Design) {
    saved.value = design
    draft.value = toDraft(design)
  }

  async function load() {
    loading.value = true
    try {
      const response = await fetch(api("/api/design"))
      if (!response.ok) {
        throw new Error(`API answered ${response.status}`)
      }
      const design = (await response.json()) as Design
      if (!dirty.value) {
        apply(design)
      }
    } catch (cause) {
      error.value = `The Design did not load: ${message(cause)}`
    } finally {
      loading.value = false
    }
  }

  function discard() {
    if (saved.value) {
      draft.value = toDraft(saved.value)
    }
    return load()
  }

  async function save() {
    if (!draft.value) return
    saving.value = true
    try {
      const response = await fetch(api("/api/design"), {
        method: "PUT",
        headers: { "content-type": "application/json" },
        body: JSON.stringify(toPayload(draft.value)),
      })
      if (!response.ok) {
        throw new Error((await response.text()) || `API answered ${response.status}`)
      }
      apply((await response.json()) as Design)
      await reloadLabels()
    } catch (cause) {
      error.value = `The changes were not saved: ${message(cause)}`
    } finally {
      saving.value = false
    }
  }

  async function addTeamMember(name: string) {
    try {
      const response = await fetch(api("/api/team-members"), {
        method: "POST",
        headers: { "content-type": "application/json" },
        body: JSON.stringify({ name }),
      })
      if (!response.ok) {
        throw new Error((await response.text()) || `API answered ${response.status}`)
      }
      const added = (await response.json()) as Pick<DesignTeamMember, "id" | "name">
      const teamMember: DesignTeamMember = { ...added, email: "", account: null }
      saved.value?.teamMembers.push({ ...teamMember })
      draft.value?.teamMembers.push({ ...teamMember })
      return true
    } catch (cause) {
      error.value = `The Team Member was not added: ${message(cause)}`
      return false
    }
  }

  /** Saved with the other changes. Each Work Station lets the Team Member go too. */
  function removeTeamMember(id: string) {
    if (!draft.value) return
    draft.value.teamMembers = draft.value.teamMembers.filter((teamMember) => teamMember.id !== id)
    for (const station of steps().flatMap((step) => step.stations)) {
      station.teamMembers = station.teamMembers.filter((one) => one !== id)
      if (station.teamLeader === id) {
        station.teamLeader = station.teamMembers[0] ?? ""
      }
    }
  }

  function steps() {
    return draft.value?.steps ?? []
  }

  function addStepAfter(index: number) {
    steps().splice(index + 1, 0, { key: newKey(), name: "New step", stations: [newStation(null)] })
  }

  function removeStep(index: number) {
    if (steps()[index]?.stations.length === 0) {
      steps().splice(index, 1)
    }
  }

  /** A locked Work Station cannot move past another locked Work Station. */
  function canMove(index: number, delta: -1 | 1) {
    const list = steps()
    const other = list[index + delta]
    if (!other) return false
    const hasLocked = (step: DraftStep) => step.stations.some((station) => station.locked)
    return !(hasLocked(list[index]) && hasLocked(other))
  }

  function moveStep(index: number, delta: -1 | 1) {
    if (!canMove(index, delta)) return
    const list = steps()
    const [step] = list.splice(index, 1)
    list.splice(index + delta, 0, step)
  }

  /** A locked Work Station keeps its Branch, so it cannot split. */
  function canSplit(step: DraftStep) {
    return isBranchStep(step) || !step.stations.some((station) => station.locked)
  }

  /**
   * An empty step gets one Work Station. A trunk step splits into 2 Branches,
   * or into the Branches of the Branch step next to it. A Branch step gets
   * one more Branch.
   */
  function splitStep(index: number) {
    const list = steps()
    const step = list[index]
    if (!step || !canSplit(step)) return
    if (step.stations.length === 0) {
      step.stations.push(newStation(null))
      return
    }
    if (isBranchStep(step)) {
      step.stations.push(newStation(freshBranch(branchSet(step))))
      return
    }
    const neighbour = [list[index - 1], list[index + 1]].find(
      (one) => one !== undefined && isBranchStep(one) && one.stations.length > 1,
    )
    const names = neighbour ? branchSet(neighbour) : []
    const [first] = step.stations
    first.branch = names[0] ?? (first.name.trim() || "Branch 1")
    if (names.length > 1) {
      for (const name of names.slice(1)) step.stations.push(newStation(name))
    } else {
      step.stations.push(newStation(freshBranch(branchSet(step))))
    }
  }

  /** The last Branch left in a step becomes its one Work Station, unless it is locked. */
  function removeStation(stepIndex: number, stationIndex: number) {
    const step = steps()[stepIndex]
    const station = step?.stations[stationIndex]
    if (!step || !station || station.locked) return
    step.stations.splice(stationIndex, 1)
    const [last] = step.stations
    if (step.stations.length === 1 && !last.locked) {
      last.branch = null
    }
  }

  onMounted(load)
  useLiveUpdates(() => (dirty.value ? Promise.resolve() : load()))

  return {
    draft,
    error,
    loading,
    saving,
    dirty,
    problems,
    load,
    save,
    discard,
    addTeamMember,
    removeTeamMember,
    addStepAfter,
    removeStep,
    canMove,
    moveStep,
    canSplit,
    splitStep,
    removeStation,
  }
}
