<script setup lang="ts">
import { computed, onMounted, ref } from "vue"
import { firstLine, lineApi, lineId, pageUrl, rememberLine, workspaceOwner } from "../api"
import { useAccount } from "../composables/useAccount"
import { useWorkspaces } from "../composables/useWorkspaces"
import type { LineEntry, Workspace } from "../types"
import AppModal from "./AppModal.vue"
import ErrorToast from "./ErrorToast.vue"

/** The view to open in another Line, as `/demands`. */
const props = defineProps<{ view: string }>()

/** Must match `max_name_length` of `bluebin/lines` in the backend. */
const maxNameLength = 60

const { workspaces, current, problem, ready } = useWorkspaces()
const { account } = useAccount()

/** Sharing lives with the Accounts, so it needs sign-in (F52). */
const canShare = computed(() => account.value?.signedIn === true)
const owns = computed(() => current.value?.role === "owner")

function title(workspace: Workspace): string {
  if (workspace.own) return "Your Lines"
  return `Lines of ${workspace.name ?? "another Account"}`
}

function opensHere(workspace: Workspace, line: LineEntry): boolean {
  const here = workspaceOwner ? workspace.owner === workspaceOwner : workspace.own
  return here && line.id === lineId
}

function urlOf(workspace: Workspace, line: LineEntry): string {
  return pageUrl(props.view, line.id, workspace.own ? null : workspace.owner)
}

async function answerOf(response: Response) {
  if (!response.ok) {
    throw new Error((await response.text()) || `API answered ${response.status}`)
  }
  return response.json()
}

onMounted(async () => {
  await ready
  if (problem.value) return
  if (current.value) {
    rememberLine(lineId, workspaceOwner)
  } else {
    // A Line this Account cannot open, or an old bookmark.
    rememberLine(null)
    location.replace(pageUrl(props.view, firstLine, null))
  }
})

const naming = ref<"create" | "rename" | null>(null)
const name = ref("")
const shareNew = ref(false)
const saving = ref(false)
const nameProblem = ref<string | null>(null)

function startNaming(mode: "create" | "rename") {
  name.value = mode === "rename" ? (current.value?.name ?? "") : ""
  shareNew.value = false
  nameProblem.value = null
  naming.value = mode
}

async function share(path: string, shared: boolean): Promise<boolean> {
  const answer = (await answerOf(
    await fetch(`${path}/sharing`, {
      method: "PUT",
      headers: { "content-type": "application/json" },
      body: JSON.stringify({ shared }),
    }),
  )) as { shared: boolean }
  return answer.shared
}

async function saveName() {
  const wanted = name.value.trim()
  if (wanted === "" || saving.value) return
  saving.value = true
  nameProblem.value = null
  try {
    const creating = naming.value === "create"
    const response = await fetch(creating ? "/api/lines" : lineApi, {
      method: creating ? "POST" : "PUT",
      headers: { "content-type": "application/json" },
      body: JSON.stringify({ name: wanted }),
    })
    const saved = (await answerOf(response)) as { id: string; name: string }
    if (creating) {
      if (shareNew.value) await share(`/api/lines/${saved.id}`, true)
      // A new Line is empty: its Work Stations come first.
      location.assign(pageUrl("/design", saved.id, null))
      return
    }
    if (current.value) current.value.name = saved.name
    naming.value = null
  } catch (cause) {
    nameProblem.value = cause instanceof Error ? cause.message : String(cause)
  } finally {
    saving.value = false
  }
}

async function toggleSharing() {
  const line = current.value
  if (!line) return
  try {
    line.shared = await share(lineApi, !line.shared)
  } catch (cause) {
    problem.value = `The Line did not change: ${cause instanceof Error ? cause.message : String(cause)}`
  }
}
</script>

<template>
  <div class="dropdown">
    <div
      tabindex="0"
      role="button"
      class="btn btn-sm btn-ghost max-w-72 font-normal [--btn-rest-fg:var(--color-primary-content)]"
      title="Open another Line, or make a new one"
    >
      <span class="truncate">{{ current?.name ?? "Line" }}</span>
      <span aria-hidden="true">▾</span>
    </div>
    <ul
      tabindex="-1"
      class="dropdown-content menu z-20 mt-2 max-h-[70vh] w-80 flex-nowrap overflow-y-auto rounded-box bg-base-100 p-2 text-base-content shadow-lg"
    >
      <template v-for="workspace in workspaces" :key="workspace.owner">
        <li class="menu-title">{{ title(workspace) }}</li>
        <li v-for="line in workspace.lines" :key="line.id">
          <a
            :href="urlOf(workspace, line)"
            :class="{ 'menu-active': opensHere(workspace, line) }"
            :aria-current="opensHere(workspace, line) ? 'page' : undefined"
          >
            <span class="truncate">{{ line.name }}</span>
            <span v-if="line.role === 'viewer'" class="badge badge-ghost badge-sm ml-auto">
              Look only
            </span>
            <span v-else-if="canShare && line.shared" class="badge badge-ghost badge-sm ml-auto">
              Shared
            </span>
          </a>
        </li>
      </template>
      <li class="mt-1 border-t border-base-300 pt-1">
        <button type="button" @click="startNaming('create')">New Line…</button>
      </li>
      <template v-if="owns">
        <li>
          <button type="button" @click="startNaming('rename')">Rename this one…</button>
        </li>
        <li v-if="canShare && current">
          <button
            type="button"
            :title="
              current.shared
                ? 'Only you and its Team Members will see it'
                : 'Every Account that can open your Workspace will see it'
            "
            @click="toggleSharing"
          >
            {{ current.shared ? "Make it Private" : "Make it Shared" }}
          </button>
        </li>
      </template>
    </ul>
  </div>

  <AppModal v-if="naming" @close="naming = null">
    <form @submit.prevent="saveName">
      <h3 class="text-lg font-semibold">
        {{ naming === "create" ? "New Line" : "Rename this Line" }}
      </h3>
      <p v-if="naming === 'create'" class="py-2 text-sm opacity-80">
        It starts empty, with one Work Station and one Team Member to rename in Design. The other
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
      <fieldset v-if="naming === 'create' && canShare" class="mt-4 grid gap-2">
        <legend class="mb-2 text-sm font-medium">Who sees it</legend>
        <label class="flex items-start gap-3">
          <input v-model="shareNew" type="radio" class="radio radio-sm mt-0.5" :value="false" />
          <span>
            <span class="block">Private</span>
            <span class="block text-sm opacity-80">You and its Team Members.</span>
          </span>
        </label>
        <label class="flex items-start gap-3">
          <input v-model="shareNew" type="radio" class="radio radio-sm mt-0.5" :value="true" />
          <span>
            <span class="block">Shared</span>
            <span class="block text-sm opacity-80">
              Also every Account that is a Team Member in one of your Lines, look only.
            </span>
          </span>
        </label>
      </fieldset>
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
