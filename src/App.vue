<script setup lang="ts">
import { computed, onBeforeUnmount, ref } from "vue"
import { lineId, lookOnly, pageUrl, settleLineUrl, viewPath, workspaceOwner } from "./api"
import AppModal from "./components/AppModal.vue"
import BrandMark from "./components/BrandMark.vue"
import ErrorToast from "./components/ErrorToast.vue"
import FirstSignIn from "./components/FirstSignIn.vue"
import InviteDialog from "./components/InviteDialog.vue"
import LinePicker from "./components/LinePicker.vue"
import SimulationBar from "./components/SimulationBar.vue"
import ThemeToggle from "./components/ThemeToggle.vue"
import BacklogView from "./views/BacklogView.vue"
import DemandsView from "./views/DemandsView.vue"
import DesignView from "./views/DesignView.vue"
import MeasuresView from "./views/MeasuresView.vue"
import NextThingView from "./views/NextThingView.vue"
import LineView from "./views/LineView.vue"
import { useAccount } from "./composables/useAccount"
import { useLabels } from "./composables/useLabels"
import { homeLine, useWorkspaces } from "./composables/useWorkspaces"
import { appUrl, restartSimulation, simulation } from "./simulation/state"

const views = [
  { id: "demands", label: "Demands", path: "/demands" },
  { id: "backlog", label: "Backlog", path: "/backlog" },
  { id: "line", label: "Line", path: "/line" },
  { id: "next", label: "My next thing", path: "/next" },
  { id: "measures", label: "Measures", path: "/measures" },
  { id: "design", label: "Design", path: "/design" },
] as const

type View = (typeof views)[number]

const { labels } = useLabels()
const { account, checked } = useAccount()
const { role, workspaces, ready } = useWorkspaces()

/** Design is for the owner; Measures is not for who only looks at a Shared Line. */
const shownViews = computed(() =>
  views.filter(
    (view) =>
      (view.id !== "design" || role.value === "owner") &&
      (view.id !== "measures" || role.value !== "viewer"),
  ),
)

const unnamed = computed(() =>
  account.value?.signedIn && !account.value.named ? account.value : null,
)

/** `akadmin`, authentik's own admin, who invites people. */
const isAdmin = computed(() => account.value?.signedIn === true && account.value.admin)
const inviting = ref(false)

function viewAt(path: string): View {
  return views.find((view) => view.path === path.replace(/\/+$/, "")) ?? views[0]
}

/** Opened at `/`, as after sign-in: the Account's own work comes first (F45). */
const landing = ref(location.pathname === "/" && !lookOnly && !simulation)
settleLineUrl()
const opened = ref<View>(viewAt(viewPath()))
/** A link to a hidden tab, as Measures in a Shared Line, opens the first tab. */
const current = computed<View>({
  get: () =>
    shownViews.value.some((view) => view.id === opened.value.id) ? opened.value : views[0],
  set: (view) => (opened.value = view),
})

async function land() {
  await ready
  const home = homeLine(workspaces.value, workspaceOwner, lineId)
  if (!home) {
    landing.value = false
    return
  }
  const url = `${pageUrl("/next", home.id, home.owner, false)}?teamMember=${encodeURIComponent(home.teamMember)}`
  if (home.id !== lineId || home.owner !== workspaceOwner) {
    // The Line is read once per page, so another Line needs a new page.
    location.replace(url)
    return
  }
  history.replaceState(null, "", url)
  current.value = viewAt("/next")
  landing.value = false
}
if (landing.value) void land()

function open(view: View) {
  if (view.path !== viewPath()) {
    history.pushState(null, "", pageUrl(view.path))
  }
  current.value = view
}

const choosingRestart = ref(false)
const restartError = ref<string | null>(null)

function restart(demo: boolean) {
  choosingRestart.value = false
  try {
    restartSimulation(demo)
  } catch (cause) {
    restartError.value = cause instanceof Error ? cause.message : String(cause)
  }
}

const onPopState = () => (current.value = viewAt(viewPath()))
addEventListener("popstate", onPopState)
onBeforeUnmount(() => removeEventListener("popstate", onPopState))
</script>

