<script setup lang="ts">
import { computed, ref } from "vue"
import DeviationDialog from "../components/DeviationDialog.vue"
import ErrorToast from "../components/ErrorToast.vue"
import HeijunkaBox from "../components/HeijunkaBox.vue"
import { useBacklog } from "../composables/useBacklog"
import { useFlowRunner } from "../composables/useFlowRunner"
import { useLabels } from "../composables/useLabels"
import { useWorkspaces } from "../composables/useWorkspaces"

const { backlog, error, loading, makeUrgent } = useBacklog()
const { pending, actionError, busy, run, recordDeviation } = useFlowRunner()
const { labels } = useLabels()
const { canAct } = useWorkspaces()

/** The Piece under the pointer, shared by the Heijunka box and the list. */
const hovered = ref<string | null>(null)

const sequence = computed(() => backlog.value?.sequence ?? [])
const next = computed(() => sequence.value[0] ?? null)
const demandCount = computed(() => new Set(sequence.value.map((piece) => piece.demand)).size)

const taktLabel = computed(() => {
  const hours = backlog.value?.taktTimeHours ?? 0
  return hours > 0 ? `${Math.round(hours * 10) / 10} h` : "—"
})

function urgent(piece: string) {
  run((reason) => makeUrgent(piece, reason))
}

function dateLabel(day: string, options: Intl.DateTimeFormatOptions) {
  return new Date(`${day}T12:00:00`).toLocaleDateString(undefined, options)
}
</script>

