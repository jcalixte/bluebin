<script setup lang="ts">
import { computed, ref, watch } from "vue"
import AndonAlert from "../components/AndonAlert.vue"
import DeviationDialog from "../components/DeviationDialog.vue"
import { useFlowRunner } from "../composables/useFlowRunner"
import { useNextThing } from "../composables/useNextThing"
import type { Assignment, FlowConfirm, NextThing } from "../types"

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

const { people, view, error, loading, pull, finish, repair, assign, raiseAndon, closeAndon } =
  useNextThing(personId)

function stopped(station: string) {
  return (view.value?.andons ?? []).some((one) => one.kind === "stop" && one.station === station)
}
const { pending, actionError, busy, run, recordDeviation } = useFlowRunner()

const next = computed(() => view.value?.next ?? null)

const waiting = computed(() => (view.value?.assignments ?? []).filter((one) => !one.active))

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

/** Captures `now` so a Deviation confirmed later reruns this action, not
 *  whatever is next by then. */
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

/** The pull rules, in the order the API tries them. The first that applies is the next thing. */
const rules = [
  { kind: "continue", label: "Finish what is in your hands" },
  { kind: "take_rework", label: "Take a Rework nobody repairs" },
  { kind: "take_kanban", label: "Pull at a Kanban, nearest to production first" },
  { kind: "help_downstream", label: "Help Downstream where the flow is held up" },
  { kind: "wait", label: "Wait" },
] as const

const ruleIndex = computed(() => rules.findIndex((rule) => rule.kind === next.value?.kind))

type Tone = "error" | "primary" | "warning" | "neutral"

/** What the hero card says. Rework is a defect, so it is the only red. */
const focus = computed<{ tone: Tone; eyebrow: string; title: string; action: string | null }>(
  () => {
    const now = next.value
    switch (now?.kind) {
      case "continue":
        return now.assignment.kind === "rework"
          ? {
              tone: "error",
              eyebrow: "Rework first",
              title: `Repair ${now.assignment.piece}`,
              action: "Repaired",
            }
          : {
              tone: "primary",
              eyebrow: "In your hands",
              title: `Transform ${now.assignment.piece}`,
              action: "Finish: put it in a Blue Bin",
            }
      case "take_rework":
        return {
          tone: "error",
          eyebrow: "Rework first",
          title: `Take the Rework on ${now.piece}`,
          action: "Take it",
        }
      case "take_kanban":
        return {
          tone: "primary",
          eyebrow: "Your hands are free",
          title: `Pull the next Piece at ${now.stationName}`,
          action: "Pull a Piece",
        }
      case "help_downstream":
        return {
          tone: "warning",
          eyebrow: "No Kanban for you",
          title: `Help Downstream at ${now.stationName}`,
          action: null,
        }
      default:
        return { tone: "neutral", eyebrow: "No Kanban for you", title: "Wait", action: null }
    }
  },
)

const toneBorder: Record<Tone, string> = {
  error: "border-error",
  primary: "border-primary",
  warning: "border-warning",
  neutral: "border-base-content/30",
}

