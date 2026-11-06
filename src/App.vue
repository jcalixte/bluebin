<script setup lang="ts">
import { onBeforeUnmount, ref } from "vue"
import { api, pageUrl, settleLineUrl, viewPath } from "./api"
import AppModal from "./components/AppModal.vue"
import ErrorToast from "./components/ErrorToast.vue"
import LinePicker from "./components/LinePicker.vue"
import BacklogView from "./views/BacklogView.vue"
import DemandsView from "./views/DemandsView.vue"
import DesignView from "./views/DesignView.vue"
import MeasuresView from "./views/MeasuresView.vue"
import NextThingView from "./views/NextThingView.vue"
import LineView from "./views/LineView.vue"
import { useLabels } from "./composables/useLabels"

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

function viewAt(path: string): View {
  return views.find((view) => view.path === path.replace(/\/+$/, "")) ?? views[0]
}

settleLineUrl()
const current = ref<View>(viewAt(viewPath()))

function open(view: View) {
  if (view.path !== viewPath()) {
    history.pushState(null, "", pageUrl(view.path))
  }
  current.value = view
}

const choosingReset = ref(false)
const resetting = ref(false)
const resetError = ref<string | null>(null)

async function reset(mode: "demo" | "empty") {
  resetting.value = true
  try {
    const response = await fetch(api("/api/reset"), {
      method: "POST",
      headers: { "content-type": "application/json" },
      body: JSON.stringify({ mode }),
    })
    if (!response.ok) {
      throw new Error((await response.text()) || `API answered ${response.status}`)
    }
    location.reload()
  } catch (cause) {
    resetting.value = false
    choosingReset.value = false
    resetError.value = `The reset failed: ${cause instanceof Error ? cause.message : String(cause)}`
  }
}

const onPopState = () => (current.value = viewAt(viewPath()))
addEventListener("popstate", onPopState)
onBeforeUnmount(() => removeEventListener("popstate", onPopState))
</script>

<template>
  <div class="min-h-screen bg-base-200">
    <header class="bg-primary text-primary-content">
      <div
        class="mx-auto flex max-w-[110rem] flex-wrap items-center justify-between gap-4 px-6 py-6"
      >
        <div class="flex items-center gap-3">
          <span
            class="size-8 bg-current"
            style="mask: url(/favicon.svg) center / contain no-repeat"
          />
          <h1 class="text-2xl font-semibold leading-tight">Bluebin</h1>
          <LinePicker :view="current.path" />
        </div>
        <div class="flex flex-wrap items-center gap-3">
          <nav class="tabs tabs-box">
            <a
              v-for="view in views"
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
          <button
            type="button"
            class="btn btn-sm btn-ghost"
            :disabled="resetting"
            title="Load the demo data, or start empty"
            @click="choosingReset = true"
          >
            Reset…
          </button>
        </div>
      </div>
    </header>

    <main class="mx-auto max-w-[110rem] px-6 py-8">
      <DemandsView v-if="current.id === 'demands'" />
      <BacklogView v-else-if="current.id === 'backlog'" />
      <LineView v-else-if="current.id === 'line'" />
      <MeasuresView v-else-if="current.id === 'measures'" />
      <DesignView v-else-if="current.id === 'design'" />
      <NextThingView v-else />
    </main>

    <AppModal v-if="choosingReset" @close="choosingReset = false">
      <h3 class="text-lg font-semibold">Reset this Line</h3>
      <p class="py-2 text-sm opacity-80">
        Every change made in this Line is lost. The other Lines stay. Pick what to start from.
      </p>
      <div class="grid gap-3">
        <div class="rounded-box border border-base-300 p-4">
          <button
            type="button"
            class="btn btn-primary btn-sm"
            :disabled="resetting"
            @click="reset('demo')"
          >
            Load the demo data
          </button>
          <p class="mt-2 text-sm opacity-80">
            Example {{ labels.demands }}, {{ labels.pieces }}, People and Work Stations, to try
            Bluebin.
          </p>
        </div>
        <div class="rounded-box border border-base-300 p-4">
          <button type="button" class="btn btn-sm" :disabled="resetting" @click="reset('empty')">
            Start empty
          </button>
          <p class="mt-2 text-sm opacity-80">
            Removes every {{ labels.demand }}, {{ labels.piece }}, Person and Work Station. Keeps
            the Working Calendar and the labels. Leaves one Work Station and one Person to rename in
            Design.
          </p>
        </div>
      </div>
      <div class="modal-action">
        <button type="button" class="btn btn-ghost" @click="choosingReset = false">Cancel</button>
      </div>
    </AppModal>

    <ErrorToast v-model="resetError" tone="error" />
  </div>
</template>