<template>
  <section>
    <header class="mb-6 flex flex-wrap items-end justify-between gap-x-10 gap-y-4">
      <div>
        <h2 class="text-xl font-semibold">Backlog</h2>
        <p class="text-sm opacity-70">
          {{ labels.pieces }} leave in Heijunka Sequence, one for each Kanban of the first Work
          Station
        </p>
      </div>
      <dl v-if="sequence.length > 0" class="flex flex-wrap gap-x-8 gap-y-3">
        <div>
          <dt class="text-xs font-semibold uppercase tracking-wide opacity-70">Next out</dt>
          <dd class="flex items-baseline gap-2">
            <span class="font-mono text-2xl">{{ next?.reference }}</span>
            <span class="max-w-48 truncate text-sm opacity-70">{{ next?.demandLabel }}</span>
          </dd>
        </div>
        <div>
          <dt class="text-xs font-semibold uppercase tracking-wide opacity-70">
            {{ labels.pieces }} waiting
          </dt>
          <dd class="text-2xl font-semibold tabular-nums">
            {{ sequence.length }}
            <span class="text-sm font-normal opacity-70">
              from {{ demandCount }} {{ demandCount === 1 ? labels.demand : labels.demands }}
            </span>
          </dd>
        </div>
        <div>
          <dt class="text-xs font-semibold uppercase tracking-wide opacity-70">
            Takt Time of the Line
          </dt>
          <dd class="text-2xl font-semibold tabular-nums">{{ taktLabel }}</dd>
        </div>
      </dl>
    </header>

    <ErrorToast v-model="actionError" tone="error" />

    <p v-if="loading && !backlog" class="flex items-center gap-3 opacity-70">
      <span class="loading loading-spinner loading-sm" />
      Loading the Backlog…
    </p>

    <div v-else-if="error" role="alert" class="alert alert-error">
      <span>The API did not answer: {{ error }}</span>
    </div>

    <div v-else-if="backlog" class="grid gap-6">
      <div
        v-if="sequence.length === 0"
        class="rounded-box border border-dashed border-base-content/30 p-8 text-center"
      >
        <p class="opacity-70">
          The Backlog is empty. {{ labels.pieces }} come in with a new {{ labels.demand }}.
        </p>
      </div>

      <div v-else class="card border border-base-300 bg-base-100 shadow-sm">
        <div class="card-body gap-4 p-5">
          <div>
            <h3 class="card-title text-base">Heijunka Sequence</h3>
            <p class="text-sm opacity-70">
              One lane for each {{ labels.demand }}. Each Piece has a slot at a multiple of its
              Demand's Takt Time: the earliest slot goes first, then the earliest due date, then
              first in.
            </p>
          </div>
          <HeijunkaBox v-model:hovered="hovered" :sequence="sequence" />
        </div>
      </div>

      <div class="grid items-start gap-6 xl:grid-cols-[minmax(0,3fr)_minmax(0,2fr)]">
        <div v-if="sequence.length > 0" class="card border border-base-300 bg-base-100 shadow-sm">
          <div class="card-body gap-3 p-5">
            <h3 class="card-title text-base">In order</h3>
            <ol class="divide-y divide-base-300">
              <li
                v-for="(piece, index) in sequence"
                :key="piece.id"
                class="-mx-2 grid min-h-11 grid-cols-[2rem_minmax(0,1fr)_auto] items-center gap-3 rounded-field px-2 py-1.5 transition-colors duration-150 motion-reduce:transition-none"
                :class="hovered === piece.id ? 'bg-base-200' : ''"
                @mouseenter="hovered = piece.id"
                @mouseleave="hovered = null"
                @focusin="hovered = piece.id"
                @focusout="hovered = null"
              >
                <span
                  class="text-right text-sm tabular-nums"
                  :class="index === 0 ? 'font-semibold text-primary' : 'opacity-70'"
                >
                  {{ index + 1 }}
                </span>
                <p class="flex min-w-0 flex-wrap items-baseline gap-x-3 gap-y-0.5">
                  <span class="font-mono text-base">{{ piece.reference }}</span>
                  <span class="min-w-0 truncate text-sm opacity-70">{{ piece.demandLabel }}</span>
                  <span v-if="index === 0" class="badge badge-primary badge-sm">Next out</span>
                  <span v-if="piece.urgent" class="badge badge-warning badge-sm">Urgent</span>
                </p>
                <button
                  v-if="piece.canBeUrgent && canAct"
                  type="button"
                  class="btn btn-ghost btn-sm"
                  :disabled="busy"
                  :aria-label="`Make ${piece.reference} of ${piece.demandLabel} urgent`"
                  title="Release this Piece before its turn. It is a Deviation."
                  @click="urgent(piece.id)"
                >
                  Make urgent
                </button>
              </li>
            </ol>
          </div>
        </div>

        <div
          class="card border border-base-300 bg-base-100 shadow-sm xl:sticky xl:top-4"
          :class="sequence.length === 0 ? 'xl:col-span-2' : ''"
        >
          <div class="card-body gap-3 p-5">
            <h3 class="card-title text-base">Product Mix</h3>
            <p class="text-sm opacity-70">
              Pieces that left the Backlog each day, against the plan of each Demand's Takt Time.
              More than 1 Piece apart is off plan.
            </p>
            <div class="overflow-x-auto">
              <table class="table table-sm">
                <thead>
                  <tr>
                    <th>Demand</th>
                    <th
                      v-for="cell in backlog.mix[0]?.cells ?? []"
                      :key="cell.day"
                      class="text-center"
                    >
                      {{ dateLabel(cell.day, { weekday: "short", day: "numeric" }) }}
                    </th>
                  </tr>
                </thead>
                <tbody>
                  <tr v-for="row in backlog.mix" :key="row.demand">
                    <th class="font-medium">{{ row.label }}</th>
                    <td v-for="cell in row.cells" :key="cell.day" class="text-center">
                      <span
                        class="badge badge-sm tabular-nums"
                        :class="cell.onPlan ? 'badge-success' : 'badge-error'"
                        :title="`${cell.real} left the Backlog, ${cell.planned} planned`"
                      >
                        {{ cell.real }} / {{ cell.planned }}
                      </span>
                    </td>
                  </tr>
                </tbody>
              </table>
            </div>
            <p class="text-xs opacity-70">Real / planned. Today counts the whole day.</p>
          </div>
        </div>
      </div>
    </div>

    <DeviationDialog
      v-if="pending"
      :message="pending.message"
      :effects="pending.effects"
      :busy="busy"
      @confirm="recordDeviation"
      @cancel="pending = null"
    />
  </section>
</template>
