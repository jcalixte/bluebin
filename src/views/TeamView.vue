<script setup lang="ts">
import { computed } from "vue"
import { pageUrl } from "../api"
import { useLine } from "../composables/useLine"
import { useWorkspaces } from "../composables/useWorkspaces"
import type { Rework, WorkStation } from "../types"

const { line, error, loading } = useLine()
const { current, ownWorkOnly } = useWorkspaces()

/** My next thing of a Team Member, when who looks may open it. */
function nextUrl(teamMember: string): string | null {
  if (ownWorkOnly.value && teamMember !== current.value?.teamMember) return null
  return `${pageUrl("/next")}?teamMember=${encodeURIComponent(teamMember)}`
}

/** Opens the tab in this page, as the header tabs do: App.vue follows `popstate`. */
function openNext(url: string) {
  history.pushState(null, "", url)
  dispatchEvent(new PopStateEvent("popstate"))
}

type Card = {
  key: string
  kind: "piece" | "rework"
  piece: string
  stationName: string
  active: boolean
  stale: boolean
  /** Rework only: the defect, in one line. */
  description?: string
}

type Row = {
  id: string
  name: string
  stations: string[]
  cards: Card[]
  helping: { piece: string; assignee: string | null } | null
}

const stations = computed<WorkStation[]>(() =>
  [...(line.value?.stations ?? [])].sort((a, b) => a.position - b.position),
)

const stale = computed(
  () => new Set((line.value?.stale ?? []).map((one) => `${one.kind}:${one.id}`)),
)

function reworkCard(station: WorkStation, item: Rework): Card {
  return {
    key: `rework:${item.id}`,
    kind: "rework",
    piece: item.piece,
    stationName: station.name,
    active: item.started,
    stale: stale.value.has(`rework:${item.id}`),
    description: item.description,
  }
}

/**
 * Each Team Member once, in Line order, with their Assignments ordered as in My next thing:
 * Rework first, then the active Piece, then nearest to Deployment.
 */
const rows = computed<Row[]>(() => {
  const byId = new Map<string, Row>()
  for (const station of stations.value) {
    for (const member of station.teamMembers) {
      const row = byId.get(member.id) ?? {
        id: member.id,
        name: member.name,
        stations: [],
        cards: [],
        helping: null,
      }
      row.stations.push(station.name)
      byId.set(member.id, row)
    }
  }
  const reworks = new Map<string, Card[]>()
  const pieces = new Map<string, Card[]>()
  const push = (into: Map<string, Card[]>, id: string, card: Card) =>
    into.set(id, [...(into.get(id) ?? []), card])
  for (const station of [...stations.value].reverse()) {
    for (const item of station.rework) {
      if (item.assigneeId) push(reworks, item.assigneeId, reworkCard(station, item))
      for (const helper of item.helpers) {
        const row = byId.get(helper.id)
        if (row) row.helping = { piece: item.piece, assignee: item.assignee }
      }
    }
    for (const item of station.inProgress) {
      if (!item.teamMemberId) continue
      push(pieces, item.teamMemberId, {
        key: `piece:${item.id}`,
        kind: "piece",
        piece: item.piece,
        stationName: station.name,
        active: !item.paused,
        stale: stale.value.has(`piece:${item.id}`),
      })
    }
  }
  const activeFirst = (a: Card, b: Card) => Number(b.active) - Number(a.active)
  for (const row of byId.values()) {
    row.cards = [
      ...(reworks.get(row.id) ?? []).sort(activeFirst),
      ...(pieces.get(row.id) ?? []).sort(activeFirst),
    ]
  }
  return [...byId.values()]
})

/** Open Rework and Pieces in the Line that no Team Member holds. */
const nobody = computed<Card[]>(() =>
  [...stations.value].reverse().flatMap((station) => [
    ...station.rework
      .filter((item) => !item.assigneeId)
      .map((item) => ({ ...reworkCard(station, item), active: false })),
    ...station.inProgress
      .filter((item) => !item.teamMemberId)
      .map((item): Card => ({
        key: `piece:${item.id}`,
        kind: "piece",
        piece: item.piece,
        stationName: station.name,
        active: false,
        stale: false,
      })),
  ]),
)

const total = computed(() => rows.value.reduce((sum, row) => sum + row.cards.length, 0))
const paused = computed(() =>
  rows.value.reduce((sum, row) => sum + row.cards.filter((card) => !card.active).length, 0),
)
const free = computed(
  () => rows.value.filter((row) => row.cards.length === 0 && !row.helping).length,
)

function state(card: Card) {
  if (card.kind === "rework") return card.active ? "Repairs" : "Rework waits"
  return card.active ? "In hand" : "Paused"
}
</script>