const toneText: Record<Tone, string> = {
  error: "text-error",
  primary: "text-primary",
  warning: "text-warning-ink",
  neutral: "opacity-70",
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
  <section class="mx-auto max-w-5xl">
    <header class="mb-6 flex flex-wrap items-end justify-between gap-x-10 gap-y-4">
      <div>
        <h2 class="text-xl font-semibold">My next thing</h2>
        <p class="text-sm opacity-70">
          One thing to do now, from the pull rules. Nobody pushes it.
        </p>
      </div>
      <label class="flex items-center gap-3">
        <span class="text-xs font-semibold uppercase tracking-wide opacity-70">I am</span>
        <select v-model="personId" class="select select-bordered h-11 w-auto min-w-56">
          <option value="" disabled>Pick your name</option>
          <option v-for="one in people" :key="one.id" :value="one.id">
            {{ one.name }} · {{ one.stations.join(", ") }}
          </option>
        </select>
      </label>
    </header>

    <div v-if="actionError" role="alert" class="alert alert-warning mb-4">
      <span>{{ actionError }}</span>
    </div>

    <p v-if="loading && !view && !error" class="flex items-center gap-3 opacity-70">
      <span class="loading loading-spinner loading-sm" />
      Loading…
    </p>

    <div v-else-if="error" role="alert" class="alert alert-error">
      <span>The API did not answer: {{ error }}</span>
    </div>

    <p
      v-else-if="personId === ''"
      class="rounded-box border border-dashed border-base-content/30 p-8 text-center opacity-70"
    >
      Pick your name above to see your next thing.
    </p>

    <template v-else-if="view && next">
      <AndonAlert
        :andons="view.andons"
        :person-id="personId"
        :busy="busy"
        @close="(station) => run(() => closeAndon(station))"
      />

      <article
        class="card overflow-hidden border border-l-8 border-base-300 bg-base-100 shadow-sm"
        :class="toneBorder[focus.tone]"
        aria-labelledby="next-thing-title"
      >
        <div class="card-body grid gap-6 p-5 sm:p-6 md:grid-cols-[minmax(0,1fr)_16rem]">
          <div class="flex min-w-0 flex-col gap-3">
            <p class="text-xs font-semibold uppercase tracking-wide" :class="toneText[focus.tone]">
              {{ focus.eyebrow }}
            </p>
            <h3 id="next-thing-title" class="text-3xl font-semibold leading-tight">
              {{ focus.title }}
            </h3>

            <template v-if="next.kind === 'continue' && next.assignment.kind === 'rework'">
              <blockquote
                class="rounded-r-box border-l-4 border-error bg-error/5 px-4 py-3 text-base"
              >
                {{ next.assignment.description }}
                <footer class="mt-1 text-sm opacity-70">
                  Found by {{ next.assignment.foundBy }} · made at
                  {{ next.assignment.stationName }}
                </footer>
              </blockquote>
              <p class="opacity-80">The Piece stays where it is: go and repair it there.</p>
            </template>
            <p v-else-if="next.kind === 'continue'" class="opacity-80">
              At {{ next.assignment.stationName }}. Finish it before anything else.
            </p>
            <p v-else-if="next.kind === 'take_rework'" class="opacity-80">
              Nobody of {{ next.stationName }} repairs it yet.
            </p>
            <p v-else-if="next.kind === 'take_kanban'" class="opacity-80">
              A Kanban waits there, and a Piece waits upstream. It is your Work Station nearest to
              production.
            </p>
            <p v-else-if="next.kind === 'help_downstream'" class="opacity-80">
              It holds up the flow: {{ next.because }}. Do not start a new Piece.
            </p>
            <p v-else class="opacity-80">
              Nothing downstream asks for a Piece, and nothing downstream holds up the flow.
              Starting a Piece now would be a Deviation.
            </p>

            <div v-if="focus.action" class="mt-auto pt-2">
              <button
                class="btn btn-primary btn-lg w-full sm:w-auto"
                :disabled="busy"
                @click="run(doing(next))"
              >
                <span v-if="busy" class="loading loading-spinner loading-sm" aria-hidden="true" />
                {{ focus.action }}
              </button>
            </div>
          </div>

          <aside
            aria-label="Why this thing"
            class="border-t border-base-300 pt-4 md:border-t-0 md:border-l md:pt-0 md:pl-6"
          >
            <p class="text-xs font-semibold uppercase tracking-wide opacity-70">Pull rules</p>
            <ol class="mt-3 space-y-2.5 text-sm">
              <li
                v-for="(rule, index) in rules"
                :key="rule.kind"
                class="flex items-start gap-2.5"
                :class="index > ruleIndex ? 'opacity-50' : ''"
                :aria-current="index === ruleIndex ? 'step' : undefined"
              >
                <span
                  class="grid size-6 shrink-0 place-items-center rounded-full text-xs font-semibold tabular-nums"
                  :class="
                    index === ruleIndex
                      ? 'bg-primary text-primary-content'
                      : 'border border-base-content/30'
                  "
                  aria-hidden="true"
                >
                  {{ index + 1 }}
                </span>
                <span class="pt-0.5 leading-snug">
                  <span :class="index === ruleIndex ? 'font-semibold' : ''">{{ rule.label }}</span>
                  <span v-if="index < ruleIndex" class="block text-xs opacity-70">
                    Nothing for you
                  </span>
                  <span v-else-if="index === ruleIndex" class="block text-xs font-medium">
                    Applies now
                  </span>
                </span>
              </li>
            </ol>
          </aside>
        </div>
      </article>

      <div class="mt-8 grid gap-8 lg:grid-cols-2">
        <section aria-labelledby="assignments-title">
          <h3
            id="assignments-title"
            class="text-xs font-semibold uppercase tracking-wide opacity-70"
          >
            My Assignments
          </h3>
          <ul v-if="view.assignments.length > 0" class="mt-3 space-y-2">
            <li
              v-for="one in view.assignments"
              :key="`${one.kind}-${one.id}`"
              class="flex flex-wrap items-center gap-x-3 gap-y-2 rounded-box border border-base-300 bg-base-100 px-4 py-3 text-sm"
            >
              <span
                class="size-2.5 shrink-0 rounded-full"
                :class="one.active ? 'bg-primary' : 'border border-base-content/50'"
                aria-hidden="true"
              />
              <span class="min-w-0" :class="one.active ? '' : 'opacity-70'">
                <span class="font-medium">
                  {{ one.kind === "rework" ? "Repair" : "Transform" }} {{ one.piece }}
                </span>
                <span class="opacity-70"> · {{ one.stationName }}</span>
              </span>
              <span v-if="one.active" class="badge badge-sm badge-primary">In hand</span>
              <span v-else class="badge badge-sm badge-ghost">Paused</span>
              <select
                v-if="handOverTo(one).length > 0"
                class="select select-bordered select-sm ml-auto w-40"
                :disabled="busy"
                :aria-label="`Hand ${one.piece} over to another Person`"
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
          <p
            v-else
            class="mt-3 rounded-box border border-dashed border-base-content/30 px-4 py-3 text-sm opacity-70"
          >
            Your hands are free: no Assignment.
          </p>
          <p v-if="waiting.length > 0" class="mt-2 text-xs opacity-70">
            A paused Assignment comes back on its own once your hands are free.
          </p>
        </section>

        <section aria-labelledby="stations-title">
          <h3 id="stations-title" class="text-xs font-semibold uppercase tracking-wide opacity-70">
            My Work Stations, nearest to production first
          </h3>
          <div class="mt-3 grid gap-3">
            <article
              v-for="list in view.priorityLists"
              :key="list.station"
              class="rounded-box border bg-base-100 p-4"
              :class="stopped(list.station) ? 'border-2 border-error' : 'border-base-300'"
            >
              <header class="flex items-start justify-between gap-2">
                <div class="min-w-0">
                  <h4 class="font-semibold leading-tight">{{ list.name }}</h4>
                  <p class="mt-0.5 text-xs opacity-70">Priority List</p>
                </div>
                <span
                  v-if="stopped(list.station)"
                  class="badge badge-error shrink-0 gap-1.5 font-semibold"
                >
                  <span class="size-2 rounded-full bg-current" aria-hidden="true" />
                  Stopped
                </span>
                <button
                  v-else
                  class="btn btn-ghost btn-sm shrink-0 gap-1.5"
                  :disabled="busy"
                  title="Stop this Work Station and call its Team Leader"
                  @click="run(() => raiseAndon(list.station))"
                >
                  <span class="size-2 rounded-full bg-andon" aria-hidden="true" />
                  Andon
                </button>
              </header>
              <ol v-if="list.items.length > 0" class="mt-3 space-y-1.5 text-sm">
                <li
                  v-for="(item, index) in list.items"
                  :key="item.id"
                  class="flex items-baseline gap-2.5 rounded-r-box border-l-4 px-3 py-1.5"
                  :class="item.kind === 'rework' ? 'border-error bg-error/5' : 'border-base-300'"
                >
                  <span class="w-4 shrink-0 text-xs tabular-nums opacity-70">{{ index + 1 }}</span>
                  <span v-if="item.kind === 'rework'" class="min-w-0">
                    <span class="font-medium text-error">Rework</span> {{ item.piece }}
                    <span class="block text-xs opacity-70">
                      {{ item.assignee ? `${item.assignee} repairs it` : "Nobody repairs it yet" }}
                    </span>
                  </span>
                  <span v-else class="min-w-0">
                    <span class="font-medium">Kanban</span>
                    <span class="opacity-70"> · since {{ since(item.since) }}</span>
                  </span>
                </li>
              </ol>
              <p v-else class="mt-3 text-sm opacity-70">Nothing: no Rework, no Kanban.</p>
            </article>
          </div>
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
