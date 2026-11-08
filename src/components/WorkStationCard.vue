<script setup lang="ts">
import { computed, ref, watch } from "vue"
import type { Andon, Bottleneck, WorkStation } from "../types"

const props = defineProps<{
  station: WorkStation
  /** The Piece each Team Member transforms now, by Team Member id. */
  activePieces: Map<string, { piece: string; station: string; position: number }>
  last?: boolean
  busy?: boolean
  /** The Work Station after the Branches pulls by Assembly. */
  assembly?: boolean
  andons: Andon[]
  /** Keys `piece:<id>` and `rework:<id>` of the stale Assignments. */
  stale: Set<string>
  bottleneck?: Bottleneck
  taktHours: number
  /** Whether who looks may act as this Team Member, or at all with none (`access.actor`). */
  canActAs: (teamMember?: string) => boolean
  /** The signed-in Account's own Team Member in this Line, if any. */
  ownTeamMember?: string | null
}>()

const emit = defineEmits<{
  pull: [teamMember: string | undefined]
  finish: [piece: string]
  deploy: [piece: string, hold: boolean]
  rework: [piece: string]
  repair: [rework: string]
  assign: [kind: "piece" | "rework", id: string, teamMember: string]
  andon: [teamMember: string | undefined]
  closeAndon: [teamMember: string]
}>()

/**
 * Who takes a pulled Piece by default: the signed-in Account's own Team Member when it works at
 * this Work Station, else the only Team Member of a Work Station of one.
 */
const defaultTeamMember = computed(() => {
  const own = props.ownTeamMember
  if (own && props.station.teamMembers.some((one) => one.id === own) && props.canActAs(own)) {
    return own
  }
  const [only, ...others] = props.station.teamMembers
  return only && others.length === 0 && props.canActAs(only.id) ? only.id : ""
})

const teamMember = ref(defaultTeamMember.value)
watch(defaultTeamMember, (id) => {
  teamMember.value = id
})

/**
 * Whether who looks acts as one of this Work Station's Team Members: only then may they pull a
 * Piece or hand one over here.
 */
const actsHere = computed(() => props.station.teamMembers.some((one) => props.canActAs(one.id)))

function handOver(kind: "piece" | "rework", id: string, event: Event) {
  const teamMember = (event.target as HTMLSelectElement).value
  if (teamMember !== "") {
    emit("assign", kind, id, teamMember)
  }
}

/** Finishing beats starting: a Piece nearer to Deployment keeps the Team Member's hands. */
const keptFirst = computed(() => {
  const active = props.activePieces.get(teamMember.value)
  if (!active || active.position < props.station.position) return null
  const name = props.station.teamMembers.find((one) => one.id === teamMember.value)?.name
  return active.station === props.station.id
    ? `${name} already has ${active.piece} in hand here: the new Piece starts paused`
    : `${name} finishes ${active.piece} first, at another Work Station: the new Piece starts paused`
})

const hasRework = computed(() => props.station.rework.length > 0)

const stop = computed(() => {
  const found = props.andons.find((one) => one.kind === "stop" && one.station === props.station.id)
  return found?.kind === "stop" ? found : null
})

function reworkWaits(rework: string) {
  const found = props.andons.find((one) => one.kind === "rework_waits" && one.rework === rework)
  return found?.kind === "rework_waits" ? found.waitingHours : null
}

const oneDecimal = (value: number) => Math.round(value * 10) / 10

const bottleneck = computed(() => {
  const found = props.bottleneck
  if (!found) return null
  const slow =
    found.slower && found.capacityHours !== null
      ? {
          pieceHours: oneDecimal(found.capacityHours),
          taktHours: oneDecimal(props.taktHours),
          times: props.taktHours > 0 ? oneDecimal(found.capacityHours / props.taktHours) : null,
        }
      : null
  if (!slow && !found.fullInFront) return null
  return { slow, fullInFront: found.fullInFront }
})

function raisedAt(at: string) {
  return new Date(at).toLocaleTimeString(undefined, { hour: "2-digit", minute: "2-digit" })
}

const binsFilled = computed(() => props.station.blueBins.filter((bin) => bin.piece !== null).length)

const binsFull = computed(
  () => props.station.blueBins.length > 0 && binsFilled.value === props.station.blueBins.length,
)

const yieldPercent = computed(() =>
  props.station.firstPassYield === null ? null : Math.round(props.station.firstPassYield * 100),
)

const reworkHours = computed(() => Math.round(props.station.reworkHours * 10) / 10)
</script>

