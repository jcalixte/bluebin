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

/** One heading per screen, so the Guest reads at once where they stand. */
const heading = computed(() => {
  if (joinError.value) return "This link did not open"
  if (host.value === "ended") return "The host ended this Simulation"
  if (host.value === "gone") return "The host is no longer here"
  if (host.value === "looking") return "Looking for the host…"
  return "Pick the Team Member you play"
})

/** Without a host, playing alone is the way on; while a host is here, it is a side exit. */
const stranded = computed(() => joinError.value !== null || host.value === "ended")

function lookAgain() {
  location.reload()
}

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
  <main v-else class="grid min-h-screen place-items-center bg-base-200 px-4 py-10 sm:px-6">
    <section class="card w-full max-w-lg bg-base-100 shadow-sm" aria-labelledby="guest-heading">
      <div class="card-body gap-4">
        <p class="flex items-center gap-2 text-sm font-medium opacity-80">
          <BrandMark />
          Bluebin · shared Simulation
        </p>
        <h1 id="guest-heading" class="text-2xl leading-tight font-semibold">{{ heading }}</h1>

        <template v-if="joinError">
          <p role="alert" class="alert alert-error">{{ joinError }}</p>
        </template>

        <template v-else-if="host === 'ended'">
          <p>The shared Simulation is over for every Guest. Ask the host for a new link.</p>
        </template>

        <template v-else-if="host === 'gone'">
          <p>
            The host closed the Simulation, or the connection dropped. Look again for the host, or
            ask the host for a new link.
          </p>
        </template>

        <template v-else-if="host === 'looking'">
          <p class="flex items-center gap-3" role="status">
            <span class="loading loading-spinner loading-sm" aria-hidden="true" />
            The host must keep the Simulation open in their page.
          </p>
          <p v-if="waitedLong" class="text-sm opacity-80">
            No host answers yet. A link works only while its host keeps the Simulation open. Some
            company networks also block the direct connection between two browsers.
          </p>
        </template>

        <template v-else>
          <p>
            The host plays the owner of the Line and each Team Member that no Guest picks. You can
            change later.
          </p>
          <ul class="grid gap-2">
            <li v-for="one in teamMembers" :key="one.id">
              <button
                type="button"
                class="btn btn-block h-auto min-h-12 justify-between py-2 text-left"
                :disabled="one.id in seats || picking !== null"
                @click="choose(one.id)"
              >
                <span class="grid gap-0.5">
                  <span>{{ one.name || "Unnamed Team Member" }}</span>
                  <span v-if="one.stations.length" class="text-sm font-normal opacity-70">{{
                    one.stations.join(", ")
                  }}</span>
                  <span v-if="one.leads.length" class="text-sm font-normal">
                    Team Leader of {{ one.leads.join(", ") }}
                  </span>
                </span>
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

        <div class="card-actions mt-2 justify-end">
          <button
            type="button"
            class="btn"
            :class="stranded ? 'btn-primary' : 'btn-ghost'"
            @click="playAlone"
          >
            Play a Simulation alone
          </button>
          <button v-if="host === 'gone'" type="button" class="btn btn-primary" @click="lookAgain">
            Look again
          </button>
        </div>
      </div>
    </section>
  </main>
</template>
