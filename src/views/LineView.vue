<script setup lang="ts">
import { computed, ref } from "vue"
import AndonAlert from "../components/AndonAlert.vue"
import AppModal from "../components/AppModal.vue"
import FlowConnectors from "../components/FlowConnectors.vue"
import StepName from "../components/StepName.vue"
import DeviationDialog from "../components/DeviationDialog.vue"
import ErrorToast from "../components/ErrorToast.vue"
import HeldForReleaseZone from "../components/HeldForReleaseZone.vue"
import WorkStationCard from "../components/WorkStationCard.vue"
import { useFlowRunner } from "../composables/useFlowRunner"
import { useLine } from "../composables/useLine"
import { useWorkspaces } from "../composables/useWorkspaces"
import { flowLinks, inflow, isUpstream, laneRows, type ShapeNode } from "../shape"
import type { HelpOffer, WorkStation } from "../types"

const {
  line,
  error,
  loading,
  load,
  renameStep,
  pull,
  finish,
  deploy,
  release,
  raiseRework,
  repairRework,
  assign,
  helpTheRework,
  stopHelping,
  raiseAndon,
  closeAndon,
} = useLine()

const { role, canActAs, current } = useWorkspaces()

const stale = computed(
  () => new Set((line.value?.stale ?? []).map((one) => `${one.kind}:${one.id}`)),
)

const staleShare = computed(() => {
  const active = line.value?.activeAssignments ?? 0
  return active === 0 ? 0 : Math.round((stale.value.size / active) * 100)
})

function bottleneckOf(station: string) {
  return line.value?.bottlenecks.find((one) => one.station === station)
}

/** Must match max_name_length in backend/src/bluebin/line.gleam. */
const maxNameLength = 40

const renameError = ref<string | null>(null)

function stepName(position: number) {
  return line.value?.steps.find((step) => step.position === position)?.name ?? `Step ${position}`
}

async function rename(position: number, name: string) {
  renameError.value = null
  try {
    await renameStep(position, name)
  } catch (cause) {
    renameError.value = `The step was not renamed: ${cause instanceof Error ? cause.message : String(cause)}`
    await load()
  }
}

const { pending, actionError, busy, run, recordDeviation } = useFlowRunner()

/** The last pull tried, so its warning can offer Help the Rework instead (F14). */
const pullAt = ref<{ station: string; who?: string } | null>(null)

function pullHere(station: string, who?: string) {
  pullAt.value = { station, who }
  void run((why) => pull(station, who, why))
}

const helpOffers = computed<HelpOffer[]>(() => {
  const at = pullAt.value
  if (!at || !pending.value?.confirm.split(" ").includes("pull_with_an_open_rework")) return []
  const who = at.who
  return (line.value?.stations ?? []).flatMap((madeBy) =>
    madeBy.rework
      .filter((item) => item.foundById === at.station)
      .map((item) => ({
        rework: item.id,
        label: item.assignee
          ? `Help ${item.assignee} on ${item.piece}`
          : `Help the Rework on ${item.piece}`,
        blocked: !item.assignee
          ? `Nobody of ${madeBy.name} repairs it yet: help once someone takes it.`
          : !who
            ? "Pick who takes the Piece in “Taken by”: that Team Member helps."
            : item.canHelp.some((one) => one.id === who) && canActAs(who)
              ? null
              : "This Team Member cannot help it now: they repair it, or already help another Piece.",
      })),
  )
})

function helpInstead(rework: string) {
  const who = pullAt.value?.who
  pending.value = null
  if (who) void run(() => helpTheRework(rework, who))
}

const raising = ref<{ station: WorkStation; piece: string; reference: string } | null>(null)
const madeBy = ref("")
const defect = ref("")

function openRework(station: WorkStation, piece: string) {
  raising.value = {
    station,
    piece,
    reference: station.inProgress.find((one) => one.id === piece)?.piece ?? piece,
  }
  const [only, ...others] = madeByChoices.value
  madeBy.value = only && others.length === 0 ? only.id : ""
  defect.value = ""
}

const madeByChoices = computed(() => {
  const found = raising.value?.station
  if (!found) {
    return []
  }
  return (line.value?.stations ?? []).filter((one) => isUpstream(nodes.value, one.id, found.id))
})

async function recordRework() {
  const asked = raising.value
  if (!asked || madeBy.value === "" || defect.value.trim() === "") {
    return
  }
  raising.value = null
  await run(() => raiseRework(asked.station.id, asked.piece, madeBy.value, defect.value.trim()))
}

