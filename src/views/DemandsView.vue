<script setup lang="ts">
import { computed } from "vue"
import AndonAlert from "../components/AndonAlert.vue"
import DemandRow from "../components/DemandRow.vue"
import { useDemands } from "../composables/useDemands"

const { demands, andons, error, loading } = useDemands()

const behind = computed(() => demands.value.filter((d) => d.andon).length)
</script>

<template>
  <section>
    <header class="mb-6 flex flex-wrap items-end justify-between gap-4">
      <div>
        <h2 class="text-xl font-semibold">Active Demands</h2>
        <p class="text-sm opacity-70">Each Demand against its own Takt Time, for its Client</p>
      </div>
    </header>

    <AndonAlert :andons="andons" />

    <div v-if="behind > 0" role="alert" class="alert alert-error mb-6 font-medium">
      <span class="inline-block size-3 rounded-full bg-current" />
      <span>
        {{ behind }}
        {{ behind === 1 ? "Demand is" : "Demands are" }}
        behind Takt Time.
      </span>
    </div>

    <p v-if="loading && demands.length === 0" class="flex items-center gap-3 opacity-70">
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
  </section>
</template>
