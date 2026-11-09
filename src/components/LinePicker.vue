<script setup lang="ts">
import { computed, onMounted, ref } from "vue"
import { firstLine, lineApi, lineId, lookOnly, pageUrl, rememberLine, workspaceOwner } from "../api"
import { useAccount } from "../composables/useAccount"
import { useWorkspaces } from "../composables/useWorkspaces"
import type { LineEntry, Workspace } from "../types"
import type { NameInput, ShareInput } from "../wire"
import AppModal from "./AppModal.vue"
import ErrorToast from "./ErrorToast.vue"
import { simulationUrl } from "../simulation/state"

/** The view to open in another Line, as `/demands`. */
const props = defineProps<{ view: string }>()

/** Must match `max_name_length` of `bluebin/lines` in the backend. */
const maxNameLength = 60

const { workspaces, workspace, current, problem, ready } = useWorkspaces()
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

/** The name of a Line opened by its link and missing from the menu: a Shared Line to look at. */
const linkedName = ref<string | null>(null)

const name = computed(() => current.value?.name ?? linkedName.value)

onMounted(async () => {
  await ready
  if (problem.value) return
  if (current.value) {
    rememberLine(lineId, workspaceOwner)
    return
  }
  const response = await fetch(lineApi).catch(() => null)
  if (response?.ok) {
    linkedName.value = ((await response.json()) as { name: string }).name
    return
  }
  if (lookOnly) {
    problem.value = "This Line is not shared, or it does not exist."
    return
  }
  // A Line this Account cannot open, or an old bookmark.
  rememberLine(null)
  location.replace(pageUrl(props.view, firstLine, null))
})

const copied = ref<string | null>(null)

async function copyLookOnlyLink() {
  if (!workspace.value) return
  const link = location.origin + pageUrl(props.view, lineId, workspace.value.owner, true)
  try {
    await navigator.clipboard.writeText(link)
    copied.value = "Link copied. Anyone with it can look at this Line, signed in or not."
  } catch {
    copied.value = `Copy this link: ${link}`
  }
}

const naming = ref<"create" | "rename" | null>(null)
const newName = ref("")
const shareNew = ref(false)
const saving = ref(false)
const nameProblem = ref<string | null>(null)

function startNaming(mode: "create" | "rename") {
  newName.value = mode === "rename" ? (current.value?.name ?? "") : ""
  shareNew.value = false
  nameProblem.value = null
  naming.value = mode
}

async function share(path: string, shared: boolean): Promise<boolean> {
  const answer = (await answerOf(
    await fetch(`${path}/sharing`, {
      method: "PUT",
      headers: { "content-type": "application/json" },
      body: JSON.stringify({ shared } satisfies ShareInput),
    }),
  )) as { shared: boolean }
  return answer.shared
}

async function saveName() {
  const wanted = newName.value.trim()
  if (wanted === "" || saving.value) return
  saving.value = true
  nameProblem.value = null
  try {
    const creating = naming.value === "create"
    const response = await fetch(creating ? "/api/lines" : lineApi, {
      method: creating ? "POST" : "PUT",
      headers: { "content-type": "application/json" },
      body: JSON.stringify({ name: wanted } satisfies NameInput),
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
  <span v-if="lookOnly" class="max-w-72 truncate px-3 text-sm">{{ name ?? "Shared Line" }}</span>
  <div v-else class="dropdown">
    <div
      tabindex="0"
      role="button"
      class="btn btn-sm btn-ghost max-w-72 font-normal [--btn-rest-fg:var(--color-primary-content)]"
      title="Open another Line, or make a new one"
    >
      <span class="truncate">{{ name ?? "Line" }}</span>
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
      <li>
        <a
          :href="simulationUrl"
          target="_blank"
          rel="noopener"
          title="A Line with demo data, in a new tab: play any Team Member, nothing is saved"
        >
          Try the Simulation <span aria-hidden="true">↗</span>
        </a>
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
                : 'Anyone with its link will look at it, signed in or not'
            "
            @click="toggleSharing"
          >
            {{ current.shared ? "Make it Private" : "Make it Shared" }}
          </button>
        </li>
      </template>
      <li v-if="current?.shared && workspace">
        <button type="button" title="A link that opens with no sign-in" @click="copyLookOnlyLink">
          Copy look-only link
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
        It starts empty, with one Work Station and one Team Member to rename in Design. The other
        Lines do not change.
      </p>
      <label class="floating-label mt-4 block">
        <span>Name</span>
        <input
          v-model="newName"
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
              Also anyone with its link, signed in or not, look only.
            </span>
          </span>
        </label>
      </fieldset>
      <p v-if="nameProblem" role="alert" class="mt-3 text-sm text-error">{{ nameProblem }}</p>
      <div class="modal-action">
        <button type="button" class="btn btn-ghost" @click="naming = null">Cancel</button>
        <button type="submit" class="btn btn-primary" :disabled="saving || newName.trim() === ''">
          {{ naming === "create" ? "Make it" : "Rename" }}
        </button>
      </div>
    </form>
  </AppModal>

  <ErrorToast v-model="problem" tone="error" />
  <ErrorToast v-model="copied" tone="info" />
</template>
