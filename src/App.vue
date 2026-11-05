<script setup lang="ts">
import { onBeforeUnmount, ref } from "vue"
import BacklogView from "./views/BacklogView.vue"
import DemandsView from "./views/DemandsView.vue"
import NextThingView from "./views/NextThingView.vue"
import ValueStreamView from "./views/ValueStreamView.vue"

const views = [
  { id: "demands", label: "Demands", path: "/demands" },
  { id: "backlog", label: "Backlog", path: "/backlog" },
  { id: "value-stream", label: "Value Stream", path: "/value-stream" },
  { id: "next", label: "My next thing", path: "/next" },
] as const

type View = (typeof views)[number]

function viewAt(path: string): View {
  return views.find((view) => view.path === path.replace(/\/+$/, "")) ?? views[0]
}

const current = ref<View>(viewAt(location.pathname))

function open(view: View) {
  if (view.path !== location.pathname) {
    history.pushState(null, "", view.path)
  }
  current.value = view
}

const resetting = ref(false)

async function resetDemo() {
  if (!confirm("Reset all the demo data? Every change made on Bluebin will be lost.")) return
  resetting.value = true
  const response = await fetch("/api/reset", { method: "POST" })
  if (response.ok) {
    location.reload()
  } else {
    resetting.value = false
    alert("The reset failed. Try again.")
  }
}

const onPopState = () => (current.value = viewAt(location.pathname))
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
        </div>
        <div class="flex flex-wrap items-center gap-3">
          <nav class="tabs tabs-box">
            <a
              v-for="view in views"
              :key="view.id"
              :href="view.path"
              class="tab"
              :class="
                current.id === view.id
                  ? 'tab-active font-medium text-base-content'
                  : 'text-base-content/70'
              "
              :aria-current="current.id === view.id ? 'page' : undefined"
              @click.exact.prevent="open(view)"
            >
              {{ view.label }}
            </a>
          </nav>
          <button
            type="button"
            class="btn btn-sm btn-ghost"
            :disabled="resetting"
            title="Put back the demo data"
            @click="resetDemo"
          >
            Reset demo
          </button>
        </div>
      </div>
    </header>

    <main class="mx-auto max-w-[110rem] px-6 py-8">
      <DemandsView v-if="current.id === 'demands'" />
      <BacklogView v-else-if="current.id === 'backlog'" />
      <ValueStreamView v-else-if="current.id === 'value-stream'" />
      <NextThingView v-else />
    </main>
  </div>
</template>
