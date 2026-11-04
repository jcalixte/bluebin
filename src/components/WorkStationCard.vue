<script setup lang="ts">
import { computed, ref } from "vue"
import type { WorkStation } from "../types"

const props = defineProps<{
  station: WorkStation
  last?: boolean
  busy?: boolean
  /** The Work Station after the Branches pulls by Assembly. */
  assembly?: boolean
}>()

defineEmits<{
  pull: [person: string | undefined]
  finish: [piece: string]
  deliver: [piece: string]
  rework: [piece: string]
  repair: [rework: string]
}>()

/** The Person who takes the next Piece in hand; none until one is picked. */
const person = ref("")

const hasRework = computed(() => props.station.rework.length > 0)

/** A Work Station with every Blue Bin full holds the flow up: it can finish
 *  nothing more until the downstream Work Station pulls. */
const binsFull = computed(
  () =>
    props.station.blueBins.length > 0 && props.station.blueBins.every((bin) => bin.piece !== null),
)

/** First Pass Yield as a whole percentage, or null until a Piece has left. */
const yieldPercent = computed(() =>
  props.station.firstPassYield === null ? null : Math.round(props.station.firstPassYield * 100),
)

const reworkHours = computed(() => Math.round(props.station.reworkHours * 10) / 10)
</script>

<template>
  <article
    class="card border bg-base-100 shadow-sm"
    :class="hasRework ? 'border-error border-2' : 'border-base-300'"
  >
    <div class="card-body gap-3 p-4">
      <header class="flex items-start justify-between gap-2">
        <div>
          <h3 class="font-semibold leading-tight">{{ station.name }}</h3>
          <p v-if="station.teamLeader" class="text-xs opacity-60">
            Team Leader {{ station.teamLeader }}
          </p>
        </div>
        <span
          class="badge badge-sm shrink-0"
          :class="station.kanbans > 0 ? 'badge-primary' : 'badge-ghost'"
          :title="`${station.kanbans} Kanban(s)`"
        >
          {{ station.kanbans }} Kanban
        </span>
      </header>

      <div class="flex gap-1">
        <button
          class="btn btn-sm btn-primary flex-1"
          :disabled="busy"
          @click="$emit('pull', person === '' ? undefined : person)"
        >
          {{ assembly ? "Assemble a Piece" : "Pull a Piece" }}
        </button>
        <select
          v-model="person"
          class="select select-bordered select-sm w-24"
          title="The Person who takes the Piece in hand"
        >
          <option value="">Nobody</option>
          <option v-for="one in station.people" :key="one.id" :value="one.id">
            {{ one.name }}
          </option>
        </select>
      </div>

      <div>
        <p class="text-xs uppercase tracking-wide opacity-60">Blue Bins</p>
        <ul class="mt-1 flex flex-wrap gap-1">
          <li
            v-for="bin in station.blueBins"
            :key="bin.slot"
            class="flex items-center gap-1 rounded border px-2 py-1 text-xs"
            :class="
              bin.piece
                ? 'border-primary bg-primary text-primary-content'
                : 'border-dashed border-base-300 opacity-60'
            "
            :title="bin.demand ?? 'Empty Blue Bin'"
          >
            {{ bin.piece ?? "empty" }}
            <span v-if="bin.pulledBy" class="opacity-80">· {{ bin.pulledBy }} pulled</span>
            <button
              v-if="last && bin.id"
              class="btn btn-xs"
              :disabled="busy"
              @click="$emit('deliver', bin.id)"
            >
              Deliver
            </button>
          </li>
        </ul>
        <ul v-if="station.overflow.length > 0" class="mt-1 flex flex-wrap gap-1">
          <li
            v-for="extra in station.overflow"
            :key="extra.id"
            class="flex items-center gap-1 rounded border border-warning bg-warning/20 px-2 py-1 text-xs"
            :title="`${extra.demand} — over the Blue Bin count, put there by a Deviation`"
          >
            {{ extra.piece }} · over the count
            <button
              v-if="last"
              class="btn btn-xs"
              :disabled="busy"
              @click="$emit('deliver', extra.id)"
            >
              Deliver
            </button>
          </li>
        </ul>
        <p v-if="binsFull" class="mt-1 text-xs font-medium text-warning">Every Blue Bin is full</p>
      </div>

      <div v-if="station.inProgress.length > 0">
        <p class="text-xs uppercase tracking-wide opacity-60">In the hands of</p>
        <ul class="mt-1 space-y-1 text-sm">
          <li v-for="item in station.inProgress" :key="item.id" class="flex items-center gap-2">
            <span class="font-medium" :class="item.paused ? 'opacity-50 line-through' : ''">
              {{ item.piece }}
            </span>
            <span class="opacity-60">· {{ item.person ?? "unassigned" }}</span>
            <span
              v-if="item.paused"
              class="badge badge-xs badge-warning"
              title="Paused: its Person repairs a Rework first"
            >
              paused
            </span>
            <span class="ml-auto flex gap-1">
              <button
                class="btn btn-xs"
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
      </div>

      <div v-if="hasRework" class="rounded bg-error/10 p-2">
        <p class="text-xs font-semibold uppercase tracking-wide text-error">Rework</p>
        <ul class="mt-1 space-y-1 text-sm">
          <li v-for="item in station.rework" :key="item.id" class="flex items-start gap-2">
            <span>
              <span class="font-medium">{{ item.piece }}</span>
              <span class="opacity-70"> — {{ item.description }}</span>
              <span class="block text-xs opacity-60">
                found by {{ item.foundBy }} ·
                {{ item.assignee ? `${item.assignee} repairs` : "nobody repairs it yet" }}
              </span>
            </span>
            <button class="btn btn-xs ml-auto" :disabled="busy" @click="$emit('repair', item.id)">
              Repaired
            </button>
          </li>
        </ul>
      </div>

      <div v-if="station.deviations.length > 0">
        <p class="text-xs uppercase tracking-wide text-warning">Deviations</p>
        <ul class="mt-1 space-y-1 text-xs opacity-70">
          <li v-for="(item, index) in station.deviations" :key="index">
            <span class="font-medium">{{ item.piece ?? "—" }}</span>
            — {{ item.reason }}
          </li>
        </ul>
      </div>

      <p class="text-xs opacity-60" title="First Pass Yield and Rework Time of this Work Station">
        <span v-if="yieldPercent === null">No Piece has left yet</span>
        <span v-else :class="yieldPercent < 90 ? 'font-medium text-warning' : ''">
          First Pass Yield {{ yieldPercent }} %
        </span>
        <span v-if="reworkHours > 0"> · {{ reworkHours }} h of Rework</span>
      </p>

      <footer class="flex flex-wrap gap-1">
        <span
          v-for="one in station.people"
          :key="one.id"
          class="badge badge-sm badge-outline gap-1"
        >
          <span
            class="inline-block size-1.5 rounded-full"
            :class="one.busy ? 'bg-primary' : 'bg-base-content/30'"
          />
          {{ one.name }}
        </span>
      </footer>
    </div>
  </article>
</template>
