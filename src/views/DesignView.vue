<script setup lang="ts">
import DesignPeopleCard from "../components/DesignPeopleCard.vue"
import DesignStationCard from "../components/DesignStationCard.vue"
import ErrorToast from "../components/ErrorToast.vue"
import WorkingCalendarCard from "../components/WorkingCalendarCard.vue"
import { isBranchStep, maxNameLength, useDesign, type DraftStep } from "../composables/useDesign"
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
  addPerson,
  removePerson,
  addStepAfter,
  removeStep,
  canMove,
  moveStep,
  canSplit,
  splitStep,
  removeStation,
} = useDesign()

const { calendar, calendarError, saveCalendar } = useWorkingCalendar()

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
          Change the steps, Work Stations, People and labels. Nothing changes until you save.
        </p>
      </div>
      <div v-if="draft" class="flex flex-wrap items-center gap-3">
        <span v-if="dirty" class="badge badge-outline" role="status">Changes not saved</span>
        <span v-else class="text-sm opacity-70" role="status">All changes are saved</span>
        <button
          type="button"
          class="btn btn-ghost btn-sm"
          :disabled="!dirty || saving"
          @click="confirmDiscard"
        >
          Discard
        </button>
        <button
          type="button"
          class="btn btn-primary btn-sm"
          :disabled="!dirty || saving"
          @click="save"
        >
          <span v-if="saving" class="loading loading-spinner loading-xs" />
          Save changes
        </button>
      </div>
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

    <div v-else class="flex flex-col gap-6">
      <div
        v-if="dirty && problems.length > 0"
        class="rounded-r-box border-l-4 border-warning bg-warning/10 px-4 py-3 text-sm"
        role="status"
      >
        <p class="font-semibold">Before you save</p>
        <ul class="mt-1 list-disc pl-5">
          <li v-for="problem in problems" :key="problem">{{ problem }}</li>
        </ul>
      </div>

      <div class="overflow-x-auto pb-4">
        <ol class="flex flex-col gap-6 lg:min-w-max lg:flex-row lg:gap-4">
          <li
            v-for="(step, index) in draft.steps"
            :key="step.key"
            class="flex flex-col gap-3 lg:w-80 lg:shrink-0"
          >
            <div class="flex items-center gap-2">
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
              class="flex flex-wrap items-center gap-1"
              role="group"
              :aria-label="`Step ${index + 1} actions`"
            >
              <button
                type="button"
                class="btn btn-ghost btn-xs"
                :disabled="!canMove(index, -1)"
                :title="moveTitle(index, -1)"
                :aria-label="`Move ${step.name || 'this step'} to the left`"
                @click="moveStep(index, -1)"
              >
                ←
              </button>
              <button
                type="button"
                class="btn btn-ghost btn-xs"
                :disabled="!canMove(index, 1)"
                :title="moveTitle(index, 1)"
                :aria-label="`Move ${step.name || 'this step'} to the right`"
                @click="moveStep(index, 1)"
              >
                →
              </button>
              <button
                type="button"
                class="btn btn-ghost btn-xs"
                :disabled="!canSplit(step)"
                :title="
                  canSplit(step) ? undefined : 'A Work Station with work in it keeps its Branch'
                "
                @click="splitStep(index)"
              >
                {{ splitLabel(step) }}
              </button>
              <button
                type="button"
                class="btn btn-ghost btn-xs"
                title="Add a step with one new Work Station after this step"
                @click="addStepAfter(index)"
              >
                Add a step after
              </button>
              <button
                v-if="step.stations.length === 0"
                type="button"
                class="btn btn-ghost btn-xs"
                @click="removeStep(index)"
              >
                Remove step
              </button>
            </div>

            <p v-if="index === 0" class="text-xs opacity-70">Pulls from the Backlog.</p>

            <DesignStationCard
              v-for="(station, stationIndex) in step.stations"
              :key="station.key"
              v-model="step.stations[stationIndex]"
              :people="draft.people"
              @remove="removeStation(index, stationIndex)"
            />

            <p v-if="step.stations.length === 0" class="text-sm opacity-70">
              No Work Station. Add one or remove this step.
            </p>
            <p v-else-if="step.stations.length > 1" class="text-xs italic opacity-70">
              {{ step.stations.length }} Branches in parallel
            </p>
          </li>
        </ol>
      </div>

      <div class="grid gap-6 xl:grid-cols-3">
        <DesignPeopleCard v-model="draft.people" :add="addPerson" @remove="removePerson" />

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
  </section>
</template>