<template>
  <article
    class="card overflow-hidden border bg-base-100 shadow-sm"
    :class="stop || hasRework ? 'border-2 border-error' : 'border-base-300'"
  >
    <div
      v-if="stop"
      role="alert"
      class="flex flex-col gap-1 bg-error px-4 py-3 text-sm text-error-content"
    >
      <p class="flex items-center gap-2 font-semibold">
        <span
          class="size-2.5 rounded-full bg-current motion-safe:animate-pulse"
          aria-hidden="true"
        />
        Andon: stopped at {{ raisedAt(stop.raisedAt) }}
        <template v-if="stop.raisedBy"> by {{ stop.raisedBy }}</template>
      </p>
      <p v-if="stop.teamLeader">
        Team Leader {{ stop.teamLeader }} is called. A pull is a Deviation until the Andon is
        closed.
      </p>
      <button
        v-if="stop.teamLeaderId && canActAs(stop.teamLeaderId)"
        class="btn btn-xs mt-1 self-start"
        :disabled="busy"
        @click="$emit('closeAndon', stop.teamLeaderId)"
      >
        {{ stop.teamLeader }} closes the Andon
      </button>
    </div>

    <div class="card-body gap-4 p-4">
      <header class="flex items-start justify-between gap-2">
        <div class="min-w-0">
          <h3 class="text-base font-semibold leading-tight">{{ station.name }}</h3>
          <p v-if="station.teamLeader" class="mt-0.5 text-xs opacity-70">
            Team Leader {{ station.teamLeader }}
          </p>
        </div>
        <button
          v-if="!stop && canActAs()"
          class="btn btn-ghost btn-xs shrink-0 gap-1.5"
          :disabled="busy"
          title="Stop this Work Station and call its Team Leader"
          @click="$emit('andon', teamMember === '' ? undefined : teamMember)"
        >
          <span class="size-2 rounded-full bg-andon" aria-hidden="true" />
          Andon
        </button>
      </header>

      <section
        v-if="bottleneck"
        aria-label="Bottleneck"
        class="rounded-r-box border-l-4 border-warning bg-warning/10 px-3 py-2 text-xs"
      >
        <p class="flex items-baseline justify-between gap-2">
          <span class="text-sm font-semibold">Bottleneck</span>
          <span
            v-if="bottleneck.slow?.times"
            class="font-medium tabular-nums opacity-70"
            title="Touch Time per Piece divided by the Takt Time"
          >
            {{ bottleneck.slow.times }} × Takt Time
          </span>
        </p>
        <p v-if="bottleneck.slow" class="mt-1 opacity-80">
          Each Piece takes
          <strong class="font-semibold tabular-nums">{{ bottleneck.slow.pieceHours }} h</strong>
          here. The Takt Time is
          <strong class="font-semibold tabular-nums">{{ bottleneck.slow.taktHours }} h</strong>.
        </p>
        <p v-if="bottleneck.fullInFront" class="mt-1 opacity-80">
          The Blue Bins in front of it are full.
        </p>
      </section>

      <p v-if="!actsHere" class="text-sm opacity-70">
        {{ station.kanbans }} Kanban {{ station.kanbans === 1 ? "authorizes" : "authorize" }} a pull
      </p>
      <section v-else aria-label="Pull">
        <div class="tooltip tooltip-warning block">
          <div v-if="keptFirst" :id="`kept-first-${station.id}`" class="tooltip-content text-xs">
            {{ keptFirst }}
          </div>
          <button
            class="btn btn-sm btn-primary w-full justify-between"
            :disabled="busy"
            :aria-describedby="keptFirst ? `kept-first-${station.id}` : undefined"
            @click="$emit('pull', teamMember === '' ? undefined : teamMember)"
          >
            {{ assembly ? "Assemble a Piece" : "Pull a Piece" }}
            <span
              class="rounded-full bg-primary-content/10 px-2 py-0.5 text-xs font-medium tabular-nums"
              :title="
                station.kanbans > 0
                  ? `${station.kanbans} Kanban ${station.kanbans === 1 ? 'authorizes' : 'authorize'} a pull`
                  : 'No Kanban: a pull is a Deviation'
              "
            >
              {{ station.kanbans }} Kanban
            </span>
          </button>
        </div>
        <label class="mt-1.5 flex items-center gap-2 text-xs">
          <span class="opacity-70">Taken by</span>
          <select
            v-model="teamMember"
            class="select select-ghost select-xs w-auto"
            title="The Team Member who takes the Piece in hand. Also names who raises an Andon."
          >
            <option value="">Nobody</option>
            <option
              v-for="one in station.teamMembers"
              :key="one.id"
              :value="one.id"
              :disabled="!canActAs(one.id)"
            >
              {{ one.name }}
            </option>
          </select>
        </label>
      </section>

      <section v-if="hasRework" aria-label="Rework">
        <h4 class="flex items-center gap-2 text-xs font-semibold uppercase tracking-wide">
          <span class="size-2 rounded-full bg-andon" aria-hidden="true" />
          Rework
        </h4>
        <ul class="mt-2 space-y-2">
          <li
            v-for="item in station.rework"
            :key="item.id"
            class="rounded-r-box border-l-4 border-error bg-error/5 px-3 py-2 text-sm"
          >
            <div class="flex items-start justify-between gap-2">
              <p>
                <span class="font-medium">{{ item.piece }}</span>
                <span class="opacity-80"> — {{ item.description }}</span>
              </p>
              <button
                v-if="canActAs()"
                class="btn btn-xs shrink-0"
                :disabled="busy"
                @click="$emit('repair', item.id)"
              >
                Repaired
              </button>
            </div>
            <div class="mt-1 flex flex-wrap items-center gap-x-2 gap-y-1 text-xs">
              <span class="opacity-70">Found by {{ item.foundBy }}</span>
              <select
                v-if="actsHere"
                class="select select-ghost select-xs w-auto"
                :value="item.assigneeId ?? ''"
                :disabled="busy"
                aria-label="Who repairs it"
                title="Who repairs it: pick another Team Member to hand it over"
                @change="handOver('rework', item.id, $event)"
              >
                <option value="" disabled>nobody repairs it</option>
                <option
                  v-for="one in station.teamMembers"
                  :key="one.id"
                  :value="one.id"
                  :disabled="!canActAs(one.id)"
                >
                  {{ one.name }} repairs
                </option>
              </select>
              <span v-else class="opacity-70">
                {{ item.assignee ? `${item.assignee} repairs` : "nobody repairs it" }}
              </span>
              <span
                v-if="stale.has(`rework:${item.id}`)"
                class="badge badge-xs badge-warning"
                title="No event for more than one working day: is it still in repair?"
              >
                stale
              </span>
              <span
                v-if="reworkWaits(item.id) !== null"
                class="badge badge-xs badge-error"
                title="A Rework that waits with no active Assignment raises an Andon after 1 h of Working Time"
              >
                Andon · waits {{ reworkWaits(item.id) }} h
              </span>
            </div>
          </li>
        </ul>
      </section>

      <section aria-label="In the hands of">
        <h4 class="text-xs font-semibold uppercase tracking-wide opacity-70">In the hands of</h4>
        <p v-if="station.inProgress.length === 0" class="mt-1 text-sm opacity-70">
          No Piece in hand
        </p>
        <ul v-else class="mt-1 divide-y divide-base-300">
          <li
            v-for="item in station.inProgress"
            :key="item.id"
            class="flex flex-wrap items-center gap-x-2 gap-y-1 py-1.5 text-sm"
          >
            <span class="font-medium" :class="item.paused ? 'italic opacity-70' : ''">
              {{ item.piece }}
            </span>
            <select
              v-if="actsHere"
              class="select select-ghost select-xs w-auto"
              :value="item.teamMemberId ?? ''"
              :disabled="busy"
              aria-label="Who holds this Piece"
              title="Who holds this Piece: pick another Team Member to hand it over"
              @change="handOver('piece', item.id, $event)"
            >
              <option value="" disabled>unassigned</option>
              <option
                v-for="one in station.teamMembers"
                :key="one.id"
                :value="one.id"
                :disabled="!canActAs(one.id)"
              >
                {{ one.name }}
              </option>
            </select>
            <span v-else class="opacity-70">{{ item.teamMember ?? "unassigned" }}</span>
            <span
              v-if="item.paused"
              class="badge badge-xs badge-warning"
              title="Paused: its Team Member finishes a Rework or a Piece nearer to Deployment first"
            >
              paused
            </span>
            <span
              v-if="stale.has(`piece:${item.id}`)"
              class="badge badge-xs badge-warning"
              title="No event for more than one working day: is it still in hand?"
            >
              stale
            </span>
            <span v-if="canActAs()" class="ml-auto flex gap-1">
              <button
                class="btn btn-ghost btn-xs"
                :disabled="busy || item.paused"
                title="Raise a Rework: name the Work Station that made the defect"
                @click="$emit('rework', item.id)"
              >
                Rework
              </button>
              <button
                class="btn btn-xs"
                :disabled="busy || item.paused"
                @click="$emit('finish', item.id)"
              >
                Finish
              </button>
            </span>
          </li>
        </ul>
      </section>

      <section aria-label="Blue Bins">
        <h4
          class="flex items-baseline justify-between text-xs font-semibold uppercase tracking-wide"
        >
          <span class="opacity-70">Blue Bins</span>
          <span
            class="tabular-nums"
            :class="binsFull ? 'text-warning-ink' : 'opacity-70'"
            :title="`${binsFilled} of ${station.blueBins.length} Blue Bins hold a Piece`"
          >
            {{ binsFilled }}/{{ station.blueBins.length }}
          </span>
        </h4>
        <ul class="mt-2 grid grid-cols-[repeat(auto-fill,minmax(4rem,1fr))] gap-1.5">
          <li
            v-for="bin in station.blueBins"
            :key="bin.slot"
            class="flex min-h-14 flex-col justify-end gap-1 rounded-b-lg border-2 border-t-0 px-1.5 pb-1.5 pt-3 text-xs"
            :class="
              bin.piece
                ? 'border-primary bg-primary text-primary-content'
                : 'border-dashed border-base-content/50'
            "
            :title="bin.piece ? (bin.demand ?? bin.piece) : 'Empty Blue Bin'"
          >
            <template v-if="bin.piece">
              <span class="truncate font-medium">{{ bin.piece }}</span>
              <span v-if="bin.pulledBy" class="truncate text-[0.6875rem] opacity-80">
                {{ bin.pulledBy }} pulled
              </span>
              <template v-if="last && bin.id && canActAs()">
                <button
                  class="btn btn-xs"
                  :disabled="busy"
                  title="Deploy and release it to the Client now"
                  @click="$emit('deploy', bin.id, false)"
                >
                  Deploy
                </button>
                <button
                  class="btn btn-ghost btn-xs text-primary-content"
                  :disabled="busy"
                  title="Deploy it, and hold its Release for later"
                  @click="$emit('deploy', bin.id, true)"
                >
                  Deploy, hold
                </button>
              </template>
            </template>
            <span v-else class="sr-only">Empty Blue Bin</span>
          </li>
          <li
            v-for="extra in station.overflow"
            :key="extra.id"
            class="flex min-h-14 flex-col justify-end gap-1 rounded-b-lg border-2 border-t-0 border-warning bg-warning px-1.5 pb-1.5 pt-3 text-xs text-warning-content"
            :title="`${extra.demand}: over the Blue Bin count, put there by a Deviation`"
          >
            <span class="truncate font-medium">{{ extra.piece }}</span>
            <span class="text-[0.6875rem]">over the count</span>
            <template v-if="last && canActAs()">
              <button
                class="btn btn-xs"
                :disabled="busy"
                title="Deploy and release it to the Client now"
                @click="$emit('deploy', extra.id, false)"
              >
                Deploy
              </button>
              <button
                class="btn btn-ghost btn-xs text-warning-content"
                :disabled="busy"
                title="Deploy it, and hold its Release for later"
                @click="$emit('deploy', extra.id, true)"
              >
                Deploy, hold
              </button>
            </template>
          </li>
        </ul>
        <p v-if="binsFull" class="mt-1.5 text-xs font-medium text-warning-ink">
          Every Blue Bin is full
        </p>
      </section>

      <footer class="flex flex-col gap-2 border-t border-base-300 pt-3">
        <ul class="flex flex-wrap gap-1" aria-label="Team Members">
          <li
            v-for="one in station.teamMembers"
            :key="one.id"
            class="badge badge-sm badge-outline gap-1.5"
            :title="
              one.busy ? `${one.name} has a Piece or a Rework in hand` : `${one.name} is free`
            "
          >
            <span
              class="size-1.5 rounded-full"
              :class="one.busy ? 'bg-primary' : 'bg-base-content/40'"
              aria-hidden="true"
            />
            {{ one.name }}
            <span class="sr-only">{{ one.busy ? "busy" : "free" }}</span>
          </li>
        </ul>
        <p class="text-xs" title="First Pass Yield and Rework Time of this Work Station">
          <span v-if="yieldPercent === null" class="opacity-70">No Piece has left yet</span>
          <span v-else :class="yieldPercent < 90 ? 'font-medium text-warning-ink' : 'opacity-70'">
            First Pass Yield {{ yieldPercent }} %
          </span>
          <span v-if="reworkHours > 0" class="opacity-70"> · {{ reworkHours }} h of Rework</span>
        </p>
        <details v-if="station.deviations.length > 0" class="text-xs">
          <summary class="cursor-pointer font-medium text-warning-ink">
            {{ station.deviations.length }}
            {{ station.deviations.length === 1 ? "Deviation" : "Deviations" }}
          </summary>
          <ul class="mt-1 space-y-1 opacity-80">
            <li v-for="(item, index) in station.deviations" :key="index">
              <span class="font-medium">{{ item.piece ?? "—" }}</span>
              — {{ item.reason }}
            </li>
          </ul>
        </details>
      </footer>
    </div>
  </article>
</template>
