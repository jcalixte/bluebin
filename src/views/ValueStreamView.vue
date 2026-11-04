<script setup lang="ts">
import { computed, ref } from "vue"
import FlowConnectors from "../components/FlowConnectors.vue"
import StepName from "../components/StepName.vue"
import WorkStationCard from "../components/WorkStationCard.vue"
import { useValueStream } from "../composables/useValueStream"
import type { FlowConfirm, WorkStation } from "../types"

const { valueStream, error, loading, load, renameStep, pull, finish, deliver } = useValueStream()

/** The longest step name the API accepts; kept in step with the backend. */
const maxNameLength = 40

const renameError = ref<string | null>(null)

function stepName(position: number) {
  return (
    valueStream.value?.steps.find((step) => step.position === position)?.name ?? `Step ${position}`
  )
}

async function rename(position: number, name: string) {
  renameError.value = null
  try {
    await renameStep(position, name)
  } catch (cause) {
    renameError.value = cause instanceof Error ? cause.message : String(cause)
    await load()
  }
}

// --- Pull, finish, deliver, and the Deviation a broken rule needs (F6, F9) ---

/** One action waiting for the Person to confirm it and say why. */
type Pending = { message: string; again: (reason: string) => Promise<FlowConfirm | null> }

const pending = ref<Pending | null>(null)
const reason = ref("")
const actionError = ref<string | null>(null)
const busy = ref(false)

/** Runs one action; a warned rule opens the Deviation dialog instead. */
async function run(action: (reason?: string) => Promise<FlowConfirm | null>) {
  actionError.value = null
  busy.value = true
  try {
    const confirm = await action()
    if (confirm) {
      reason.value = ""
      pending.value = { message: confirm.message, again: (why) => action(why) }
    }
  } catch (cause) {
    actionError.value = cause instanceof Error ? cause.message : String(cause)
  } finally {
    busy.value = false
  }
}

async function recordDeviation() {
  const why = reason.value.trim()
  if (!pending.value || why === "") {
    return
  }
  const action = pending.value.again
  pending.value = null
  await run(() => action(why))
}

/** The last step of the chain: production pulls out of its Blue Bins. */
const lastPosition = computed(() =>
  (valueStream.value?.stations ?? []).reduce(
    (last, station) => Math.max(last, station.position),
    0,
  ),
)

/** The element the connectors measure the cards against. */
const streamEl = ref<HTMLElement | null>(null)

/** One column per position in the chain; a Split shows as several Work
 *  Stations stacked in the same column, one per Branch. */
const columns = computed<{ position: number; stations: WorkStation[]; kanbans: number }[]>(() => {
  const byPosition = new Map<number, WorkStation[]>()
  for (const station of valueStream.value?.stations ?? []) {
    const column = byPosition.get(station.position) ?? []
    column.push(station)
    byPosition.set(station.position, column)
  }
  return [...byPosition.entries()]
    .sort(([a], [b]) => a - b)
    .map(([position, stations]) => ({
      position,
      stations,
      // The Kanbans this step holds are the signals it has already sent back
      // upstream, so they belong to the link coming into it.
      kanbans: stations.reduce((total, station) => total + station.kanbans, 0),
    }))
})

const taktLabel = computed(() => {
  const hours = valueStream.value?.taktTimeHours ?? 0
  return hours >= 7 ? `${Math.round((hours / 7) * 10) / 10} working days` : `${hours} h`
})
</script>

<template>
  <section>
    <header class="mb-6 flex flex-wrap items-end justify-between gap-4">
      <div>
        <h2 class="text-xl font-semibold">Value Stream</h2>
        <p class="text-sm opacity-70">
          Takt Time {{ taktLabel }} per Piece, across every active Demand
        </p>
      </div>
      <button class="btn btn-sm" :disabled="loading" @click="load">Refresh</button>
    </header>

    <div v-if="renameError" role="alert" class="alert alert-error mb-4">
      <span>The step was not renamed: {{ renameError }}</span>
    </div>

    <div v-if="actionError" role="alert" class="alert alert-warning mb-4">
      <span>{{ actionError }}</span>
    </div>

    <!-- Only the first load shows the spinner: a reload after an action keeps the
         stream on screen, so the page keeps its scroll position. -->
    <p v-if="loading && !valueStream" class="flex items-center gap-3 opacity-70">
      <span class="loading loading-spinner loading-sm" />
      Loading the Value Stream…
    </p>

    <div v-else-if="error" class="alert alert-error">
      <span>The API did not answer: {{ error }}</span>
    </div>

    <p v-else-if="columns.length === 0" class="opacity-70">No Work Station yet.</p>

    <div v-else class="overflow-x-auto pb-4">
      <div ref="streamEl" class="relative flex min-w-max gap-4">
        <template v-for="(column, index) in columns" :key="column.position">
          <div v-if="index > 0" class="w-24 shrink-0" />
          <div class="flex min-w-[15rem] flex-1 flex-col gap-3">
            <StepName
              :name="stepName(column.position)"
              :max-length="maxNameLength"
              @rename="(name) => rename(column.position, name)"
            />
            <div
              v-for="station in column.stations"
              :key="station.id"
              :data-column="index"
              :data-branch="station.branch ?? ''"
            >
              <WorkStationCard
                :station="station"
                :last="station.position === lastPosition"
                :assembly="
                  station.branch === null && (columns[index - 1]?.stations.length ?? 0) > 1
                "
                :busy="busy"
                @pull="run((why) => pull(station.id, why))"
                @finish="(piece) => run((why) => finish(station.id, piece, why))"
                @deliver="(piece) => run(() => deliver(piece))"
              />
            </div>
            <p v-if="column.stations.length > 1" class="text-xs italic opacity-50">
              {{ column.stations.length }} Branches in parallel
            </p>
          </div>
        </template>
        <FlowConnectors :container="streamEl" :columns="columns" />
      </div>
    </div>

    <dialog v-if="pending" class="modal modal-open">
      <div class="modal-box">
        <h3 class="text-lg font-semibold">This breaks a pull rule</h3>
        <p class="py-2 text-sm opacity-80">{{ pending.message }}</p>
        <label class="form-control">
          <span class="label-text text-sm">Why do you go on? One line, seen by everyone.</span>
          <input
            v-model="reason"
            class="input input-bordered mt-1 w-full"
            maxlength="120"
            placeholder="The Client called: this one ships today"
            @keyup.enter="recordDeviation"
          />
        </label>
        <div class="modal-action">
          <button class="btn btn-ghost" @click="pending = null">Cancel</button>
          <button
            class="btn btn-warning"
            :disabled="busy || reason.trim() === ''"
            @click="recordDeviation"
          >
            Record the Deviation
          </button>
        </div>
      </div>
    </dialog>
  </section>
</template>
