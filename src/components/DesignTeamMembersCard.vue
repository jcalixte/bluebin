<script setup lang="ts">
import { computed, ref } from "vue"
import { maxNameLength } from "../composables/useDesign"
import type { DesignTeamMember } from "../types"

/** Must match max_email_length in backend/src/bluebin/accounts.gleam. */
const maxEmailLength = 254

const teamMembers = defineModel<DesignTeamMember[]>({ required: true })

const props = defineProps<{
  add: (name: string) => Promise<boolean>
  /** Only a signed-in owner links Team Members to Accounts. */
  canLink: boolean
}>()

defineEmits<{ remove: [id: string] }>()

const name = ref("")
const adding = ref(false)

const notLinked = computed(
  () => teamMembers.value.filter((teamMember) => teamMember.account === null).length,
)

async function submit() {
  const trimmed = name.value.trim()
  if (trimmed === "") return
  adding.value = true
  try {
    if (await props.add(trimmed)) {
      name.value = ""
    }
  } finally {
    adding.value = false
  }
}

/** A changed email is linked again only once it is saved. */
function unlink(teamMember: DesignTeamMember) {
  teamMember.account = null
}
</script>

<template>
  <div class="card border border-base-300 bg-base-100 shadow-sm">
    <div class="card-body gap-4 p-5">
      <div class="flex flex-wrap items-center justify-between gap-2">
        <h3 class="card-title text-base">Team Members</h3>
        <span v-if="canLink && notLinked > 0" class="badge badge-outline badge-sm">
          {{ notLinked }} not linked yet
        </span>
      </div>
      <p class="text-sm opacity-70">
        A new Team Member is added now. A changed name or email, or a removed Team Member, is saved
        with the other changes.
      </p>
      <p v-if="canLink" class="text-sm opacity-70">
        Type the email of a Team Member's Account. The link holds from that Account's next sign-in,
        and the Team Member then shows the Account's name.
      </p>

      <p v-if="teamMembers.length === 0" class="text-sm opacity-70">No Team Member yet.</p>
      <ul v-else class="flex flex-col gap-3">
        <li
          v-for="(teamMember, index) in teamMembers"
          :key="teamMember.id"
          class="flex flex-col gap-1"
        >
          <div class="flex gap-2">
            <label class="min-w-0 flex-1">
              <span class="sr-only">Name of Team Member {{ index + 1 }}</span>
              <input
                v-model="teamMember.name"
                type="text"
                class="input input-sm w-full"
                :class="teamMember.name.trim() === '' ? 'input-warning' : ''"
                :maxlength="teamMember.account ? undefined : maxNameLength"
                :disabled="teamMember.account !== null"
                :title="teamMember.account ? 'The name comes from the linked Account' : undefined"
              />
            </label>
            <button
              type="button"
              class="btn btn-ghost btn-sm shrink-0"
              title="Remove this Team Member from the Line and from each Work Station"
              :aria-label="`Remove ${teamMember.name || `Team Member ${index + 1}`}`"
              @click="$emit('remove', teamMember.id)"
            >
              Remove
            </button>
          </div>
          <div v-if="canLink" class="flex items-center gap-2">
            <label class="min-w-0 flex-1">
              <span class="sr-only">Email of the Account of {{ teamMember.name }}</span>
              <input
                v-model="teamMember.email"
                type="email"
                class="input input-sm w-full"
                autocomplete="off"
                :maxlength="maxEmailLength"
                placeholder="Email of their Account"
                @input="unlink(teamMember)"
              />
            </label>
            <span
              class="badge badge-sm shrink-0"
              :class="teamMember.account ? 'badge-ghost' : 'badge-outline'"
            >
              {{ teamMember.account ? "Linked" : "Not linked yet" }}
            </span>
          </div>
        </li>
      </ul>

      <form class="flex gap-2" @submit.prevent="submit">
        <label class="min-w-0 flex-1">
          <span class="sr-only">Name of the new Team Member</span>
          <input
            v-model="name"
            type="text"
            class="input input-sm w-full"
            :maxlength="maxNameLength"
            placeholder="Name"
          />
        </label>
        <button type="submit" class="btn btn-sm" :disabled="adding || name.trim() === ''">
          <span v-if="adding" class="loading loading-spinner loading-xs" />
          Add a Team Member
        </button>
      </form>
    </div>
  </div>
</template>
