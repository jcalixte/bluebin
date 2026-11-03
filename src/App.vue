<script setup lang="ts">
import { ref } from "vue"
import DemandsView from "./views/DemandsView.vue"
import ValueStreamView from "./views/ValueStreamView.vue"

const views = [
  { id: "demands", label: "Demands" },
  { id: "value-stream", label: "Value Stream" },
] as const

const current = ref<(typeof views)[number]["id"]>("demands")
</script>

<template>
  <div class="min-h-screen bg-base-200">
    <header class="bg-primary text-primary-content">
      <div
        class="mx-auto flex max-w-[110rem] flex-wrap items-center justify-between gap-4 px-6 py-6"
      >
        <div class="flex items-center gap-3">
          <img src="/favicon.svg" alt="" class="size-8 brightness-0 invert" />
          <h1 class="text-2xl font-semibold leading-tight">Bluebin</h1>
        </div>
        <nav class="tabs tabs-box bg-primary-content/15">
          <button
            v-for="view in views"
            :key="view.id"
            class="tab"
            :class="current === view.id ? 'tab-active' : ''"
            @click="current = view.id"
          >
            {{ view.label }}
          </button>
        </nav>
      </div>
    </header>

    <main class="mx-auto max-w-[110rem] px-6 py-8">
      <DemandsView v-if="current === 'demands'" />
      <ValueStreamView v-else />
    </main>
  </div>
</template>
