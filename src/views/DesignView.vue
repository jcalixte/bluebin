<script setup lang="ts">
import { computed, nextTick, ref } from "vue"
import AddStepSlot from "../components/AddStepSlot.vue"
import FlowConnectors from "../components/FlowConnectors.vue"
import DesignTeamMembersCard from "../components/DesignTeamMembersCard.vue"
import DesignStationCard from "../components/DesignStationCard.vue"
import ErrorToast from "../components/ErrorToast.vue"
import WorkingCalendarCard from "../components/WorkingCalendarCard.vue"
import {
  draftLanes,
  draftNodes,
  isBranchStep,
  maxNameLength,
  useDesign,
  type DraftStation,
  type DraftStep,
} from "../composables/useDesign"
import { flowLinks } from "../shape"
import { useAccount } from "../composables/useAccount"
import { useWorkingCalendar } from "../composables/useWorkingCalendar"
import type { Labels } from "../types"

const {
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
  canRemoveStep,
  removeStep,
  canMove,
  moveStep,
  canSplit,
  splitStep,
  removeStation,
  addStationAt,
  canSplitBranch,
  splitBranch,
} = useDesign()

const { calendar, calendarError, saveCalendar } = useWorkingCalendar()
const { account } = useAccount()

const labelFields: { key: keyof Labels; label: string; example: string }[] = [
  { key: "demand", label: "One Demand", example: "Feature" },
  { key: "demands", label: "More than one Demand", example: "Features" },
  { key: "piece", label: "One Piece", example: "User Story" },
  { key: "pieces", label: "More than one Piece", example: "User Stories" },
]

function role(index: number) {
  const steps = draft.value?.steps ?? []
  const step = steps[index]
  const previous = steps[index - 1]
  if (!step || !previous) return null
  if (isBranchStep(step) && !isBranchStep(previous)) {
    return { name: "Split", title: "Here a Piece divides into Sub-Pieces, one for each Branch." }
  }
  if (!isBranchStep(step) && isBranchStep(previous)) {
    return { name: "Assembly", title: "Here the Sub-Pieces of a Piece come together again." }
  }
  return null
}

function splitLabel(step: DraftStep, index: number) {
  if (isBranchStep(step) || inSplit(index)) return "Add a Branch"
  return step.stations.length === 0 ? "Add a Work Station" : "Split into Branches"
}

const lineEl = ref<HTMLElement | null>(null)

const grid = computed(() => draftLanes(draft.value?.steps ?? []))

const links = computed(() => flowLinks(draftNodes(draft.value?.steps ?? [])))

/** Rows of a step column: name, actions, one per lane, extra, footer. */
const rowCount = computed(() => grid.value.rows + 4)

function inSplit(index: number) {
  return (grid.value.lanes[index] ?? []).some((lane) => lane !== null)
}

function laneOf(station: DraftStation) {
  return station.branch === null ? null : station.branch.trim()
}

/** The grid row of a Work Station; a second one with the same Branch goes to the extra row. */
function stationRow(step: DraftStep, index: number, station: DraftStation) {
  const lanes = grid.value.lanes[index] ?? []
  const lane = laneOf(station)
  const first = step.stations.find((one) => laneOf(one) === lane)
  const at = lanes.indexOf(lane)
  return first === station && at >= 0 ? 3 + at : 3 + grid.value.rows
}

/**
 * The lanes of a Split that have no Work Station at this step: an empty cell
 * with a +. An outer Branch gets no + inside its nested Split, and a nested
 * Branch none outside it.
 */
function emptyLanes(step: DraftStep, index: number) {
  const nodes = draftNodes(draft.value?.steps ?? [])
  const span = (keep: (node: (typeof nodes)[number]) => boolean) => {
    const at = nodes.filter(keep).map((node) => node.position - 1)
    return at.length === 0 ? null : { first: Math.min(...at), last: Math.max(...at) }
  }
  return (grid.value.lanes[index] ?? []).flatMap((lane, at) => {
    if (lane === null || step.stations.some((one) => laneOf(one) === lane)) return []
    const nested = span((node) => node.parentBranch === lane)
    if (nested && index >= nested.first && index <= nested.last) return []
    const parent = nodes.find((node) => node.branch === lane)?.parentBranch ?? null
    if (parent !== null) {
      const own = nodes.filter((node) => node.branch === parent).map((node) => node.position - 1)
      const kids = span((node) => node.parentBranch === parent)
      const before = Math.max(-1, ...own.filter((one) => kids === null || one < kids.first))
      const after = Math.min(Infinity, ...own.filter((one) => kids === null || one > kids.last))
      if (index <= before || index >= after) return []
    }
    return [{ lane, row: 3 + at }]
  })
}

const lockedMove = "A Work Station with work in it cannot move past another one"

