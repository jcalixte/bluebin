<script setup lang="ts">
import { computed, ref, watch } from "vue"
import { lineId, workspaceOwner } from "../api"
import AndonAlert from "../components/AndonAlert.vue"
import AnimatedCount from "../components/AnimatedCount.vue"
import DeviationDialog from "../components/DeviationDialog.vue"
import ErrorToast from "../components/ErrorToast.vue"
import RaiseReworkDialog from "../components/RaiseReworkDialog.vue"
import { useFlowRunner } from "../composables/useFlowRunner"
import { useNextThing } from "../composables/useNextThing"
import { useWorkspaces } from "../composables/useWorkspaces"
import type { Assignment, FlowConfirm, NextThing, PriorityList, WorkStation } from "../types"

/** Team Members differ from one Line to the next, and Line ids from one Workspace to the next. */
const storageKey = `bluebin.teamMember.${workspaceOwner ? `${workspaceOwner}/` : ""}${lineId}`
const teamMemberId = ref(
  new URLSearchParams(location.search).get("teamMember") ?? localStorage.getItem(storageKey) ?? "",
)

const { current, canActAs, ownWorkOnly: pinned } = useWorkspaces()

const acting = computed(() => canActAs(teamMemberId.value))
watch(
  () => current.value?.teamMember,
  (own) => {
    if (own && (pinned.value || teamMemberId.value === "")) teamMemberId.value = own
  },
  { immediate: true },
)

watch(teamMemberId, (id) => {
  localStorage.setItem(storageKey, id)
  const url = new URL(location.href)
  url.searchParams.set("teamMember", id)
  history.replaceState(null, "", url)
})

const {
  teamMembers,
  view,
  error,
  loading,
  pull,
  finish,
  repair,
  helpTheRework,
  stopHelping,
  assign,
  raiseRework,
  loadStations,
  raiseAndon,
  closeAndon,
} = useNextThing(teamMemberId)

function stopped(station: string) {
  return (view.value?.andons ?? []).some((one) => one.kind === "stop" && one.station === station)
}
const { pending, actionError, busy, run, recordDeviation } = useFlowRunner()

const next = computed(() => view.value?.next ?? null)

const waiting = computed(() => (view.value?.assignments ?? []).filter((one) => !one.active))

function kanbans(list: PriorityList) {
  return list.items.filter((item) => item.kind === "kanban").length
}

const kanbanTotal = computed(() =>
  (view.value?.priorityLists ?? []).reduce((total, list) => total + kanbans(list), 0),
)

/** Past this many, the tokens would wrap; the number still tells the count. */
const maxTokens = 8

function authorize(count: number) {
  return count === 1 ? "Kanban authorizes a pull" : "Kanbans authorize a pull"
}

function handOverTo(assignment: Assignment) {
  return (
    view.value?.priorityLists
      .find((list) => list.station === assignment.station)
      ?.teamMembers.filter((one) => one.id !== teamMemberId.value && canActAs(one.id)) ?? []
  )
}

function handOver(assignment: Assignment, event: Event) {
  const teamMember = (event.target as HTMLSelectElement).value
  if (teamMember !== "") {
    void run(() => assign(assignment.kind, assignment.id, teamMember))
  }
}

const raising = ref<{ assignment: Assignment; stations: WorkStation[] } | null>(null)

function openRework(assignment: Assignment) {
  void run(async () => {
    raising.value = { assignment, stations: await loadStations() }
    return null
  })
}

function recordRework(madeBy: string, description: string) {
  const asked = raising.value?.assignment
  if (!asked) {
    return
  }
  raising.value = null
  void run(() => raiseRework(asked.station, asked.id, madeBy, description))
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
        return assign("rework", now.rework, teamMemberId.value)
      case "take_kanban":
        return pull(now.station, reason)
      case "help_the_rework":
        return helpTheRework(now.rework)
      case "helping":
        return stopHelping()
      default:
        return Promise.resolve(null)
    }
  }
}

/** The pull rules, in the order the API tries them. The first that applies is the next thing. */
const rules = [
  { kind: "helping", label: "Stay with the Rework you help" },
  { kind: "continue", label: "Finish what is in your hands" },
  { kind: "take_rework", label: "Take a Rework nobody repairs" },
  { kind: "take_kanban", label: "Pull at a Kanban, nearest to Deployment first" },
  { kind: "help_the_rework", label: "Help the Rework your Work Station found or made" },
  { kind: "help_downstream", label: "Help Downstream where the flow is held up" },
  { kind: "wait", label: "Wait" },
] as const

const ruleIndex = computed(() => rules.findIndex((rule) => rule.kind === next.value?.kind))