<template>
  <section>
    <header class="mb-6 flex flex-wrap items-end justify-between gap-x-10 gap-y-4">
      <div class="max-w-2xl">
        <h2 class="text-xl font-semibold">Team</h2>
        <p class="text-sm opacity-70">
          The Assignments of each Team Member. A long row shows work that piles up on one person: a
          Team Member of the same Work Station can take it over from the Line.
        </p>
      </div>
      <dl v-if="line && rows.length > 0" class="flex flex-wrap gap-x-8 gap-y-3">
        <div>
          <dt class="text-xs font-semibold uppercase tracking-wide opacity-70">Assignments</dt>
          <dd class="text-2xl font-semibold tabular-nums">{{ total }}</dd>
        </div>
        <div>
          <dt class="text-xs font-semibold uppercase tracking-wide opacity-70">Paused</dt>
          <dd class="text-2xl font-semibold tabular-nums">{{ paused }}</dd>
        </div>
        <div>
          <dt class="text-xs font-semibold uppercase tracking-wide opacity-70">Free</dt>
          <dd class="text-2xl font-semibold tabular-nums">
            {{ free }}
            <span class="text-sm font-normal opacity-70">of {{ rows.length }} Team Members</span>
          </dd>
        </div>
      </dl>
    </header>

    <p v-if="loading && !line" class="flex items-center gap-3 opacity-70">
      <span class="loading loading-spinner loading-sm" />
      Loading the Team…
    </p>
    <div v-else-if="error" role="alert" class="alert alert-error">
      <span>The API did not answer: {{ error }}</span>
    </div>
    <p
      v-else-if="rows.length === 0"
      class="rounded-box border border-dashed border-base-content/30 p-8 text-center opacity-70"
    >
      No Team Member yet. The owner adds them in Design.
    </p>

    <ul
      v-else
      class="divide-y divide-base-300 rounded-box border border-base-300 bg-base-100 shadow-sm"
    >
      <li
        v-for="row in rows"
        :key="row.id"
        class="grid gap-3 p-4 md:grid-cols-[13rem_3.5rem_minmax(0,1fr)] md:items-start md:gap-5"
      >
        <div class="flex items-baseline justify-between gap-3 md:block">
          <div class="min-w-0">
            <h3 class="truncate font-semibold">
              <a
                v-if="nextUrl(row.id)"
                :href="nextUrl(row.id)!"
                class="link link-hover rounded-field"
                :title="`Open My next thing of ${row.name}`"
                @click.exact.prevent="openNext(nextUrl(row.id)!)"
              >
                {{ row.name }}
              </a>
              <template v-else>{{ row.name }}</template>
            </h3>
            <p class="truncate text-xs opacity-70">{{ row.stations.join(" · ") }}</p>
          </div>
          <p class="shrink-0 text-sm md:hidden">
            <span class="text-2xl font-semibold tabular-nums">{{ row.cards.length }}</span>
            <span class="opacity-70">
              {{ row.cards.length === 1 ? "Assignment" : "Assignments" }}</span
            >
          </p>
        </div>
        <p
          class="hidden text-right text-3xl leading-none font-semibold tabular-nums md:block"
          :class="row.cards.length === 0 ? 'opacity-40' : ''"
        >
          {{ row.cards.length }}
          <span class="sr-only">{{ row.cards.length === 1 ? "Assignment" : "Assignments" }}</span>
        </p>

        <ol class="flex flex-wrap gap-2" :aria-label="`Assignments of ${row.name}`">
          <li
            v-if="row.helping"
            class="flex w-36 flex-col rounded-field border border-dashed border-base-content/50 px-3 py-2"
          >
            <span class="text-xs font-semibold uppercase tracking-wide opacity-70">Helps</span>
            <span class="font-semibold">{{ row.helping.piece }}</span>
            <span class="truncate text-xs opacity-70">
              {{ row.helping.assignee ? `with ${row.helping.assignee}` : "the Rework" }}
            </span>
          </li>
          <li
            v-for="card in row.cards"
            :key="card.key"
            class="flex w-36 flex-col rounded-field border px-3 py-2"
            :class="[
              card.active
                ? 'border-primary bg-primary text-primary-content'
                : 'border-base-300 bg-base-200/60',
              card.kind === 'rework' ? 'border-l-4 border-l-error' : '',
            ]"
            :title="card.description"
          >
            <span class="flex items-center justify-between gap-1">
              <span
                class="text-xs font-semibold uppercase tracking-wide"
                :class="card.active ? '' : 'opacity-70'"
              >
                {{ state(card) }}
              </span>
              <span
                v-if="card.stale"
                class="badge badge-xs badge-warning"
                title="No event for more than one working day: is it still in hand?"
              >
                stale
              </span>
            </span>
            <span class="font-semibold" :class="card.active ? '' : 'italic'">{{ card.piece }}</span>
            <span class="truncate text-xs" :class="card.active ? 'opacity-90' : 'opacity-70'">
              {{ card.stationName }}
            </span>
          </li>
          <li
            v-if="row.cards.length === 0 && !row.helping"
            class="flex min-h-16 items-center rounded-field border border-dashed border-base-300 px-3 py-2 text-sm opacity-70"
          >
            No Assignment
          </li>
        </ol>
      </li>

      <li
        v-if="nobody.length > 0"
        class="grid gap-3 bg-base-200/40 p-4 md:grid-cols-[13rem_3.5rem_minmax(0,1fr)] md:items-start md:gap-5"
      >
        <div class="flex items-baseline justify-between gap-3 md:block">
          <div>
            <h3 class="font-semibold">Nobody</h3>
            <p class="text-xs opacity-70">In the Line, with no Team Member</p>
          </div>
          <p class="shrink-0 text-2xl font-semibold tabular-nums md:hidden">{{ nobody.length }}</p>
        </div>
        <p class="hidden text-right text-3xl leading-none font-semibold tabular-nums md:block">
          {{ nobody.length }}
          <span class="sr-only">with no Team Member</span>
        </p>
        <ol class="flex flex-wrap gap-2" aria-label="In the Line with no Team Member">
          <li
            v-for="card in nobody"
            :key="card.key"
            class="flex w-36 flex-col rounded-field border border-base-300 bg-base-100 px-3 py-2"
            :class="card.kind === 'rework' ? 'border-l-4 border-l-error' : ''"
            :title="card.description"
          >
            <span class="text-xs font-semibold uppercase tracking-wide opacity-70">
              {{ card.kind === "rework" ? "Rework waits" : "Unassigned" }}
            </span>
            <span class="font-semibold">{{ card.piece }}</span>
            <span class="truncate text-xs opacity-70">{{ card.stationName }}</span>
          </li>
        </ol>
      </li>
    </ul>
  </section>
</template>