function moveTitle(index: number, delta: -1 | 1) {
  const other = draft.value?.steps[index + delta]
  if (!other) return delta < 0 ? "This is the first step" : "This is the last step"
  if (!canMove(index, delta)) return lockedMove
  return delta < 0 ? "Move this step to the left" : "Move this step to the right"
}

function stepNumber(index: number) {
  return String(index + 1).padStart(2, "0")
}

function stepName(index: number) {
  return draft.value?.steps[index]?.name.trim() || `step ${index + 1}`
}

const arrived = ref(new Set<string>())
const arrivalMs = 1200

async function showArrival(key: string | null) {
  if (key === null) return
  arrived.value.add(key)
  setTimeout(() => arrived.value.delete(key), arrivalMs)
  await nextTick()
  const element = document.querySelector<HTMLElement>(`[data-design-key="${key}"]`)
  if (!element) return
  const reduce = window.matchMedia("(prefers-reduced-motion: reduce)").matches
  element.scrollIntoView({
    behavior: reduce ? "auto" : "smooth",
    block: "nearest",
    inline: "center",
  })
  const name = element.querySelector<HTMLInputElement>("input[type=text]")
  name?.focus({ preventScroll: true })
  name?.select()
}

function arrivalClass(key: string) {
  return arrived.value.has(key)
    ? "relative motion-safe:animate-arrive after:pointer-events-none after:absolute after:-inset-1.5 after:rounded-box after:border-2 after:border-primary after:opacity-0 after:animate-glow"
    : ""
}

const showProblems = ref(false)

function confirmRemoveStep(index: number) {
  const count = draft.value?.steps[index]?.stations.length ?? 0
  if (
    count === 0 ||
    confirm(`Remove ${stepName(index)} and its ${count} Work Station${count === 1 ? "" : "s"}?`)
  ) {
    removeStep(index)
  }
}

function confirmDiscard() {
  if (confirm("Discard all the changes that are not saved?")) {
    void discard()
  }
}
</script>

