<script setup lang="ts">
import { computed, onBeforeUnmount, onMounted, ref } from "vue"
import App from "../App.vue"
import BrandMark from "./BrandMark.vue"
import { host, join, mySeat, pick, seats, teamMembers } from "../simulation/share"
import { invitation, playAlone } from "../simulation/state"

/** After this, a Guest still looking for its Host likely holds an old link. */
const patienceMs = 20000

const joinError = ref<string | null>(null)
const pickError = ref<string | null>(null)
const picking = ref<string | null>(null)
const waitedLong = ref(false)
let patience: ReturnType<typeof setTimeout> | undefined

const playing = computed(() => host.value === "here" && mySeat.value !== null)

onMounted(async () => {
  patience = setTimeout(() => (waitedLong.value = true), patienceMs)
  try {
    await join(invitation ?? "")
  } catch (cause) {
    joinError.value = cause instanceof Error ? cause.message : String(cause)
  }
})
onBeforeUnmount(() => clearTimeout(patience))

async function choose(teamMember: string) {
  picking.value = teamMember
  pickError.value = null
  try {
    await pick(teamMember)
  } catch (cause) {
    pickError.value = cause instanceof Error ? cause.message : String(cause)
  } finally {
    picking.value = null
  }
}
</script>

<template>
  <App v-if="playing" />
  <div v-else class="grid min-h-screen place-items-center bg-base-200 px-6 py-10">
    <section class="card w-full max-w-lg bg-base-100 shadow-sm">
      <div class="card-body gap-4">
        <div class="flex items-center gap-3">
          <BrandMark />
          <h1 class="text-xl font-semibold">Join a shared Simulation</h1>
        </div>

        <template v-if="joinError">
          <p role="alert" class="alert alert-error">{{ joinError }}</p>
        </template>

        <template v-else-if="host === 'gone'">
          <p>
            The host closed the Simulation, so it ended for every Guest. Ask the host for a new
            link, or play one alone.
          </p>
        </template>

        <template v-else-if="host === 'looking'">
          <p class="flex items-center gap-3" role="status">
            <span class="loading loading-spinner loading-sm" aria-hidden="true" />
            Looking for the host of this Simulation…
          </p>
          <p v-if="waitedLong" class="text-sm opacity-80">
            No host answers yet. A link works only while its host keeps the Simulation open. Some
            company networks also block the direct connection between two browsers.
          </p>
        </template>

        <template v-else>
          <p>
            Pick the Team Member you play. The host plays the owner of the Line and each Team Member
            that no Guest picks.
          </p>
          <ul class="grid gap-2">
            <li v-for="one in teamMembers" :key="one.id">
              <button
                type="button"
                class="btn btn-block justify-between"
                :disabled="one.id in seats || picking !== null"
                @click="choose(one.id)"
              >
                <span>{{ one.name || "Unnamed Team Member" }}</span>
                <span v-if="one.id in seats" class="text-sm opacity-70">Another Guest</span>
                <span
                  v-else-if="picking === one.id"
                  class="loading loading-spinner loading-xs"
                  aria-hidden="true"
                />
              </button>
            </li>
          </ul>
          <p v-if="teamMembers.length === 0" class="text-sm opacity-80">
            The Line has no Team Member yet. The host adds them in Design.
          </p>
          <p v-if="pickError" role="alert" class="alert alert-error">{{ pickError }}</p>
        </template>

        <div class="card-actions justify-end">
          <button type="button" class="btn btn-ghost btn-sm" @click="playAlone">
            Play a Simulation alone
          </button>
        </div>
      </div>
    </section>
  </div>
</template>