<template>
  <FirstSignIn
    v-if="unnamed"
    :email="unnamed.email"
    :first-name="unnamed.firstName"
    :last-name="unnamed.lastName"
  />
  <div v-else-if="!checked || landing" class="min-h-screen bg-base-200" />
  <div v-else class="min-h-screen bg-base-200">
    <header class="bg-primary text-primary-content">
      <div
        class="mx-auto flex max-w-[110rem] flex-wrap items-center justify-between gap-4 px-6 py-6"
      >
        <div class="flex items-center gap-3">
          <a
            :href="pageUrl(views[0].path)"
            class="flex items-center gap-3 rounded-field"
            @click.exact.prevent="open(views[0])"
          >
            <BrandMark />
            <h1 class="text-2xl font-semibold leading-tight">Bluebin</h1>
          </a>
          <SimulationBar v-if="simulation" @restart="choosingRestart = true" />
          <LinePicker v-else :view="current.path" />
        </div>
        <div class="flex flex-wrap items-center gap-3">
          <nav class="tabs tabs-box">
            <a
              v-for="view in shownViews"
              :key="view.id"
              :href="pageUrl(view.path)"
              class="tab"
              :class="
                current.id === view.id
                  ? 'tab-active font-medium text-base-content'
                  : 'text-base-content/70'
              "
              :aria-current="current.id === view.id ? 'page' : undefined"
              @click.exact.prevent="open(view)"
            >
              {{ view.id === "demands" ? labels.demands : view.label }}
            </a>
          </nav>
          <a
            href="/about"
            class="btn btn-sm btn-ghost [--btn-rest-fg:var(--color-primary-content)]"
            title="What a pull system and a Kanban are"
          >
            About
          </a>
          <button
            v-if="isAdmin"
            type="button"
            class="btn btn-sm btn-ghost [--btn-rest-fg:var(--color-primary-content)]"
            title="Make a sign-up link for one person"
            @click="inviting = true"
          >
            Invite…
          </button>
          <ThemeToggle class="[--btn-rest-fg:var(--color-primary-content)]" />
        </div>
      </div>
    </header>

    <main class="mx-auto max-w-[110rem] px-6 py-8">
      <p v-if="simulation" role="status" class="alert alert-info mb-6">
        <span>
          This Line lives only in this page: nothing is saved, and a reload starts it again. Play as
          any Team Member, or as the owner to change the Design. For a Line your team keeps,
          <a :href="appUrl" class="link font-medium">sign in to Bluebin</a>.
        </span>
      </p>
      <p v-else-if="lookOnly" role="status" class="alert alert-info mb-6">
        <span>
          You look at this Shared Line. Only its Team Members act in it:
          <a :href="pageUrl(current.path, lineId, workspaceOwner, false)" class="link font-medium"
            >sign in</a
          >
          to act.
        </span>
      </p>
      <p v-else-if="role === 'viewer'" role="status" class="alert alert-info mb-6">
        You look at this Shared Line. Only its Team Members act in it.
      </p>
      <DemandsView v-if="current.id === 'demands'" />
      <BacklogView v-else-if="current.id === 'backlog'" />
      <LineView v-else-if="current.id === 'line'" />
      <MeasuresView v-else-if="current.id === 'measures'" />
      <DesignView v-else-if="current.id === 'design'" />
      <NextThingView v-else />
    </main>

    <AppModal v-if="choosingRestart" @close="choosingRestart = false">
      <h3 class="text-lg font-semibold">Restart the Simulation</h3>
      <p class="py-2 text-sm opacity-80">
        Every change made in the Simulation is lost, and you play the owner again. Pick what to
        start from.
      </p>
      <div class="grid gap-3">
        <div class="rounded-box border border-base-300 p-4">
          <button type="button" class="btn btn-primary btn-sm" @click="restart(true)">
            Load the demo data
          </button>
          <p class="mt-2 text-sm opacity-80">
            Example {{ labels.demands }}, {{ labels.pieces }}, Team Members and Work Stations, to
            try Bluebin.
          </p>
        </div>
        <div class="rounded-box border border-base-300 p-4">
          <button type="button" class="btn btn-sm" @click="restart(false)">Start empty</button>
          <p class="mt-2 text-sm opacity-80">
            Removes every {{ labels.demand }}, {{ labels.piece }}, Team Member and Work Station.
            Keeps the Working Calendar and the labels. Leaves one Work Station and one Team Member
            to rename in Design.
          </p>
        </div>
      </div>
      <div class="modal-action">
        <button type="button" class="btn btn-ghost" @click="choosingRestart = false">Cancel</button>
      </div>
    </AppModal>

    <InviteDialog v-if="inviting" @close="inviting = false" />

    <ErrorToast v-model="restartError" tone="error" />
  </div>
</template>
