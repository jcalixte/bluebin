<script setup lang="ts">
import { computed, onMounted, ref } from "vue"
import { firstLine, pageUrl, rememberLine, lineId } from "../api"
import AppModal from "./AppModal.vue"
import ErrorToast from "./ErrorToast.vue"

/** The view to open in another Line, as `/demands`. */
const props = defineProps<{ view: string }>()

type Line = { id: string; name: string }

/** Must match `max_name_length` of `bluebin/lines` in the backend. */
const maxNameLength = 60

const lines = ref<Line[]>([])
const problem = ref<string | null>(null)

const current = computed(() => lines.value.find((one) => one.id === lineId))

async function answerOf(response: Response) {
  if (!response.ok) {
    throw new Error((await response.text()) || `API answered ${response.status}`)
  }
  return response.json()
}

onMounted(async () => {
  try {
    lines.value = (await answerOf(await fetch("/api/lines"))) as Line[]
  } catch (cause) {
    problem.value = `The Lines did not load: ${cause instanceof Error ? cause.message : String(cause)}`
    return
  }
  if (current.value) {
    rememberLine(lineId)
  } else {
    // A link to a Line of another account, or an old bookmark.
    rememberLine(null)
    location.replace(pageUrl(props.view, firstLine))
  }
})

const naming = ref<"create" | "rename" | null>(null)
const name = ref("")
const saving = ref(false)
const nameProblem = ref<string | null>(null)

function startNaming(mode: "create" | "rename") {
  name.value = mode === "rename" ? (current.value?.name ?? "") : ""
  nameProblem.value = null
  naming.value = mode
}

async function saveName() {
  const wanted = name.value.trim()
  if (wanted === "" || saving.value) return
  saving.value = true
  nameProblem.value = null
  try {
    const creating = naming.value === "create"
    const response = await fetch(creating ? "/api/lines" : `/api/lines/${lineId}`, {
      method: creating ? "POST" : "PUT",
      headers: { "content-type": "application/json" },
      body: JSON.stringify({ name: wanted }),
    })
    const saved = (await answerOf(response)) as Line
    if (creating) {
      // A new Line is empty: its Work Stations come first.
      location.assign(pageUrl("/design", saved.id))
      return
    }
    lines.value = lines.value.map((one) => (one.id === saved.id ? saved : one))
    naming.value = null
  } catch (cause) {
    nameProblem.value = cause instanceof Error ? cause.message : String(cause)
  } finally {
    saving.value = false
  }
}
</script>

<template>
  <div class="dropdown">
    <div
      tabindex="0"
      role="button"
      class="btn btn-sm btn-ghost max-w-72 font-normal"
      title="Open another Line, or make a new one"
    >
      <span class="truncate">{{ current?.name ?? "Line" }}</span>
      <span aria-hidden="true">▾</span>
    </div>
    <ul
      tabindex="-1"
      class="dropdown-content menu z-20 mt-2 w-72 rounded-box bg-base-100 p-2 text-base-content shadow-lg"
    >
      <li class="menu-title">Lines</li>
      <li v-for="line in lines" :key="line.id">
        <a
          :href="pageUrl(view, line.id)"
          :class="{ 'menu-active': line.id === lineId }"
          :aria-current="line.id === lineId ? 'page' : undefined"
        >
          <span class="truncate">{{ line.name }}</span>
        </a>
      </li>
      <li class="mt-1 border-t border-base-300 pt-1">
        <button type="button" @click="startNaming('create')">New Line…</button>
      </li>
      <li>
        <button type="button" :disabled="!current" @click="startNaming('rename')">
          Rename this one…
        </button>
      </li>
    </ul>
  </div>

  <AppModal v-if="naming" @close="naming = null">
    <form @submit.prevent="saveName">
      <h3 class="text-lg font-semibold">
        {{ naming === "create" ? "New Line" : "Rename this Line" }}
      </h3>
      <p v-if="naming === 'create'" class="py-2 text-sm opacity-80">
        It starts empty, with one Work Station and one Person to rename in Design. The other Value
        Lines do not change.
      </p>
      <label class="floating-label mt-4 block">
        <span>Name</span>
        <input
          v-model="name"
          class="input w-full"
          placeholder="Name, for example Mobile app"
          :maxlength="maxNameLength"
          required
          autofocus
        />
      </label>
      <p v-if="nameProblem" role="alert" class="mt-3 text-sm text-error">{{ nameProblem }}</p>
      <div class="modal-action">
        <button type="button" class="btn btn-ghost" @click="naming = null">Cancel</button>
        <button type="submit" class="btn btn-primary" :disabled="saving || name.trim() === ''">
          {{ naming === "create" ? "Make it" : "Rename" }}
        </button>
      </div>
    </form>
  </AppModal>

  <ErrorToast v-model="problem" tone="error" />
</template>
