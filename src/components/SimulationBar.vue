<script setup lang="ts">
import { computed, onBeforeUnmount, onMounted, ref } from "vue"
import { lineFetch } from "../api"
import AppModal from "./AppModal.vue"
import {
  endSharing,
  guests,
  invite,
  inviteLink,
  pick,
  seats,
  takenFromHost,
  teamMembers as seated,
} from "../simulation/share"
import { seatOf } from "../simulation/seats"
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

/** The Host learns why it plays the owner again. */
const takenName = computed(() => {
  if (takenFromHost.value === null) return null
  return seated.value.find((one) => one.id === takenFromHost.value)?.name || "Unnamed Team Member"
})

/** Host: the Team Members Guests play, and how many Guests still pick one. */
const roster = computed(() =>
  seated.value
    .filter((one) => one.id in seats.value)
    .map((one) => ({ id: one.id, name: one.name || "Unnamed Team Member" })),
)
const stillPicking = computed(
  () => guests.value.filter((peer) => seatOf(seats.value, peer) === null).length,
)

const inviting = ref(false)
const inviteError = ref<string | null>(null)
const copied = ref(false)
const copyFailed = ref(false)
const confirmingEnd = ref(false)

async function openInvite() {
  inviting.value = true
  confirmingEnd.value = false
  inviteError.value = null
  copied.value = false
  copyFailed.value = false
  try {
    await invite()
  } catch (cause) {
    inviteError.value = cause instanceof Error ? cause.message : String(cause)
  }
}

async function copyLink() {
  if (!inviteLink.value) return
  try {
    await navigator.clipboard.writeText(inviteLink.value)
    copied.value = true
    copyFailed.value = false
  } catch {
    copyFailed.value = true
  }
}

async function endForAll() {
  confirmingEnd.value = false
  inviting.value = false
  copied.value = false
  takenFromHost.value = null
  await endSharing()
}

const changeError = ref<string | null>(null)

async function pickAgain() {
  changeError.value = null
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
        title="Pick another Team Member"
        @click="pickAgain"
      >
        Change
      </button>
      <span v-if="changeError" role="alert" class="text-sm">{{ changeError }}</span>
    </template>
    <template v-else>
      <label class="flex items-center gap-2 text-sm">
        <span>Play as</span>
        <select
          v-model="actingAs"
          class="select select-sm w-auto min-w-44 text-base-content"
          @change="takenFromHost = null"
        >
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
      <span v-if="takenName" role="status" class="text-sm">
        A Guest took {{ takenName }}: you play the owner.
      </span>
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
      <h3 class="text-lg font-semibold">Invite Guests</h3>
      <p class="py-2 text-sm opacity-80">
        Send this link. Each Guest opens it and picks one Team Member. You stay the owner of the
        Line and play each Team Member that no Guest picks.
      </p>

      <p v-if="inviteError" role="alert" class="alert alert-error">{{ inviteError }}</p>
      <p v-else-if="!inviteLink" class="flex items-center gap-2 py-3 text-sm" role="status">
        <span class="loading loading-spinner loading-xs" aria-hidden="true" />
        Opening the room…
      </p>
      <template v-else>
        <div class="grid gap-2 pt-2">
          <label class="text-sm font-medium" for="simulation-link">Link to join</label>
          <div class="join w-full">
            <input
              id="simulation-link"
              :value="inviteLink"
              readonly
              class="input join-item w-full font-mono text-xs"
              @focus="($event.target as HTMLInputElement).select()"
            />
            <button type="button" class="btn btn-primary join-item" @click="copyLink">
              {{ copied ? "Copied" : "Copy" }}
            </button>
          </div>
          <p v-if="copyFailed" role="alert" class="text-sm">
            This browser did not copy the link. Select it and copy it yourself.
          </p>
        </div>

        <section class="mt-5" aria-labelledby="simulation-room">
          <h4 id="simulation-room" class="text-sm font-medium">In the room</h4>
          <ul class="mt-2 divide-y divide-base-300 rounded-box border border-base-300 text-sm">
            <li class="flex items-baseline justify-between gap-3 px-3 py-2">
              <span>You</span>
              <span class="text-right opacity-70"
                >The owner, and each Team Member no Guest plays</span
              >
            </li>
            <li
              v-for="one in roster"
              :key="one.id"
              class="flex items-baseline justify-between gap-3 px-3 py-2"
            >
              <span>A Guest</span>
              <span class="text-right">{{ one.name }}</span>
            </li>
            <li v-if="stillPicking" class="flex items-center gap-2 px-3 py-2" role="status">
              <span class="loading loading-dots loading-xs" aria-hidden="true" />
              {{
                stillPicking === 1
                  ? "1 Guest picks a Team Member"
                  : `${stillPicking} Guests pick a Team Member`
              }}
            </li>
          </ul>
          <p v-if="guests.length === 0" class="pt-2 text-sm opacity-80">
            No Guest yet. Each Guest shows here when they open the link.
          </p>
        </section>
      </template>

      <p class="pt-4 text-sm opacity-80">
        The Line lives in this page: when you close or reload it, the Simulation ends for every
        Guest. The browsers connect directly; some company networks block this.
      </p>

      <div v-if="confirmingEnd" class="mt-4 rounded-box bg-base-200 p-4" role="group">
        <p class="text-sm">
          Every Guest leaves the Simulation, and this link stops working. Your Line stays in this
          page.
        </p>
        <div class="mt-3 flex flex-wrap justify-end gap-2">
          <button type="button" class="btn btn-ghost" @click="confirmingEnd = false">
            Keep playing
          </button>
          <button type="button" class="btn btn-primary" @click="endForAll">
            End it for every Guest
          </button>
        </div>
      </div>
      <div v-else class="modal-action justify-between">
        <button v-if="inviteLink" type="button" class="btn btn-ghost" @click="confirmingEnd = true">
          End for every Guest…
        </button>
        <button type="button" class="btn ml-auto" @click="inviting = false">Close</button>
      </div>
    </AppModal>
  </div>
</template>