const lastPosition = computed(() =>
  (line.value?.stations ?? []).reduce((last, station) => Math.max(last, station.position), 0),
)

const activePieces = computed(() => {
  const active = new Map<string, { piece: string; station: string; position: number }>()
  for (const station of line.value?.stations ?? []) {
    for (const item of station.inProgress) {
      if (item.teamMemberId && !item.paused) {
        active.set(item.teamMemberId, {
          piece: item.piece,
          station: station.id,
          position: station.position,
        })
      }
    }
  }
  return active
})

const lineEl = ref<HTMLElement | null>(null)

const nodes = computed<ShapeNode[]>(() =>
  (line.value?.stations ?? []).map((station) => ({
    id: station.id,
    position: station.position,
    branch: station.branch,
    parentBranch: null,
  })),
)

const links = computed(() => flowLinks(nodes.value))

const grid = computed(() =>
  laneRows(
    nodes.value,
    columns.value.map((one) => one.position),
  ),
)

/** The grid row of a Work Station: 1 is the step names, then one row per lane. */
function rowOf(station: WorkStation) {
  const lanes = grid.value.lanes.get(station.position) ?? []
  return 2 + Math.max(0, lanes.indexOf(station.branch))
}

function assembles(station: WorkStation) {
  const node = nodes.value.find((one) => one.id === station.id)
  return node !== undefined && inflow(nodes.value, node)?.kind === "assembly"
}

const kanbansByColumn = computed(() =>
  Object.fromEntries(columns.value.map((column, index) => [index, column.kanbans])),
)

/** One column for each step, with a gap column between two steps for the arrows. */
const gridColumns = computed(() => {
  const steps = columns.value.map(() => "minmax(15rem, 1fr)").join(" 6rem ")
  return line.value?.heldForRelease.length ? `${steps} 3rem auto` : steps
})

const columns = computed<{ position: number; stations: WorkStation[]; kanbans: number }[]>(() => {
  const byPosition = new Map<number, WorkStation[]>()
  for (const station of line.value?.stations ?? []) {
    const column = byPosition.get(station.position) ?? []
    column.push(station)
    byPosition.set(station.position, column)
  }
  return [...byPosition.entries()]
    .sort(([a], [b]) => a - b)
    .map(([position, stations]) => ({
      position,
      stations,
      // A step's Kanbans are signals it already sent upstream, so they label
      // the link coming into it.
      kanbans: stations.reduce((total, station) => total + station.kanbans, 0),
    }))
})

const taktLabel = computed(() => {
  const hours = line.value?.taktTimeHours ?? 0
  return hours >= 7 ? `${Math.round((hours / 7) * 10) / 10} working days` : `${hours} h`
})
</script>