const focus = computed<{ title: string; action: string | null }>(() => {
  const now = next.value
  switch (now?.kind) {
    case "continue":
      return now.assignment.kind === "rework"
        ? {
            title: `Repair ${now.assignment.piece}`,
            action: "Repaired",
          }
        : {
            title: `Transform ${now.assignment.piece}`,
            action: "Finish: put it in a Blue Bin",
          }
    case "take_rework":
      return {
        title: `Take the Rework on ${now.piece}`,
        action: "Take it",
      }
    case "take_kanban":
      return {
        title: `Pull the next Piece at ${now.stationName}`,
        action: "Pull a Piece",
      }
    case "helping":
      return {
        title: `Help ${now.assignee} on ${now.piece}`,
        action: "Stop helping",
      }
    case "help_the_rework":
      return {
        title: `Help ${now.assignee} on ${now.piece}`,
        action: "Help",
      }
    case "help_downstream":
      return {
        title: `Help Downstream at ${now.stationName}`,
        action: null,
      }
    default:
      return { title: "Wait", action: null }
  }
})

function since(at: string) {
  return new Date(at).toLocaleString(undefined, {
    weekday: "short",
    hour: "2-digit",
    minute: "2-digit",
  })
}
</script>

<template>
  <section class="mx-auto max-w-6xl">
    <header class="mb-6 flex flex-wrap items-end justify-between gap-x-10 gap-y-4">
      <div>
        <h2 class="text-xl font-semibold">My next thing</h2>
        <p class="text-sm opacity-70">One thing to do now, chosen by the pull rules.</p>
      </div>
      <label v-if="!pinned" class="flex items-center gap-3">
        <span class="text-sm font-semibold opacity-70">I am</span>
        <select v-model="teamMemberId" class="select select-bordered h-11 w-auto min-w-56">
          <option value="" disabled>Pick your name</option>
          <option v-for="one in teamMembers" :key="one.id" :value="one.id">
            {{ one.name }} · {{ one.stations.join(", ") }}
          </option>
        </select>
      </label>
    </header>

    <ErrorToast v-model="actionError" />

    <p v-if="loading && !view && !error" class="flex items-center gap-3 opacity-70">
      <span class="loading loading-spinner loading-sm" />
      Loading…
    </p>

    <div v-else-if="error" role="alert" class="alert alert-error">
      <span>The API did not answer: {{ error }}</span>
    </div>

    <p
      v-else-if="teamMemberId === ''"
      class="rounded-box border border-dashed border-base-content/30 p-8 text-center opacity-70"
    >
      Pick your name above to see your next thing.
    </p>

    <template v-else-if="view && next">
      <AndonAlert
        :andons="view.andons"
        :team-member-id="acting ? teamMemberId : undefined"
        :busy="busy"
        @close="(station) => run(() => closeAndon(station))"
      />

      <div class="grid gap-8 lg:grid-cols-[minmax(0,1fr)_18rem]">
        <article class="card border border-base-300 bg-base-100" aria-labelledby="next-thing-title">
          <div class="card-body p-5 sm:p-6">
            <div class="flex min-w-0 flex-col gap-3">
              <h3 id="next-thing-title" class="text-3xl font-semibold leading-tight">
                {{ focus.title }}
              </h3>

              <template v-if="next.kind === 'continue' && next.assignment.kind === 'rework'">
                <blockquote class="text-base">
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
                Rework comes first: nobody of {{ next.stationName }} repairs it yet.
              </p>
              <p v-else-if="next.kind === 'take_kanban'" class="opacity-80">
                Your hands are free. A Kanban waits there, and a Piece waits upstream. It is your
                Work Station nearest to Deployment.
              </p>
              <p v-else-if="next.kind === 'helping'" class="opacity-80">
                At {{ next.stationName }}, with {{ next.assignee }}: reproduce the defect, write the
                failing test, check the repair. Your help ends when the Rework is repaired.
              </p>
              <p v-else-if="next.kind === 'help_the_rework'" class="opacity-80">
                {{ next.assignee }} repairs it at {{ next.stationName }}, where the defect was
                found. Join: reproduce the defect, write the failing test, check the repair. Do not
                start a new Piece.
              </p>
              <p v-else-if="next.kind === 'help_downstream'" class="opacity-80">
                It holds up the flow: {{ next.because }}. Do not start a new Piece.
              </p>
              <template v-else>
                <p class="opacity-80">
                  Nothing downstream asks for a Piece, and nothing downstream holds up the flow.
                  Starting a Piece now would be a Deviation.
                </p>
                <div>
                  <p class="text-sm font-semibold">Use the wait to improve the flow</p>
                  <ul class="mt-2 space-y-1.5 text-sm">
                    <li>
                      <span class="font-medium">5S</span>
                      <span class="opacity-80">
                        · sort, set in order and clean your Work Station: tools, branches, docs.
                      </span>
                    </li>
                    <li>
                      <span class="font-medium">Problem solving</span>
                      <span class="opacity-80">
                        · find the root cause of a recent Rework or Andon.
                      </span>
                    </li>
                    <li>
                      <span class="font-medium">Kaizen</span>
                      <span class="opacity-80">
                        · improve one step of your method, so the next Piece flows faster or with
                        fewer defects.
                      </span>
                    </li>
                  </ul>
                </div>
              </template>

              <div v-if="focus.action && acting" class="mt-auto flex flex-wrap gap-3 pt-2">
                <button
                  class="btn btn-primary btn-lg w-full sm:w-auto"
                  :disabled="busy"
                  @click="run(doing(next))"
                >
                  <span v-if="busy" class="loading loading-spinner loading-sm" aria-hidden="true" />
                  {{ focus.action }}
                </button>
                <button
                  v-if="next.kind === 'continue' && next.assignment.kind === 'piece'"
                  class="btn btn-ghost btn-lg w-full sm:w-auto"
                  :disabled="busy"
                  title="Found a defect? Name the Work Station that made it"
                  @click="openRework(next.assignment)"
                >
                  Raise a Rework
                </button>
              </div>
            </div>
          </div>
        </article>

        <aside
          aria-labelledby="pull-rules-title"
          class="lg:col-start-2 lg:row-span-2 lg:row-start-1"
        >
          <div class="rounded-box border border-base-300 bg-base-100 p-5 lg:sticky lg:top-6">
            <h3 id="pull-rules-title" class="text-sm font-semibold opacity-70">Pull rules</h3>
            <p class="mt-1 text-xs opacity-70">The first rule that applies is your next thing.</p>
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
            <a href="/about#rules" class="link mt-4 inline-block text-sm">Why these rules</a>
          </div>
        </aside>

        <div class="grid content-start gap-8 xl:grid-cols-2">
          <section aria-labelledby="assignments-title">
            <h3 id="assignments-title" class="text-sm font-semibold opacity-70">My Assignments</h3>
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
                  :aria-label="`Hand ${one.piece} over to another Team Member`"
                  title="Hand this Assignment to another Team Member of the Work Station"
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
            <h3 id="stations-title" class="text-sm font-semibold opacity-70">
              My Work Stations, nearest to Deployment first
            </h3>
            <div
              class="mt-3 flex items-center gap-4 rounded-box border border-base-300 bg-base-100 px-4 py-3"
            >
              <span
                class="text-3xl font-semibold leading-none tabular-nums"
                :class="kanbanTotal > 0 ? 'text-primary' : 'opacity-70'"
              >
                <AnimatedCount :value="kanbanTotal" />
              </span>
              <p class="min-w-0 text-sm leading-snug">
                <span class="font-medium">{{ authorize(kanbanTotal) }}</span>
                <span class="block text-xs opacity-70">
                  {{
                    kanbanTotal > 0
                      ? "At all your Work Stations. Pull at the one nearest to Deployment first."
                      : "Pulling a Piece now would be a Deviation."
                  }}
                </span>
              </p>
            </div>
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
                    <p class="mt-1 flex flex-wrap items-center gap-x-2 gap-y-1 text-xs">
                      <span class="opacity-70">Priority List ·</span>
                      <span
                        v-if="kanbans(list) > 0"
                        class="flex items-center gap-0.5"
                        aria-hidden="true"
                      >
                        <span
                          v-for="token in Math.min(kanbans(list), maxTokens)"
                          :key="token"
                          class="h-3.5 w-2.5 rounded-[2px] border border-primary bg-primary/15"
                        />
                        <span v-if="kanbans(list) > maxTokens" class="ml-0.5 opacity-70">+</span>
                      </span>
                      <span
                        class="tabular-nums"
                        :class="kanbans(list) > 0 ? 'font-medium' : 'opacity-70'"
                      >
                        <AnimatedCount :value="kanbans(list)" />
                        {{ kanbans(list) === 1 ? "Kanban" : "Kanbans" }}
                      </span>
                    </p>
                  </div>
                  <span
                    v-if="stopped(list.station)"
                    class="badge badge-error shrink-0 gap-1.5 font-semibold"
                  >
                    <span class="size-2 rounded-full bg-current" aria-hidden="true" />
                    Stopped
                  </span>
                  <button
                    v-else-if="acting"
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
                    class="flex items-baseline gap-2.5 py-1.5"
                  >
                    <span class="w-4 shrink-0 text-xs tabular-nums opacity-70">{{
                      index + 1
                    }}</span>
                    <span v-if="item.kind === 'rework'" class="min-w-0">
                      <span class="font-medium text-error">Rework</span> {{ item.piece }}
                      <span class="block text-xs opacity-70">
                        {{
                          item.assignee ? `${item.assignee} repairs it` : "Nobody repairs it yet"
                        }}
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
      </div>
    </template>

    <RaiseReworkDialog
      v-if="raising"
      :station="raising.assignment.station"
      :reference="raising.assignment.piece"
      :stations="raising.stations"
      :busy="busy"
      @raise="recordRework"
      @close="raising = null"
    />

    <DeviationDialog
      v-if="pending"
      :message="pending.message"
      :busy="busy"
      @confirm="recordDeviation"
      @cancel="pending = null"
    />
  </section>
</template>
