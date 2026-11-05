<script setup lang="ts">
import { computed } from "vue"
import AndonAlert from "../components/AndonAlert.vue"
import DemandRow from "../components/DemandRow.vue"
import { useDemands } from "../composables/useDemands"

const { demands, andons, error, loading } = useDemands()

/** The Demand furthest behind its Takt Time comes first, then the earliest due. */
const sorted = computed(() =>
  [...demands.value].sort((a, b) => a.taktGap - b.taktGap || a.dueOn.localeCompare(b.dueOn)),
)

const behind = computed(() => demands.value.filter((d) => d.andon).length)

const pieces = computed(() =>
  demands.value.reduce(
    (total, d) => ({
      produced: total.produced + d.piecesProduced,
      asked: total.asked + d.piecesAsked,
    }),
    { produced: 0, asked: 0 },
  ),
)
</script>

<template>
  <section>
    <header class="mb-6 flex flex-wrap items-end justify-between gap-x-10 gap-y-4">
      <div>
        <h2 class="text-xl font-semibold">Active Demands</h2>
        <p class="text-sm opacity-70">
          Each Demand against its own Takt Time. The line marks where it must be today.
        </p>
      </div>
      <dl v-if="demands.length > 0" class="flex flex-wrap gap-x-8 gap-y-3">
        <div>
          <dt class="text-xs font-semibold uppercase tracking-wide opacity-70">Demands</dt>
          <dd class="text-2xl font-semibold tabular-nums">{{ demands.length }}</dd>
        </div>
        <div>
          <dt class="text-xs font-semibold uppercase tracking-wide opacity-70">
            Demands behind Takt
          </dt>
          <dd class="flex items-center gap-2 text-2xl font-semibold tabular-nums">
            <span v-if="behind > 0" class="size-2.5 rounded-full bg-andon" aria-hidden="true" />
            {{ behind }}
          </dd>
        </div>
        <div>
          <dt class="text-xs font-semibold uppercase tracking-wide opacity-70">Pieces</dt>
          <dd class="text-2xl font-semibold tabular-nums">
            {{ pieces.produced }}
            <span class="text-sm font-normal opacity-70">
              of {{ pieces.asked }} in production
            </span>
          </dd>
        </div>
      </dl>
    </header>

    <AndonAlert :andons="andons" />

    <p v-if="loading && demands.length === 0" class="flex items-center gap-3 opacity-70">
      <span class="loading loading-spinner loading-sm" />
      Loading the Demands…
    </p>

    <div v-else-if="error" role="alert" class="alert alert-error">
      <span>The API did not answer: {{ error }}</span>
    </div>

    <p
      v-else-if="demands.length === 0"
      class="rounded-box border border-dashed border-base-content/30 p-8 text-center opacity-70"
    >
      No active Demand yet. A Demand appears here when a Client asks for Pieces.
    </p>

    <div v-else class="grid gap-3">
      <DemandRow v-for="demand in sorted" :key="demand.id" :demand="demand" />
    </div>
  </section>
</template>
