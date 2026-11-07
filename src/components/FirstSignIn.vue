<script setup lang="ts">
import { computed, ref } from "vue"
import { useAccount } from "../composables/useAccount"

const props = defineProps<{ email: string; firstName: string; lastName: string }>()

/** Must match `max_name_length` in `bluebin/accounts`. */
const maxNameLength = 60

const { saveName } = useAccount()

const firstName = ref(props.firstName)
const lastName = ref(props.lastName)
const saving = ref(false)
const problem = ref<string | null>(null)

const ready = computed(() => firstName.value.trim() !== "" && lastName.value.trim() !== "")

async function save() {
  if (!ready.value || saving.value) return
  saving.value = true
  problem.value = null
  try {
    await saveName(firstName.value.trim(), lastName.value.trim())
  } catch (cause) {
    problem.value = cause instanceof Error ? cause.message : String(cause)
    saving.value = false
  }
}
</script>

<template>
  <div class="grid min-h-screen place-items-center bg-base-200 px-6 py-12">
    <form
      class="card w-full max-w-md bg-base-100 shadow-sm"
      aria-labelledby="first-sign-in-title"
      @submit.prevent="save"
    >
      <div class="card-body gap-4">
        <div class="flex items-center gap-3 text-primary">
          <svg
            class="size-8"
            viewBox="0 0 24 24"
            fill="none"
            stroke="currentColor"
            stroke-width="2"
            stroke-linecap="round"
            stroke-linejoin="round"
            aria-hidden="true"
          >
            <path d="M4 4l6 0" />
            <path d="M14 4l6 0" />
            <path
              d="M4 10a2 2 0 0 1 2 -2h2a2 2 0 0 1 2 2v8a2 2 0 0 1 -2 2h-2a2 2 0 0 1 -2 -2l0 -8"
            />
            <path
              d="M14 10a2 2 0 0 1 2 -2h2a2 2 0 0 1 2 2v2a2 2 0 0 1 -2 2h-2a2 2 0 0 1 -2 -2l0 -2"
            />
          </svg>
          <span class="text-xl font-semibold text-base-content">Bluebin</span>
        </div>
        <div>
          <h1 id="first-sign-in-title" class="text-2xl font-semibold">Welcome</h1>
          <p class="mt-1 text-sm opacity-80">
            Give your first and last name. Your team sees this name on your work. Bluebin asks only
            once.
          </p>
        </div>
        <p class="text-sm">
          <span class="opacity-70">Signed in as</span>
          <span class="font-medium">{{ email }}</span>
        </p>
        <div class="grid gap-3 sm:grid-cols-2">
          <label class="flex flex-col gap-1 text-sm">
            <span class="font-medium">First name</span>
            <input
              v-model="firstName"
              class="input w-full"
              autocomplete="given-name"
              :maxlength="maxNameLength"
              required
            />
          </label>
          <label class="flex flex-col gap-1 text-sm">
            <span class="font-medium">Last name</span>
            <input
              v-model="lastName"
              class="input w-full"
              autocomplete="family-name"
              :maxlength="maxNameLength"
              required
            />
          </label>
        </div>
        <div v-if="problem" role="alert" class="alert alert-error text-sm">
          <span>Your name was not saved: {{ problem }}</span>
        </div>
        <button type="submit" class="btn btn-primary" :disabled="!ready || saving">
          Continue to Bluebin
        </button>
      </div>
    </form>
  </div>
</template>