<template>
  <section>
    <header class="mb-6 flex flex-wrap items-end justify-between gap-4">
      <div>
        <h2 class="text-xl font-semibold">Design</h2>
        <p class="text-sm opacity-70">
          Draw the Line your work flows through. Nothing changes until you save.
        </p>
      </div>
      <p v-if="draft" class="flex items-center gap-2 text-sm" role="status">
        <span
          class="size-2 rounded-full"
          :class="dirty ? 'bg-warning' : 'bg-base-content/30'"
          aria-hidden="true"
        />
        <span :class="dirty ? 'font-medium' : 'opacity-70'">
          {{ dirty ? "Changes not saved" : "All changes are saved" }}
        </span>
      </p>
    </header>

    <ErrorToast v-model="error" tone="error" />

    <p v-if="loading && !draft" class="flex items-center gap-3 opacity-70">
      <span class="loading loading-spinner loading-sm" />
      Loading the Design…
    </p>

    <div v-else-if="!draft" class="alert alert-error">
      <span>The Design did not load.</span>
      <button type="button" class="btn btn-sm" @click="load">Try again</button>
    </div>

    <div v-else class="flex flex-col gap-10">
      <section aria-labelledby="design-line">
        <div class="mb-4 flex flex-wrap items-baseline justify-between gap-x-6 gap-y-1">
          <h3 id="design-line" class="text-lg font-semibold">The Line</h3>
          <p class="text-sm opacity-70">
            Pieces flow from the Backlog to the right. Use + to add a step.
          </p>
        </div>

        <div class="relative overflow-x-auto p-2 pb-4">
          <div
            ref="lineEl"
            class="relative flex flex-col items-center lg:min-w-max lg:flex-row lg:items-start"
          >
            <div
              class="flex h-10 shrink-0 items-center rounded-box border border-dashed border-base-content/30 px-4 text-xs font-semibold uppercase tracking-wide opacity-70"
            >
              Backlog
            </div>

            <TransitionGroup
              tag="ol"
              move-class="transition-transform duration-300 ease-out motion-reduce:transition-none"
              class="flex w-full flex-col items-center lg:grid lg:w-auto lg:auto-cols-max lg:grid-flow-col lg:items-start lg:gap-y-3"
              :style="{ gridTemplateRows: `repeat(${rowCount}, auto)` }"
            >
              <li
                v-for="(step, index) in draft.steps"
                :key="step.key"
                class="flex w-full flex-col items-center lg:grid lg:w-auto lg:grid-cols-[auto_auto] lg:grid-rows-subgrid lg:items-start"
                :style="{ gridRow: `span ${rowCount}` }"
              >
                <AddStepSlot
                  :style="{ gridRow: 1 }"
                  :label="
                    index === 0 ? 'Add a step first' : `Add a step after ${stepName(index - 1)}`
                  "
                  @add="showArrival(addStepAfter(index - 1))"
                />

                <div
                  class="flex w-full max-w-md flex-col gap-3 lg:grid lg:w-80 lg:shrink-0 lg:grid-rows-subgrid"
                  :class="arrivalClass(step.key)"
                  :style="{ gridRow: '1 / -1' }"
                  :data-design-key="step.key"
                >
                  <div class="flex h-10 items-center gap-3" :style="{ gridRow: 1 }">
                    <span
                      class="font-mono text-3xl leading-none text-primary tabular-nums"
                      aria-hidden="true"
                    >
                      {{ stepNumber(index) }}
                    </span>
                    <label class="min-w-0 flex-1">
                      <span class="sr-only">Name of step {{ index + 1 }}</span>
                      <input
                        v-model="step.name"
                        type="text"
                        class="input input-sm w-full text-xs font-semibold uppercase tracking-wide"
                        :class="step.name.trim() === '' ? 'input-warning' : ''"
                        :maxlength="maxNameLength"
                      />
                    </label>
                    <span
                      v-if="role(index)"
                      class="badge badge-sm badge-ghost shrink-0"
                      tabindex="0"
                      :title="role(index)?.title"
                    >
                      {{ role(index)?.name }}
                    </span>
                  </div>

                  <div
                    class="flex items-center gap-1"
                    :style="{ gridRow: 2 }"
                    role="group"
                    :aria-label="`Actions of ${stepName(index)}`"
                  >
                    <button
                      type="button"
                      class="btn btn-square btn-ghost btn-sm"
                      :disabled="!canMove(index, -1)"
                      :title="moveTitle(index, -1)"
                      :aria-label="`Move ${stepName(index)} to the left`"
                      @click="moveStep(index, -1)"
                    >
                      <svg
                        class="size-4"
                        viewBox="0 0 24 24"
                        fill="none"
                        stroke="currentColor"
                        stroke-width="2"
                        stroke-linecap="round"
                        stroke-linejoin="round"
                        aria-hidden="true"
                      >
                        <path d="M15 6l-6 6l6 6" />
                      </svg>
                    </button>
                    <button
                      type="button"
                      class="btn btn-square btn-ghost btn-sm"
                      :disabled="!canMove(index, 1)"
                      :title="moveTitle(index, 1)"
                      :aria-label="`Move ${stepName(index)} to the right`"
                      @click="moveStep(index, 1)"
                    >
                      <svg
                        class="size-4"
                        viewBox="0 0 24 24"
                        fill="none"
                        stroke="currentColor"
                        stroke-width="2"
                        stroke-linecap="round"
                        stroke-linejoin="round"
                        aria-hidden="true"
                      >
                        <path d="M9 6l6 6l-6 6" />
                      </svg>
                    </button>
                    <button
                      type="button"
                      class="btn btn-ghost btn-sm"
                      :disabled="!canSplit(step)"
                      :title="
                        canSplit(step)
                          ? undefined
                          : 'A Work Station with work in it keeps its Branch'
                      "
                      @click="showArrival(splitStep(index))"
                    >
                      {{ splitLabel(step, index) }}
                    </button>
                    <button
                      type="button"
                      class="btn btn-ghost btn-sm ml-auto"
                      :disabled="!canRemoveStep(index)"
                      :title="
                        canRemoveStep(index)
                          ? undefined
                          : 'You cannot remove a step with a Work Station that has work in it'
                      "
                      @click="confirmRemoveStep(index)"
                    >
                      Remove step
                    </button>
                  </div>

                  <DesignStationCard
                    v-for="(station, stationIndex) in step.stations"
                    :key="station.key"
                    v-model="step.stations[stationIndex]"
                    :class="arrivalClass(station.key)"
                    :style="{ gridRow: stationRow(step, index, station) }"
                    :data-design-key="station.key"
                    :data-station="station.key"
                    :data-column="index"
                    :team-members="draft.teamMembers"
                    :takt-hours="draft.taktTimeHours"
                    :can-split-branch="canSplitBranch(station)"
                    @remove="removeStation(index, stationIndex)"
                    @split-branch="showArrival(splitBranch(index, stationIndex))"
                  />

                  <button
                    v-for="empty in emptyLanes(step, index)"
                    :key="`empty-${empty.lane}`"
                    type="button"
                    class="btn btn-ghost h-auto min-h-16 w-full border border-dashed border-base-content/30 font-normal hover:border-primary hover:text-primary"
                    :style="{ gridRow: empty.row }"
                    :title="`The ${empty.lane} Branch skips this step. Add a Work Station to it here.`"
                    @click="showArrival(addStationAt(index, empty.lane))"
                  >
                    + Work Station in {{ empty.lane }}
                  </button>

                  <p
                    v-if="step.stations.length === 0 && !inSplit(index)"
                    class="rounded-box border border-dashed border-base-content/30 p-4 text-sm opacity-70"
                    :style="{ gridRow: rowCount }"
                  >
                    No Work Station. Add one or remove this step.
                  </p>
                  <p
                    v-else-if="step.stations.length > 1"
                    class="text-xs italic opacity-70"
                    :style="{ gridRow: rowCount }"
                  >
                    {{ step.stations.length }} Branches in parallel
                  </p>
                </div>
              </li>
            </TransitionGroup>

            <AddStepSlot
              :label="
                draft.steps.length === 0
                  ? 'Add a step'
                  : `Add a step after ${stepName(draft.steps.length - 1)}`
              "
              @add="showArrival(addStepAfter(draft.steps.length - 1))"
            />
            <FlowConnectors class="hidden lg:block" :container="lineEl" :links="links" simple />
          </div>
        </div>
      </section>

      <div class="grid items-start gap-6 lg:grid-cols-2">
        <DesignTeamMembersCard
          v-model="draft.teamMembers"
          :add="addTeamMember"
          :can-link="account?.signedIn === true"
          @remove="removeTeamMember"
        />

        <div class="flex flex-col gap-6">
          <div class="card border border-base-300 bg-base-100 shadow-sm">
            <div class="card-body gap-4 p-5">
              <h3 class="card-title text-base">Labels</h3>
              <p class="text-sm opacity-70">
                The names your teams use for a Demand and a Piece. They are saved with the other
                changes.
              </p>
              <div class="grid gap-3 sm:grid-cols-2">
                <label v-for="field in labelFields" :key="field.key" class="flex flex-col gap-1">
                  <span class="text-sm font-medium">{{ field.label }}</span>
                  <input
                    v-model="draft.labels[field.key]"
                    type="text"
                    class="input input-sm w-full"
                    :class="draft.labels[field.key].trim() === '' ? 'input-warning' : ''"
                    :maxlength="maxNameLength"
                    :placeholder="field.example"
                  />
                </label>
              </div>
            </div>
          </div>

          <div v-if="calendarError" class="alert alert-error">
            <span>The Working Calendar did not load: {{ calendarError }}</span>
          </div>
          <WorkingCalendarCard v-else-if="calendar" :calendar="calendar" :save="saveCalendar" />
        </div>
      </div>

      <Transition
        enter-active-class="transition duration-200 ease-out motion-reduce:transition-none"
        enter-from-class="translate-y-4 opacity-0"
        leave-active-class="transition duration-150 ease-in motion-reduce:transition-none"
        leave-to-class="translate-y-4 opacity-0"
      >
        <div
          v-if="dirty"
          class="sticky bottom-4 z-10 rounded-box border border-base-300 bg-base-100 px-4 py-3 shadow-lg"
        >
          <ul
            v-if="showProblems && problems.length > 0"
            id="design-problems"
            class="mb-3 max-h-40 list-disc overflow-y-auto border-b border-base-300 pb-3 pl-5 text-sm"
          >
            <li v-for="(problem, problemIndex) in problems" :key="problemIndex">{{ problem }}</li>
          </ul>
          <div class="flex flex-wrap items-center justify-between gap-3">
            <p class="text-sm">
              <span class="font-semibold">Changes not saved.</span>
              {{ " " }}
              <button
                v-if="problems.length > 0"
                type="button"
                class="inline-flex min-h-6 items-center gap-1 text-warning-ink underline decoration-dotted underline-offset-4 hover:decoration-solid"
                aria-controls="design-problems"
                :aria-expanded="showProblems"
                @click="showProblems = !showProblems"
              >
                {{ problems.length }} {{ problems.length === 1 ? "thing" : "things" }} to fix before
                you save
                <svg
                  class="size-4 transition-transform duration-150 motion-reduce:transition-none"
                  :class="showProblems ? 'rotate-180' : ''"
                  viewBox="0 0 24 24"
                  fill="none"
                  stroke="currentColor"
                  stroke-width="2"
                  stroke-linecap="round"
                  stroke-linejoin="round"
                  aria-hidden="true"
                >
                  <path d="M6 15l6 -6l6 6" />
                </svg>
              </button>
            </p>
            <div class="flex items-center gap-2">
              <button
                type="button"
                class="btn btn-ghost btn-sm"
                :disabled="saving"
                @click="confirmDiscard"
              >
                Discard
              </button>
              <button type="button" class="btn btn-primary btn-sm" :disabled="saving" @click="save">
                <span v-if="saving" class="loading loading-spinner loading-xs" />
                Save changes
              </button>
            </div>
          </div>
        </div>
      </Transition>
    </div>
  </section>
</template>
