<script setup lang="ts">
import { computed, ref, watch } from "vue"
import DeviationDialog from "../components/DeviationDialog.vue"
import { useFlowRunner } from "../composables/useFlowRunner"
import { useNextThing } from "../composables/useNextThing"
import type { Assignment, FlowConfirm, NextThing } from "../types"

/** The Person this screen is for: from the link first, so a shared link opens
 *  the same screen, then from the last choice on this device. */
const storageKey = "bluebin.person"
const personId = ref(
  new URLSearchParams(location.search).get("person") ?? localStorage.getItem(storageKey) ?? "",
)

watch(personId, (id) => {
  localStorage.setItem(storageKey, id)
  const url = new URL(location.href)
  url.searchParams.set("person", id)
  history.replaceState(null, "", url)
})

const { people, view, error, loading, load, pull, finish, repair, assign } = useNextThing(personId)
const { pending, actionError, busy, run, recordDeviation } = useFlowRunner()

const next = computed(() => view.value?.next ?? null)

/** The Assignments that wait behind the active one. */
const waiting = computed(() => (view.value?.assignments ?? []).filter((one) => !one.active))

/** The other People of the Work Station an Assignment belongs to (F21). */
function handOverTo(assignment: Assignment) {
  return (
    view.value?.priorityLists
      .find((list) => list.station === assignment.station)
      ?.people.filter((one) => one.id !== personId.value) ?? []
  )
}

function handOver(assignment: Assignment, event: Event) {
  const person = (event.target as HTMLSelectElement).value
  if (person !== "") {
    void run(() => assign(assignment.kind, assignment.id, person))
  }
}

/** The one action of the next thing, bound to the thing shown when clicked,
 *  so a Deviation confirmed later runs the same action again. */
function doing(now: NextThing): (reason?: string) => Promise<FlowConfirm | null> {
  return (reason) => {
    switch (now.kind) {
      case "continue":
        return now.assignment.kind === "rework"
          ? repair(now.assignment.id)
          : finish(now.assignment.station, now.assignment.id, reason)
      case "take_rework":
        return assign("rework", now.rework, personId.value)
      case "take_kanban":
        return pull(now.station, reason)
      default:
        return Promise.resolve(null)
    }
  }
}

function since(at: string) {
  return new Date(at).toLocaleString(undefined, {
    weekday: "short",
    hour: "2-digit",
    minute: "2-digit",
  })
}
</script>

