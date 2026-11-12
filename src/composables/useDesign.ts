import { computed, onMounted, ref } from "vue"
import { lineFetch } from "../api"
import type {
  BlueBinSuggestion,
  Design,
  DesignInput,
  DesignTeamMember,
  DesignStationInput,
  Labels,
} from "../types"
import type { NameInput } from "../wire"
import { laneRows, upstream, type ShapeNode } from "../shape"
import { useLabels } from "./useLabels"
import { useLiveUpdates } from "./useLiveUpdates"

/** Must match max_name_length in backend/src/bluebin/line.gleam. */
export const maxNameLength = 40

export type DraftStation = Required<DesignStationInput> & {
  key: string
  locked: boolean
  minBlueBins: number
  /** Null for a Work Station added in this draft. */
  suggestion: BlueBinSuggestion | null
}

export type DraftStep = {
  key: string
  name: string
  stations: DraftStation[]
}

export type DesignDraft = {
  labels: Labels
  taktTimeHours: number
  teamMembers: DesignTeamMember[]
  steps: DraftStep[]
}

type DesignShape = {
  labels: Labels
  teamMembers: DesignTeamMember[]
  steps: { name: string; stations: Required<DesignStationInput>[] }[]
}

let nextKey = 0
const newKey = () => `new-${nextKey++}`

function toDraft(design: Design): DesignDraft {
  return {
    labels: { ...design.labels },
    taktTimeHours: design.taktTimeHours,
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
        parentBranch: station.parentBranch === null ? null : station.parentBranch.trim(),
        blueBins: Number(station.blueBins),
        teamLeader: station.teamLeader,
        teamMembers: [...station.teamMembers].sort(),
      })),
    })),
  }
}

export function freshName(base: string, taken: string[]) {
  const names = new Set(taken.map((name) => name.trim()))
  if (!names.has(base)) return base
  let n = 2
  while (names.has(`${base} ${n}`)) n++
  return `${base} ${n}`
}

function newStation(name: string, branch: string | null): DraftStation {
  return {
    key: newKey(),
    id: null,
    name,
    branch,
    parentBranch: null,
    blueBins: 1,
    teamLeader: "",
    teamMembers: [],
    locked: false,
    minBlueBins: 1,
    suggestion: null,
  }
}

export function isBranchStep(step: DraftStep) {
  return step.stations.some((station) => station.branch !== null)
}

function branchSet(step: DraftStep) {
  return step.stations.map((station) => (station.branch ?? "").trim()).sort()
}

function allBranches(steps: DraftStep[]) {
  return steps.flatMap(branchSet).filter((branch) => branch !== "")
}

function freshBranch(taken: string[]) {
  let n = 1
  while (taken.includes(`Branch ${n}`)) n++
  return `Branch ${n}`
}

/** Each Work Station of the draft as a node of its shape; the id is its key. */
export function draftNodes(steps: DraftStep[]): ShapeNode[] {
  return steps.flatMap((step, index) =>
    step.stations.map((station) => ({
      id: station.key,
      position: index + 1,
      branch: station.branch === null ? null : station.branch.trim(),
      parentBranch: station.parentBranch?.trim() || null,
    })),
  )
}

/** The lanes at each step, by step index, and the number of rows of the grid. */
export function draftLanes(steps: DraftStep[]) {
  const { lanes, rows } = laneRows(
    draftNodes(steps),
    steps.map((_, index) => index + 1),
  )
  return { lanes: steps.map((_, index) => lanes.get(index + 1) ?? []), rows }
}

/** The keys of the Work Stations each Work Station of the draft pulls from. */
export function draftUpstream(steps: DraftStep[]): Map<string, string[]> {
  const nodes = draftNodes(steps)
  return new Map(nodes.map((node) => [node.id, upstream(nodes, node)]))
}

