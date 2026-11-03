<script setup lang="ts">
import { computed } from "vue"
import DemandRow from "./components/DemandRow.vue"
import { useDemands } from "./composables/useDemands"

const { demands, error, loading, load } = useDemands()

const behind = computed(() => demands.value.filter((d) => d.andon).length)
</script>

<template>
  <div class="min-h-screen bg-base-200">
    <header class="bg-primary text-primary-content">
      <div class="mx-auto flex max-w-5xl flex-wrap items-center justify-between gap-4 px-6 py-6">
        <div class="flex items-center gap-3">
          <img src="/favicon.svg" alt="" class="size-8 brightness-0 invert" />
          <div>
            <h1 class="text-2xl font-semibold leading-tight">Bluebin</h1>
            <p class="text-sm opacity-80">Pull Kanban · active Demands</p>
          </div>
        </div>
        <button class="btn btn-sm" :disabled="loading" @click="load">Refresh</button>
      </div>
    </header>

    <main class="mx-auto max-w-5xl px-6 py-8">
      <div v-if="behind > 0" role="alert" class="alert alert-error mb-6 font-medium">
        <span class="inline-block size-3 rounded-full bg-current" />
        <span>
          {{ behind }}
          {{ behind === 1 ? "Demand is" : "Demands are" }}
          behind Takt Time.
        </span>
      </div>

      <p v-if="loading" class="flex items-center gap-3 opacity-70">
        <span class="loading loading-spinner loading-sm" />
        Loading the Demands…
      </p>

      <div v-else-if="error" class="alert alert-error">
        <span>The API did not answer: {{ error }}</span>
      </div>

      <p v-else-if="demands.length === 0" class="opacity-70">No active Demand yet.</p>

      <div v-else class="grid gap-4">
        <DemandRow v-for="demand in demands" :key="demand.id" :demand="demand" />
      </div>
    </main>
  </div>
</template>
