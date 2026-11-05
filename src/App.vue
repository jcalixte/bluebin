<script setup lang="ts">
import { onBeforeUnmount, ref } from "vue"
import DemandsView from "./views/DemandsView.vue"
import NextThingView from "./views/NextThingView.vue"
import ValueStreamView from "./views/ValueStreamView.vue"

const views = [
  { id: "demands", label: "Demands", path: "/demands" },
  { id: "value-stream", label: "Value Stream", path: "/value-stream" },
  { id: "next", label: "My next thing", path: "/next" },
] as const

type View = (typeof views)[number]

/** The view lives in the URL, so a reload, a bookmark or a shared link opens
 *  the same screen. Any other path, `/` included, shows the Demands. */
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

/** Back and forward move between the views like any other page. */
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
      </div>
    </header>

    <main class="mx-auto max-w-[110rem] px-6 py-8">
      <DemandsView v-if="current.id === 'demands'" />
      <ValueStreamView v-else-if="current.id === 'value-stream'" />
      <NextThingView v-else />
    </main>
  </div>
</template>