<template>
  <section>
    <header class="mb-6 flex flex-wrap items-end justify-between gap-x-10 gap-y-4">
      <div>
        <h2 class="text-xl font-semibold">Line</h2>
        <p class="text-sm opacity-70">Pieces flow to the right. Kanbans flow back to the left.</p>
      </div>
      <dl v-if="line" class="flex flex-wrap gap-x-8 gap-y-3">
        <div>
          <dt class="text-xs font-semibold uppercase tracking-wide opacity-70">Takt Time</dt>
          <dd class="text-2xl font-semibold tabular-nums">
            {{ taktLabel }} <span class="text-sm font-normal opacity-70">per Piece</span>
          </dd>
        </div>
        <div>
          <dt class="text-xs font-semibold uppercase tracking-wide opacity-70">Andons</dt>
          <dd class="flex items-center gap-2 text-2xl font-semibold tabular-nums">
            <span
              v-if="line.andons.length > 0"
              class="size-2.5 rounded-full bg-andon"
              aria-hidden="true"
            />
            {{ line.andons.length }}
          </dd>
        </div>
        <div>
          <dt class="text-xs font-semibold uppercase tracking-wide opacity-70">
            Demands behind Takt
          </dt>
          <dd class="flex items-center gap-2 text-2xl font-semibold tabular-nums">
            <span
              v-if="line.demandsBehind > 0"
              class="size-2.5 rounded-full bg-andon"
              aria-hidden="true"
            />
            {{ line.demandsBehind }}
          </dd>
        </div>
        <div
          v-if="line.activeAssignments > 0"
          title="Active Assignments with no event for more than one working day. Target: 5 % or less."
        >
          <dt class="text-xs font-semibold uppercase tracking-wide opacity-70">
            Stale Assignments
          </dt>
          <dd
            class="text-2xl font-semibold tabular-nums"
            :class="staleShare > 5 ? 'text-warning-ink' : ''"
          >
            {{ staleShare }} %
            <span class="text-sm font-normal opacity-70">
              {{ stale.size }} of {{ line.activeAssignments }}, target 5 %
            </span>
          </dd>
        </div>
      </dl>
    </header>

    <AndonAlert v-if="line" :andons="line.andons" />

    <ErrorToast v-model="renameError" tone="error" />
    <ErrorToast v-model="actionError" />

    <!-- Only the first load shows the spinner: a reload after an action keeps the
         line on screen, so the page keeps its scroll position. -->
    <p v-if="loading && !line" class="flex items-center gap-3 opacity-70">
      <span class="loading loading-spinner loading-sm" />
      Loading the Line…
    </p>

    <div v-else-if="error" class="alert alert-error">
      <span>The API did not answer: {{ error }}</span>
    </div>

    <p v-else-if="columns.length === 0" class="opacity-70">No Work Station yet.</p>

    <div v-else class="overflow-x-auto pb-4">
      <div
        ref="lineEl"
        class="relative grid min-w-max gap-x-4 gap-y-3"
        :style="{
          gridTemplateColumns: gridColumns,
          gridTemplateRows: `auto repeat(${grid.rows}, auto) auto`,
        }"
      >
        <template v-for="(column, index) in columns" :key="column.position">
          <StepName
            :style="{ gridColumn: index * 2 + 1, gridRow: 1 }"
            :name="stepName(column.position)"
            :max-length="maxNameLength"
            :readonly="role !== 'owner'"
            @rename="(name) => rename(column.position, name)"
          />
          <div
            v-for="station in column.stations"
            :key="station.id"
            class="self-start"
            :style="{ gridColumn: index * 2 + 1, gridRow: rowOf(station) }"
            :data-station="station.id"
            :data-column="index"
          >
            <WorkStationCard
              :station="station"
              :active-pieces="activePieces"
              :last="station.position === lastPosition"
              :assembly="assembles(station)"
              :busy="busy"
              :andons="line?.andons ?? []"
              :stale="stale"
              :bottleneck="bottleneckOf(station.id)"
              :takt-hours="line?.taktTimeHours ?? 0"
              :can-act-as="canActAs"
              :own-team-member="current?.teamMember"
              @andon="(who) => run(() => raiseAndon(station.id, who))"
              @close-andon="(who) => run(() => closeAndon(station.id, who))"
              @pull="(who) => pullHere(station.id, who)"
              @finish="(piece) => run((why) => finish(station.id, piece, why))"
              @deploy="(piece, hold) => run(() => deploy(piece, hold))"
              @rework="(piece) => openRework(station, piece)"
              @repair="(rework) => run(() => repairRework(rework))"
              @assign="(kind, id, teamMember) => run(() => assign(kind, id, teamMember))"
              @help="(rework, who) => run(() => helpTheRework(rework, who))"
              @stop-helping="(who) => run(() => stopHelping(who))"
            />
          </div>
          <p
            v-if="column.stations.length > 1"
            class="text-xs italic opacity-70"
            :style="{ gridColumn: index * 2 + 1, gridRow: grid.rows + 2 }"
          >
            {{ column.stations.length }} Branches in parallel
          </p>
        </template>
        <HeldForReleaseZone
          v-if="line?.heldForRelease.length"
          :style="{ gridColumn: columns.length * 2 + 1, gridRow: '1 / -1' }"
          :held="line.heldForRelease"
          :busy="busy"
          :can-release="canActAs()"
          @release="(pieces) => run(() => release(pieces))"
        />
        <FlowConnectors :container="lineEl" :links="links" :kanbans="kanbansByColumn" />
      </div>
    </div>

    <AppModal v-if="raising" @close="raising = null">
      <h3 class="text-lg font-semibold">A defect in {{ raising.reference }}</h3>
      <p class="py-2 text-sm opacity-80">
        The Piece stays here: name the Work Station that made the defect, and one of its Team
        Members comes to repair it.
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
    </AppModal>

    <DeviationDialog
      v-if="pending"
      :message="pending.message"
      :busy="busy"
      :helps="helpOffers"
      @confirm="recordDeviation"
      @help="helpInstead"
      @cancel="pending = null"
    />
  </section>
</template>
