<script setup lang="ts">
import { computed, onBeforeUnmount, onMounted, ref } from "vue"
import { lineFetch } from "../api"
import AppModal from "./AppModal.vue"
import { guests, invite, inviteLink, pick, seats, teamMembers as seated } from "../simulation/share"
import { actingAs, guest, onSimulatedChange } from "../simulation/state"
import type { TeamMember } from "../types"

defineEmits<{ restart: [] }>()

const teamMembers = ref<TeamMember[]>([])

async function load() {
  if (guest) return
  const response = await lineFetch("/api/team-members")
  if (!response.ok) return
  teamMembers.value = (await response.json()) as TeamMember[]
  // A Team Member removed in Design can no longer be played.
  if (actingAs.value !== "" && !teamMembers.value.some((one) => one.id === actingAs.value)) {
    actingAs.value = ""
  }
}

let stop = () => {}
onMounted(() => {
  void load()
  stop = onSimulatedChange(() => void load())
})
onBeforeUnmount(() => stop())

const myName = computed(
  () => seated.value.find((one) => one.id === actingAs.value)?.name || "Unnamed Team Member",
)

const inviting = ref(false)
const inviteError = ref<string | null>(null)
const copied = ref(false)

async function openInvite() {
  inviting.value = true
  inviteError.value = null
  try {
    await invite()
  } catch (cause) {
    inviteError.value = cause instanceof Error ? cause.message : String(cause)
  }
}

async function copyLink() {
  if (!inviteLink.value) return
  await navigator.clipboard.writeText(inviteLink.value)
  copied.value = true
}

const changeError = ref<string | null>(null)

async function pickAgain() {
  try {
    await pick("")
  } catch (cause) {
    changeError.value = cause instanceof Error ? cause.message : String(cause)
  }
}
</script>

<template>
  <div class="flex flex-wrap items-center gap-2">
    <span class="badge badge-neutral">Simulation</span>
    <template v-if="guest">
      <span class="text-sm">You play {{ myName }}</span>
      <button
        type="button"
        class="btn btn-sm btn-ghost [--btn-rest-fg:var(--color-primary-content)]"
        :title="changeError ?? 'Pick another Team Member'"
        @click="pickAgain"
      >
        Change
      </button>
    </template>
    <template v-else>
      <label class="flex items-center gap-2 text-sm">
        <span>Play as</span>
        <select v-model="actingAs" class="select select-sm w-auto min-w-44 text-base-content">
          <option value="">The owner of the Line</option>
          <option
            v-for="one in teamMembers"
            :key="one.id"
            :value="one.id"
            :disabled="one.id in seats"
          >
            {{ one.name || "Unnamed Team Member" }}{{ one.id in seats ? " (another Guest)" : "" }}
          </option>
        </select>
      </label>
      <button
        type="button"
        class="btn btn-sm btn-ghost [--btn-rest-fg:var(--color-primary-content)]"
        title="Play this Line with other people"
        @click="openInvite"
      >
        Invite…<span v-if="guests.length" class="badge badge-sm">{{ guests.length }}</span>
      </button>
      <button
        type="button"
        class="btn btn-sm btn-ghost [--btn-rest-fg:var(--color-primary-content)]"
        title="Load the demo data again, or start empty"
        @click="$emit('restart')"
      >
        Restart…
      </button>
    </template>

    <AppModal v-if="inviting" @close="inviting = false">
      <h3 class="text-lg font-semibold">Play this Simulation together</h3>
      <p class="py-2 text-sm opacity-80">
        Send this link. Each Guest picks one Team Member. You stay the owner of the Line and play
        each Team Member that no Guest picks.
      </p>
      <p v-if="inviteError" role="alert" class="alert alert-error">{{ inviteError }}</p>
      <div v-else-if="inviteLink" class="join w-full">
        <input
          :value="inviteLink"
          readonly
          aria-label="Link to join this Simulation"
          class="input join-item w-full"
          @focus="($event.target as HTMLInputElement).select()"
        />
        <button type="button" class="btn btn-primary join-item" @click="copyLink">
          {{ copied ? "Copied" : "Copy" }}
        </button>
      </div>
      <p v-else class="flex items-center gap-2 text-sm" role="status">
        <span class="loading loading-spinner loading-xs" aria-hidden="true" />
        Opening the room…
      </p>
      <p class="pt-3 text-sm opacity-80">
        {{ guests.length === 1 ? "1 Guest is here." : `${guests.length} Guests are here.` }}
        The Line lives in this page: when you close or reload it, the Simulation ends for every
        Guest. The browsers connect directly; some company networks block this.
      </p>
      <div class="modal-action">
        <button type="button" class="btn btn-ghost" @click="inviting = false">Close</button>
      </div>
    </AppModal>
  </div>
</template>
