<script setup lang="ts">
import { computed, ref } from "vue"
import AndonAlert from "../components/AndonAlert.vue"
import DemandRow from "../components/DemandRow.vue"
import NewDemandDialog from "../components/NewDemandDialog.vue"
import { useDemands } from "../composables/useDemands"
import { useLabels } from "../composables/useLabels"
import { useWorkspaces } from "../composables/useWorkspaces"

const { demands, andons, error, loading, load } = useDemands()
const { labels } = useLabels()
const { canAct } = useWorkspaces()

const creating = ref(false)

function created() {
  creating.value = false
  void load()
}

const sorted = computed(() =>
  [...demands.value].sort((a, b) => a.taktGap - b.taktGap || a.dueOn.localeCompare(b.dueOn)),
)

const behind = computed(() => demands.value.filter((d) => d.andon).length)

const pieces = computed(() =>
  demands.value.reduce(
    (total, d) => ({
      deployed: total.deployed + d.piecesDeployed,
      asked: total.asked + d.piecesAsked,
    }),
    { deployed: 0, asked: 0 },
  ),
)
</script>

<template>
  <section>
    <header class="mb-6 flex flex-wrap items-end justify-between gap-x-10 gap-y-4">
      <div>
        <h2 class="text-xl font-semibold">Active {{ labels.demands }}</h2>
        <p class="text-sm opacity-70">
          Each Demand against its own Takt Time. The line marks where it must be today.
        </p>
      </div>
      <div v-if="demands.length > 0" class="flex flex-wrap items-end gap-x-10 gap-y-4">
        <dl class="flex flex-wrap gap-x-8 gap-y-3">
          <div>
            <dt class="text-xs font-semibold uppercase tracking-wide opacity-70">
              {{ labels.demands }}
            </dt>
            <dd class="text-2xl font-semibold tabular-nums">{{ demands.length }}</dd>
          </div>
          <div>
            <dt class="text-xs font-semibold uppercase tracking-wide opacity-70">
              {{ labels.demands }} behind Takt
            </dt>
            <dd class="flex items-center gap-2 text-2xl font-semibold tabular-nums">
              <span v-if="behind > 0" class="size-2.5 rounded-full bg-andon" aria-hidden="true" />
              {{ behind }}
            </dd>
          </div>
          <div>
            <dt class="text-xs font-semibold uppercase tracking-wide opacity-70">
              {{ labels.pieces }}
            </dt>
            <dd class="text-2xl font-semibold tabular-nums">
              {{ pieces.deployed }}
              <span class="text-sm font-normal opacity-70"> of {{ pieces.asked }} deployed </span>
            </dd>
          </div>
        </dl>
        <button v-if="canAct" type="button" class="btn btn-primary btn-sm" @click="creating = true">
          New {{ labels.demand }}
        </button>
      </div>
    </header>

    <AndonAlert :andons="andons" />

    <p v-if="loading && demands.length === 0" class="flex items-center gap-3 opacity-70">
      <span class="loading loading-spinner loading-sm" />
      Loading the Demands…
    </p>

    <div v-else-if="error" role="alert" class="alert alert-error">
      <span>The API did not answer: {{ error }}</span>
    </div>

    <div
      v-else-if="demands.length === 0"
      class="flex flex-col items-center gap-4 rounded-box border border-dashed border-base-content/30 p-8 text-center"
    >
      <p class="opacity-70">
        No active {{ labels.demand }}.
        <template v-if="canAct">
          Create one when a Client asks for {{ labels.pieces }} by a due date.
        </template>
      </p>
      <button v-if="canAct" type="button" class="btn btn-primary" @click="creating = true">
        New {{ labels.demand }}
      </button>
    </div>

    <div v-else class="grid gap-3">
      <DemandRow
        v-for="demand in sorted"
        :key="demand.id"
        :demand="demand"
        :can-change-code="canAct"
        @changed="load"
      />
    </div>

    <NewDemandDialog v-if="creating" @created="created" @close="creating = false" />
  </section>
</template>
