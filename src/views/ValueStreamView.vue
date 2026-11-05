<script setup lang="ts">
import { computed, ref } from "vue"
import FlowConnectors from "../components/FlowConnectors.vue"
import StepName from "../components/StepName.vue"
import DeviationDialog from "../components/DeviationDialog.vue"
import WorkStationCard from "../components/WorkStationCard.vue"
import { useFlowRunner } from "../composables/useFlowRunner"
import { useValueStream } from "../composables/useValueStream"
import type { WorkStation } from "../types"

const {
  valueStream,
  error,
  loading,
  load,
  renameStep,
  pull,
  finish,
  deliver,
  raiseRework,
  repairRework,
  assign,
} = useValueStream()

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

const { pending, actionError, busy, run, recordDeviation } = useFlowRunner()

// --- Jidoka: raise a Rework on the Piece in hand (F12, F13) ---

/** The Piece a Work Station found a defect in, waiting for the defect to be
 *  named and described. */
const raising = ref<{ station: WorkStation; piece: string; reference: string } | null>(null)
const madeBy = ref("")
const defect = ref("")

function openRework(station: WorkStation, piece: string) {
  raising.value = {
    station,
    piece,
    reference: station.inProgress.find((one) => one.id === piece)?.piece ?? piece,
  }
  madeBy.value = ""
  defect.value = ""
}

/** The Work Stations the Piece already crossed: an earlier position, in the
 *  trunk or in the same Branch. A Piece never moves backward. */
const madeByChoices = computed(() => {
  const found = raising.value?.station
  if (!found) {
    return []
  }
  return (valueStream.value?.stations ?? []).filter(
    (one) =>
      one.position < found.position &&
      (one.branch === null || found.branch === null || one.branch === found.branch),
  )
})

async function recordRework() {
  const asked = raising.value
  if (!asked || madeBy.value === "" || defect.value.trim() === "") {
    return
  }
  raising.value = null
  await run(() => raiseRework(asked.station.id, asked.piece, madeBy.value, defect.value.trim()))
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
                @pull="(who) => run((why) => pull(station.id, who, why))"
                @finish="(piece) => run((why) => finish(station.id, piece, why))"
                @deliver="(piece) => run(() => deliver(piece))"
                @rework="(piece) => openRework(station, piece)"
                @repair="(rework) => run(() => repairRework(rework))"
                @assign="(kind, id, person) => run(() => assign(kind, id, person))"
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

    <dialog v-if="raising" class="modal modal-open">
      <div class="modal-box">
        <h3 class="text-lg font-semibold">A defect in {{ raising.reference }}</h3>
        <p class="py-2 text-sm opacity-80">
          The Piece stays here: name the Work Station that made the defect, and one of its People
          comes to repair it.
        </p>
        <label class="form-control">
          <span class="label-text text-sm">Made by</span>
          <select v-model="madeBy" class="select select-bordered mt-1 w-full">
            <option value="" disabled>Pick a Work Station</option>
            <option v-for="one in madeByChoices" :key="one.id" :value="one.id">
              {{ one.name }}
            </option>
          </select>
        </label>
        <label class="form-control mt-2">
          <span class="label-text text-sm">What is wrong? One line.</span>
          <input
            v-model="defect"
            class="input input-bordered mt-1 w-full"
            maxlength="120"
            placeholder="Sync retries lose the last edit"
            @keyup.enter="recordRework"
          />
        </label>
        <div class="modal-action">
          <button class="btn btn-ghost" @click="raising = null">Cancel</button>
          <button
            class="btn btn-error"
            :disabled="busy || madeBy === '' || defect.trim() === ''"
            @click="recordRework"
          >
            Raise the Rework
          </button>
        </div>
      </div>
    </dialog>

    <DeviationDialog
      v-if="pending"
      :message="pending.message"
      :busy="busy"
      @confirm="recordDeviation"
      @cancel="pending = null"
    />
  </section>
</template>
