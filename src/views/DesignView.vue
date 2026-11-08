<script setup lang="ts">
import { nextTick, ref } from "vue"
import AddStepSlot from "../components/AddStepSlot.vue"
import DesignTeamMembersCard from "../components/DesignTeamMembersCard.vue"
import DesignStationCard from "../components/DesignStationCard.vue"
import ErrorToast from "../components/ErrorToast.vue"
import WorkingCalendarCard from "../components/WorkingCalendarCard.vue"
import { isBranchStep, maxNameLength, useDesign, type DraftStep } from "../composables/useDesign"
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
  removeStep,
  canMove,
  moveStep,
  canSplit,
  splitStep,
  removeStation,
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

function splitLabel(step: DraftStep) {
  if (step.stations.length === 0) return "Add a Work Station"
  return isBranchStep(step) ? "Add a Branch" : "Split into Branches"
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

/** Keys of the steps and Work Stations just added: they show where they arrive. */
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

/** The list of things to fix opens from the save bar, so it never pushes the Line down. */
const showProblems = ref(false)

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
          <div class="flex flex-col items-center lg:min-w-max lg:flex-row lg:items-start">
            <div
              class="flex h-10 shrink-0 items-center rounded-box border border-dashed border-base-content/30 px-4 text-xs font-semibold uppercase tracking-wide opacity-70"
            >
              Backlog
            </div>

            <TransitionGroup
              tag="ol"
              move-class="transition-transform duration-300 ease-out motion-reduce:transition-none"
              class="flex w-full flex-col items-center lg:w-auto lg:flex-row lg:items-start"
            >
              <li
                v-for="(step, index) in draft.steps"
                :key="step.key"
                class="flex w-full flex-col items-center lg:w-auto lg:flex-row lg:items-start"
              >
                <AddStepSlot
                  :label="
                    index === 0 ? 'Add a step first' : `Add a step after ${stepName(index - 1)}`
                  "
                  @add="showArrival(addStepAfter(index - 1))"
                />

                <div
                  class="flex w-full max-w-md flex-col gap-3 lg:w-80 lg:shrink-0"
                  :class="arrivalClass(step.key)"
                  :data-design-key="step.key"
                >
                  <div class="flex h-10 items-center gap-3">
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
                      {{ splitLabel(step) }}
                    </button>
                    <button
                      v-if="step.stations.length === 0"
                      type="button"
                      class="btn btn-ghost btn-sm ml-auto"
                      @click="removeStep(index)"
                    >
                      Remove step
                    </button>
                  </div>

                  <DesignStationCard
                    v-for="(station, stationIndex) in step.stations"
                    :key="station.key"
                    v-model="step.stations[stationIndex]"
                    :class="arrivalClass(station.key)"
                    :data-design-key="station.key"
                    :team-members="draft.teamMembers"
                    :takt-hours="draft.taktTimeHours"
                    @remove="removeStation(index, stationIndex)"
                  />

                  <p
                    v-if="step.stations.length === 0"
                    class="rounded-box border border-dashed border-base-content/30 p-4 text-sm opacity-70"
                  >
                    No Work Station. Add one or remove this step.
                  </p>
                  <p v-else-if="step.stations.length > 1" class="text-xs italic opacity-70">
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
