<script setup lang="ts">
import { ref } from "vue"
import AppModal from "./AppModal.vue"

const emit = defineEmits<{ close: [] }>()

type Invitation = { link: string; expires: string }

const invitation = ref<Invitation | null>(null)
const making = ref(false)
const error = ref<string | null>(null)
const copied = ref(false)

async function make() {
  making.value = true
  error.value = null
  copied.value = false
  try {
    const response = await fetch("/api/invitations", { method: "POST" })
    if (!response.ok) {
      throw new Error((await response.text()) || `API answered ${response.status}`)
    }
    invitation.value = (await response.json()) as Invitation
  } catch (cause) {
    error.value = `No invitation: ${cause instanceof Error ? cause.message : String(cause)}`
  } finally {
    making.value = false
  }
}

async function copy() {
  if (!invitation.value) return
  try {
    await navigator.clipboard.writeText(invitation.value.link)
    copied.value = true
  } catch {
    error.value = "The browser refused the copy. Select the link and copy it."
  }
}

function day(expires: string) {
  return new Date(expires).toLocaleString(undefined, { dateStyle: "full", timeStyle: "short" })
}
</script>

<template>
  <AppModal @close="emit('close')">
    <h3 class="text-lg font-semibold">Invite a person</h3>
    <p class="py-2 text-sm opacity-80">
      The link lets one person make an account and sign in to Bluebin. It works one time only, for
      one week. Send it to the person. Do not open it yourself: opening it uses it.
    </p>

    <div v-if="invitation" class="grid gap-2">
      <label class="text-sm font-medium" for="invitation-link">Sign-up link</label>
      <div class="join w-full">
        <input
          id="invitation-link"
          class="input join-item w-full font-mono text-xs"
          readonly
          :value="invitation.link"
          @focus="($event.target as HTMLInputElement).select()"
        />
        <button type="button" class="btn btn-primary join-item" @click="copy">
          {{ copied ? "Copied" : "Copy" }}
        </button>
      </div>
      <p class="text-sm opacity-80">Expires {{ day(invitation.expires) }}.</p>
    </div>

    <p v-if="error" role="alert" class="mt-2 text-sm text-error">{{ error }}</p>

    <div class="modal-action">
      <button type="button" class="btn btn-ghost" @click="emit('close')">Close</button>
      <button
        type="button"
        class="btn"
        :class="invitation ? '' : 'btn-primary'"
        :disabled="making"
        :aria-busy="making"
        @click="make"
      >
        <span v-if="making" class="loading loading-spinner loading-xs" />
        {{ invitation ? "Make another link" : "Make a link" }}
      </button>
    </div>
  </AppModal>
</template>