<template>
  <section class="mx-auto max-w-3xl">
    <header class="mb-6 flex flex-wrap items-end justify-between gap-4">
      <div>
        <h2 class="text-xl font-semibold">My next thing</h2>
        <p class="text-sm opacity-70">
          One thing to do now, from the pull rules — nobody pushes it
        </p>
      </div>
      <div class="flex gap-2">
        <select v-model="personId" class="select select-bordered select-sm" aria-label="Person">
          <option value="" disabled>Who are you?</option>
          <option v-for="one in people" :key="one.id" :value="one.id">
            {{ one.name }} · {{ one.stations.join(", ") }}
          </option>
        </select>
        <button class="btn btn-sm" :disabled="loading" @click="load">Refresh</button>
      </div>
    </header>

    <div v-if="actionError" role="alert" class="alert alert-warning mb-4">
      <span>{{ actionError }}</span>
    </div>

    <p v-if="loading && !view && !error" class="flex items-center gap-3 opacity-70">
      <span class="loading loading-spinner loading-sm" />
      Loading…
    </p>

    <div v-else-if="error" class="alert alert-error">
      <span>The API did not answer: {{ error }}</span>
    </div>

    <p v-else-if="personId === ''" class="opacity-70">Pick your name to see your next thing.</p>

    <template v-else-if="view && next">
      <article class="card border-2 border-primary bg-base-100 shadow-sm">
        <div class="card-body gap-3">
          <template v-if="next.kind === 'continue' && next.assignment.kind === 'rework'">
            <p class="text-xs font-semibold uppercase tracking-wide text-error">Rework first</p>
            <h3 class="text-2xl font-semibold">Repair {{ next.assignment.piece }}</h3>
            <p class="opacity-80">
              {{ next.assignment.foundBy }} found a defect made at
              {{ next.assignment.stationName }}: {{ next.assignment.description }}. The Piece stays
              where it is: go and repair it there.
            </p>
            <div class="card-actions">
              <button class="btn btn-primary" :disabled="busy" @click="run(doing(next))">
                Repaired
              </button>
            </div>
          </template>

          <template v-else-if="next.kind === 'continue'">
            <p class="text-xs font-semibold uppercase tracking-wide opacity-60">In your hands</p>
            <h3 class="text-2xl font-semibold">Transform {{ next.assignment.piece }}</h3>
            <p class="opacity-80">
              At {{ next.assignment.stationName }}. Finish it before anything else.
            </p>
            <div class="card-actions">
              <button class="btn btn-primary" :disabled="busy" @click="run(doing(next))">
                Finish: put it in a Blue Bin
              </button>
            </div>
          </template>

          <template v-else-if="next.kind === 'take_rework'">
            <p class="text-xs font-semibold uppercase tracking-wide text-error">Rework first</p>
            <h3 class="text-2xl font-semibold">Take the Rework on {{ next.piece }}</h3>
            <p class="opacity-80">Nobody of {{ next.stationName }} repairs it yet.</p>
            <div class="card-actions">
              <button class="btn btn-primary" :disabled="busy" @click="run(doing(next))">
                Take it
              </button>
            </div>
          </template>

          <template v-else-if="next.kind === 'take_kanban'">
            <p class="text-xs font-semibold uppercase tracking-wide opacity-60">
              Your hands are free
            </p>
            <h3 class="text-2xl font-semibold">Pull the next Piece at {{ next.stationName }}</h3>
            <p class="opacity-80">
              A Kanban waits there, and a Piece waits upstream. It is your Work Station nearest to
              production.
            </p>
            <div class="card-actions">
              <button class="btn btn-primary" :disabled="busy" @click="run(doing(next))">
                Pull a Piece
              </button>
            </div>
          </template>

          <template v-else-if="next.kind === 'help_downstream'">
            <p class="text-xs font-semibold uppercase tracking-wide opacity-60">
              No Kanban for you
            </p>
            <h3 class="text-2xl font-semibold">Help Downstream at {{ next.stationName }}</h3>
            <p class="opacity-80">
              It holds up the flow: {{ next.because }}. Do not start a new Piece.
            </p>
          </template>

          <template v-else>
            <p class="text-xs font-semibold uppercase tracking-wide opacity-60">
              No Kanban for you
            </p>
            <h3 class="text-2xl font-semibold">Wait</h3>
            <p class="opacity-80">
              Nothing downstream asks for a Piece, and nothing downstream holds up the flow.
              Starting a Piece now would be a Deviation.
            </p>
          </template>
        </div>
      </article>

      <div v-if="view.assignments.length > 0" class="mt-6">
        <h3 class="text-xs uppercase tracking-wide opacity-60">My Assignments</h3>
        <ul class="mt-2 space-y-2">
          <li
            v-for="one in view.assignments"
            :key="`${one.kind}-${one.id}`"
            class="flex flex-wrap items-center gap-2 rounded border border-base-300 bg-base-100 px-3 py-2 text-sm"
          >
            <span class="font-medium" :class="one.active ? '' : 'opacity-50'">
              {{ one.kind === "rework" ? "Repair" : "Transform" }} {{ one.piece }}
            </span>
            <span class="opacity-60">· {{ one.stationName }}</span>
            <span v-if="one.active" class="badge badge-sm badge-primary">active</span>
            <span v-else class="badge badge-sm badge-ghost">paused</span>
            <select
              v-if="handOverTo(one).length > 0"
              class="select select-bordered select-xs ml-auto w-36"
              :disabled="busy"
              title="Hand this Assignment to another Person of the Work Station"
              @change="handOver(one, $event)"
            >
              <option value="" selected>Hand over to…</option>
              <option v-for="other in handOverTo(one)" :key="other.id" :value="other.id">
                {{ other.name }}
              </option>
            </select>
          </li>
        </ul>
        <p v-if="waiting.length > 0" class="mt-1 text-xs opacity-60">
          A paused Assignment comes back on its own once your hands are free.
        </p>
      </div>

      <div class="mt-6 grid gap-4 sm:grid-cols-2">
        <section
          v-for="list in view.priorityLists"
          :key="list.station"
          class="rounded border border-base-300 bg-base-100 p-3"
        >
          <h3 class="font-semibold">{{ list.name }}</h3>
          <p class="text-xs uppercase tracking-wide opacity-60">Priority List</p>
          <ol v-if="list.items.length > 0" class="mt-2 list-decimal space-y-1 pl-5 text-sm">
            <li v-for="item in list.items" :key="item.id">
              <template v-if="item.kind === 'rework'">
                <span class="font-medium text-error">Rework</span> {{ item.piece }}
                <span class="opacity-60">
                  · {{ item.assignee ? `${item.assignee} repairs` : "nobody repairs it yet" }}
                </span>
              </template>
              <template v-else>
                <span class="font-medium">Kanban</span>
                <span class="opacity-60"> · since {{ since(item.since) }}</span>
              </template>
            </li>
          </ol>
          <p v-else class="mt-2 text-sm opacity-60">Nothing: no Rework, no Kanban.</p>
        </section>
      </div>
    </template>

    <DeviationDialog
      v-if="pending"
      :message="pending.message"
      :busy="busy"
      @confirm="recordDeviation"
      @cancel="pending = null"
    />
  </section>
</template>
