<script setup lang="ts">
import DeviationDialog from "../components/DeviationDialog.vue"
import { useBacklog } from "../composables/useBacklog"
import { useFlowRunner } from "../composables/useFlowRunner"

const { backlog, error, loading, makeUrgent } = useBacklog()
const { pending, actionError, busy, run, recordDeviation } = useFlowRunner()

function urgent(piece: string) {
  run((reason) => makeUrgent(piece, reason))
}

function dateLabel(day: string, options: Intl.DateTimeFormatOptions) {
  return new Date(`${day}T12:00:00`).toLocaleDateString(undefined, options)
}
</script>

<template>
  <section>
    <header class="mb-6">
      <h2 class="text-xl font-semibold">Backlog</h2>
      <p class="text-sm opacity-70">
        Pieces leave in Heijunka Sequence, one for each Kanban of the first Work Station
      </p>
    </header>

    <p v-if="loading && !backlog" class="flex items-center gap-3 opacity-70">
      <span class="loading loading-spinner loading-sm" />
      Loading the Backlog…
    </p>

    <div v-else-if="error" class="alert alert-error">
      <span>The API did not answer: {{ error }}</span>
    </div>

    <div v-else-if="backlog" class="grid gap-6 xl:grid-cols-[minmax(0,3fr)_minmax(0,4fr)]">
      <div class="card border border-base-300 bg-base-100 shadow-sm">
        <div class="card-body gap-3 p-5">
          <h3 class="card-title text-base">Heijunka Sequence</h3>
          <p class="text-sm opacity-70">
            Each Piece has a slot at a multiple of its Demand's Takt Time: the earliest slot goes
            first, then the earliest due date, then first in.
          </p>
          <div v-if="actionError" class="alert alert-error text-sm">
            <span>{{ actionError }}</span>
          </div>
          <p v-if="backlog.sequence.length === 0" class="opacity-70">The Backlog is empty.</p>
          <ol v-else class="divide-y divide-base-300">
            <li
              v-for="(piece, index) in backlog.sequence"
              :key="piece.id"
              class="flex items-center gap-3 py-2"
            >
              <span class="w-6 text-right text-sm tabular-nums opacity-60">{{ index + 1 }}</span>
              <div class="min-w-0 flex-1">
                <p class="font-medium">
                  {{ piece.reference }}
                  <span v-if="piece.urgent" class="badge badge-warning badge-sm ml-1">Urgent</span>
                </p>
                <p class="truncate text-sm opacity-70">
                  {{ piece.demandLabel }} · {{ piece.client }} · due
                  {{ dateLabel(piece.dueOn, { day: "numeric", month: "short" }) }}
                </p>
              </div>
              <button
                v-if="piece.canBeUrgent"
                type="button"
                class="btn btn-ghost btn-xs"
                :disabled="busy"
                title="Release this Piece before its turn. It is a Deviation."
                @click="urgent(piece.id)"
              >
                Make urgent
              </button>
            </li>
          </ol>
        </div>
      </div>

      <div class="card border border-base-300 bg-base-100 shadow-sm">
        <div class="card-body gap-3 p-5">
          <h3 class="card-title text-base">Product Mix</h3>
          <p class="text-sm opacity-70">
            Pieces that left the Backlog each day, against the plan of each Demand's Takt Time. More
            than 1 Piece apart is off plan.
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
          <p class="text-xs opacity-60">Real / planned. Today counts the whole day.</p>
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