/** Runs of steps between two trunk steps: the steps of one Split. */
function splits(steps: DraftStep[]): number[][] {
  const runs: number[][] = []
  let run: number[] = []
  steps.forEach((step, index) => {
    if (isBranchStep(step)) {
      run.push(index)
    } else if (step.stations.length > 0) {
      if (run.length > 0) runs.push(run)
      run = []
    }
  })
  if (run.length > 0) runs.push(run)
  return runs
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
    if (step.stations.length > 1 && step.stations.some((station) => station.branch === null)) {
      problems.push(`Give a Branch name to each Work Station in ${name}.`)
    } else if (isBranchStep(step)) {
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
  const named: string[] = []
  for (const run of splits(steps)) {
    const branches = [...new Set(run.flatMap((index) => branchSet(steps[index])))]
    const label =
      run.length === 1 ? `Step ${run[0] + 1}` : `Steps ${run[0] + 1} to ${run[run.length - 1] + 1}`
    const nodes = draftNodes(steps).filter((node) => run.includes(node.position - 1))
    const parentsOf = (branch: string) => [
      ...new Set(nodes.filter((node) => node.branch === branch).map((node) => node.parentBranch)),
    ]
    const outer = branches.filter((branch) => {
      const parents = parentsOf(branch)
      return parents.length === 1 && parents[0] === null
    })
    if (outer.length < 2) {
      problems.push(`${label} open one Branch only. Add a Branch, or remove the Branch name.`)
    }
    for (const branch of branches) {
      const parents = parentsOf(branch)
      if (parents.length > 1) {
        problems.push(
          `The Work Stations of the Branch "${branch}" must all be inside one outer Branch.`,
        )
      } else if (parents[0] && !outer.includes(parents[0])) {
        problems.push(
          `The Branch "${branch}" opens inside "${parents[0]}", which is not a Branch of its Split. A nested Branch does not split again.`,
        )
      }
    }
    for (const parent of outer) {
      const nested = nodes.filter((node) => node.parentBranch === parent)
      if (nested.length === 0) continue
      if (new Set(nested.map((node) => node.branch)).size < 2) {
        problems.push(
          `"${parent}" splits into one Branch only. A nested Split needs two Branches or more.`,
        )
      }
      const first = Math.min(...nested.map((node) => node.position))
      const last = Math.max(...nested.map((node) => node.position))
      const own = nodes.filter((node) => node.branch === parent).map((node) => node.position)
      if (
        !own.some((at) => at < first) ||
        !own.some((at) => at > last) ||
        own.some((at) => at >= first && at <= last)
      ) {
        problems.push(
          `"${parent}" needs one Work Station before its nested Split and one after it, which assembles its nested Branches.`,
        )
      }
    }
    named.push(...branches.filter((branch) => branch !== ""))
  }
  const twice = named.filter((branch, index) => named.indexOf(branch) !== index)
  if (twice.length > 0) {
    problems.push(
      `Two Splits have a Branch named "${twice[0]}". Each Branch name is unique in the Line.`,
    )
  }
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
      const response = await lineFetch("/api/design")
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
      const response = await lineFetch("/api/design", {
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
      const response = await lineFetch("/api/team-members", {
        method: "POST",
        headers: { "content-type": "application/json" },
        body: JSON.stringify({ name } satisfies NameInput),
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

  function stationNames() {
    return steps().flatMap((step) => step.stations.map((station) => station.name))
  }

  function addStation(step: DraftStep, branch: string | null) {
    const station = newStation(freshName("New Work Station", stationNames()), branch)
    step.stations.push(station)
    return station.key
  }

  /** Inside a Split the new step starts empty: each Branch gets a + there. */
  function addStepAfter(index: number) {
    const list = steps()
    const step: DraftStep = {
      key: newKey(),
      name: freshName(
        "New step",
        list.map((one) => one.name),
      ),
      stations: [],
    }
    const before = list[index]
    const after = list[index + 1]
    const insideSplit = before && after && isBranchStep(before) && isBranchStep(after)
    if (!insideSplit) addStation(step, null)
    list.splice(index + 1, 0, step)
    return step.key
  }

  /** A Work Station for `branch` at this step, in an empty cell of the grid. */
  function addStationAt(stepIndex: number, branch: string) {
    const step = steps()[stepIndex]
    if (!step || step.stations.some((station) => station.branch === null)) return null
    const parent =
      steps()
        .flatMap((one) => one.stations)
        .find((one) => one.branch?.trim() === branch)?.parentBranch ?? null
    const key = addStation(step, branch)
    const added = step.stations.find((one) => one.key === key)
    if (added) added.parentBranch = parent
    return key
  }

  function removeStep(index: number) {
    if (steps()[index]?.stations.length === 0) {
      steps().splice(index, 1)
    }
  }

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

  function splitStep(index: number): string | null {
    const list = steps()
    const step = list[index]
    if (!step || !canSplit(step)) return null
    const inSplit = (draftLanes(list).lanes[index] ?? []).some((lane) => lane !== null)
    if (isBranchStep(step) || inSplit) {
      return addStation(step, freshBranch(allBranches(list)))
    }
    if (step.stations.length === 0) {
      return addStation(step, null)
    }
    const neighbour = [list[index - 1], list[index + 1]].find(
      (one) => one !== undefined && isBranchStep(one) && one.stations.length > 1,
    )
    const names = neighbour ? branchSet(neighbour) : []
    const [first] = step.stations
    first.branch = names[0] ?? (first.name.trim() || "Branch 1")
    const branches = names.length > 1 ? names.slice(1) : [freshBranch(allBranches(list))]
    const keys = branches.map((branch) => addStation(step, branch))
    return keys[0]
  }

  /** An outer Branch opens one nested Split at most. */
  function canSplitBranch(station: DraftStation) {
    const outer = station.branch?.trim()
    if (!outer || station.parentBranch !== null) return false
    return !steps().some((step) => step.stations.some((one) => one.parentBranch?.trim() === outer))
  }

  /**
   * A nested Split after this Work Station of an outer Branch: a new step with
   * two nested Branches, then a new step where the outer Branch assembles them.
   * The other Branches skip both steps.
   */
  function splitBranch(stepIndex: number, stationIndex: number) {
    const list = steps()
    const station = list[stepIndex]?.stations[stationIndex]
    if (!station || !canSplitBranch(station)) return null
    const outer = station.branch?.trim() ?? ""
    const step = (): DraftStep => ({
      key: newKey(),
      name: freshName(
        "New step",
        steps().map((one) => one.name),
      ),
      stations: [],
    })
    const nested = step()
    list.splice(stepIndex + 1, 0, nested)
    const assembly = step()
    list.splice(stepIndex + 2, 0, assembly)
    const first = addStation(nested, freshBranch(allBranches(list)))
    addStation(nested, freshBranch(allBranches(list)))
    for (const one of nested.stations) one.parentBranch = outer
    addStation(assembly, outer)
    return first
  }

  function removeStation(stepIndex: number, stationIndex: number) {
    const step = steps()[stepIndex]
    const station = step?.stations[stationIndex]
    if (!step || !station || station.locked) return
    step.stations.splice(stationIndex, 1)
    const [last] = step.stations
    // A Split of one step with one Branch left is one Work Station again.
    const elsewhere = steps().some(
      (other) => other !== step && other.stations.some((one) => one.branch === last?.branch),
    )
    if (step.stations.length === 1 && !last.locked && !elsewhere) {
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
    addStationAt,
    canSplitBranch,
    splitBranch,
  }
}
