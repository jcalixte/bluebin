<script setup lang="ts">
import { computed } from "vue"
import { maxNameLength, type DraftStation } from "../composables/useDesign"
import type { DesignTeamMember } from "../types"

const station = defineModel<DraftStation>({ required: true })

const props = defineProps<{ teamMembers: DesignTeamMember[] }>()

defineEmits<{ remove: [] }>()

const members = computed(() =>
  props.teamMembers.filter((teamMember) => station.value.teamMembers.includes(teamMember.id)),
)

function toggle(teamMember: string, event: Event) {
  const on = (event.target as HTMLInputElement).checked
  const others = station.value.teamMembers.filter((one) => one !== teamMember)
  station.value.teamMembers = on ? [...others, teamMember] : others
  if (!station.value.teamMembers.includes(station.value.teamLeader)) {
    station.value.teamLeader = station.value.teamMembers[0] ?? ""
  }
}

const tooFewBins = computed(() => !(Number(station.value.blueBins) >= station.value.minBlueBins))
</script>

<template>
  <article class="card border border-base-300 bg-base-100 shadow-sm">
    <div class="card-body gap-3 p-4">
      <header class="flex items-start gap-2">
        <label class="min-w-0 flex-1">
          <span class="sr-only">Work Station name</span>
          <input
            v-model="station.name"
            type="text"
            class="input input-sm w-full font-semibold"
            :class="station.name.trim() === '' ? 'input-warning' : ''"
            :maxlength="maxNameLength"
            placeholder="Work Station name"
          />
        </label>
        <span
          v-if="station.locked"
          class="badge badge-sm badge-neutral mt-1.5 shrink-0 gap-1"
          tabindex="0"
          title="This Work Station holds a Piece, an open Rework or an open Andon. You cannot remove it or change its Branch. It cannot move past another locked Work Station."
        >
          <svg
            class="size-3"
            viewBox="0 0 24 24"
            fill="none"
            stroke="currentColor"
            stroke-width="2"
            stroke-linecap="round"
            stroke-linejoin="round"
            aria-hidden="true"
          >
            <path d="M5 13a2 2 0 0 1 2 -2h10a2 2 0 0 1 2 2v6a2 2 0 0 1 -2 2h-10a2 2 0 0 1 -2 -2z" />
            <path d="M8 11v-4a4 4 0 1 1 8 0v4" />
          </svg>
          Locked
        </span>
        <button
          type="button"
          class="btn btn-ghost btn-sm shrink-0"
          :disabled="station.locked"
          :title="
            station.locked
              ? 'You cannot remove a Work Station that has work in it'
              : 'Remove this Work Station'
          "
          :aria-label="`Remove ${station.name || 'this Work Station'}`"
          @click="$emit('remove')"
        >
          Remove
        </button>
      </header>

      <label v-if="station.branch !== null" class="flex flex-col gap-1 text-sm">
        <span class="font-medium">Branch</span>
        <input
          v-model="station.branch"
          type="text"
          class="input input-sm w-full"
          :class="station.branch.trim() === '' ? 'input-warning' : ''"
          :maxlength="maxNameLength"
          :disabled="station.locked"
          :title="station.locked ? 'A Work Station with work in it keeps its Branch' : undefined"
        />
      </label>

      <label class="flex flex-col gap-1 text-sm">
        <span class="font-medium">Blue Bins</span>
        <input
          v-model.number="station.blueBins"
          type="number"
          class="input input-sm w-24 tabular-nums"
          :class="tooFewBins ? 'input-warning' : ''"
          :min="station.minBlueBins"
          step="1"
          required
        />
        <span v-if="station.minBlueBins > 1" class="text-xs opacity-70">
          {{ station.minBlueBins }} or more: Pieces are in the Blue Bins.
        </span>
      </label>

      <fieldset>
        <legend class="mb-1 text-sm font-medium">Team Members</legend>
        <p v-if="teamMembers.length === 0" class="text-sm opacity-70">Add a Team Member first.</p>
        <ul v-else class="flex max-h-40 flex-col gap-1 overflow-y-auto">
          <li v-for="teamMember in teamMembers" :key="teamMember.id">
            <label class="flex items-center gap-2 text-sm">
              <input
                type="checkbox"
                class="checkbox checkbox-sm"
                :checked="station.teamMembers.includes(teamMember.id)"
                @change="toggle(teamMember.id, $event)"
              />
              {{ teamMember.name || "Unnamed Team Member" }}
            </label>
          </li>
        </ul>
      </fieldset>

      <label class="flex flex-col gap-1 text-sm">
        <span class="font-medium">Team Leader</span>
        <select
          v-model="station.teamLeader"
          class="select select-sm w-full"
          :class="!station.teamMembers.includes(station.teamLeader) ? 'select-warning' : ''"
          :disabled="members.length === 0"
        >
          <option value="" disabled>
            {{ members.length === 0 ? "Pick its Team Members first" : "Pick a Team Leader" }}
          </option>
          <option v-for="teamMember in members" :key="teamMember.id" :value="teamMember.id">
            {{ teamMember.name || "Unnamed Team Member" }}
          </option>
        </select>
      </label>
    </div>
  </article>
</template>
