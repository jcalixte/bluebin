<script setup lang="ts">
import { nextTick, onBeforeUnmount, onMounted, ref, watch } from "vue"
import type { FlowLink } from "../shape"

const props = defineProps<{
  container: HTMLElement | null
  links: FlowLink[]
  /** Kanbans of each column, by column index: they label the links into it. */
  kanbans?: Record<number, number>
  /** One arrow for each link, with no Kanban lane and no labels (Design). */
  simple?: boolean
}>()

const CORNER_RADIUS = 10
const LANE_OFFSET = 9
const LANE_END_GAP = 5
/** The height on a card where its links arrive and leave: its title row. */
const ANCHOR = 30
const TURN = 18
const BRANCH_LABEL_MAX = 14

type Card = { column: number; left: number; right: number; top: number }
type Lane = { d: string; kind: "piece" | "kanban" }
type Label = { x: number; y: number; text: string; kind: "piece" | "kanban" | "branch" }
type Mark = { x: number; y: number; kind: "split" | "assembly" }

const size = ref({ width: 0, height: 0 })
const lanes = ref<Lane[]>([])
const labels = ref<Label[]>([])
const marks = ref<Mark[]>([])

function elbow(sx: number, sy: number, ex: number, ey: number, trunk: number): string {
  if (Math.abs(ey - sy) < 1) return `M ${sx} ${sy} H ${ex}`
  const vertical = ey > sy ? 1 : -1
  const horizontal = ex > sx ? 1 : -1
  const radius = Math.min(
    CORNER_RADIUS,
    Math.abs(ey - sy) / 2,
    Math.abs(trunk - sx),
    Math.abs(ex - trunk),
  )
  return [
    `M ${sx} ${sy}`,
    `H ${trunk - horizontal * radius}`,
    `Q ${trunk} ${sy} ${trunk} ${sy + vertical * radius}`,
    `V ${ey - vertical * radius}`,
    `Q ${trunk} ${ey} ${trunk + horizontal * radius} ${ey}`,
    `H ${ex}`,
  ].join(" ")
}

function short(text: string) {
  return text.length > BRANCH_LABEL_MAX ? `${text.slice(0, BRANCH_LABEL_MAX - 1)}…` : text
}

function measure() {
  const root = props.container
  if (!root) return
  size.value = { width: root.offsetWidth, height: root.offsetHeight }

  const base = root.getBoundingClientRect()
  const cards = new Map<string, Card>()
  for (const card of root.querySelectorAll<HTMLElement>("[data-station]")) {
    const box = card.getBoundingClientRect()
    if (box.width === 0) continue
    cards.set(card.dataset.station ?? "", {
      column: Number(card.dataset.column ?? 0),
      left: box.left - base.left,
      right: box.right - base.left,
      top: box.top - base.top,
    })
  }

  const offset = props.simple ? 0 : LANE_OFFSET
  const nextLanes: Lane[] = []
  const nextLabels: Label[] = []
  const nextMarks = new Map<string, Mark>()
  const into = new Map<number, { x: number; top: number; bottom: number }>()
  for (const link of props.links) {
    const from = cards.get(link.from)
    const to = cards.get(link.to)
    if (!from || !to) continue
    const fromY = from.top + ANCHOR
    const toY = to.top + ANCHOR
    const turn = link.kind === "split" ? from.right + TURN : to.left - TURN
    nextLanes.push({
      kind: "piece",
      d: elbow(from.right, fromY - offset, to.left - LANE_END_GAP, toY - offset, turn - offset),
    })
    if (!props.simple) {
      nextLanes.push({
        kind: "kanban",
        d: elbow(to.left, toY + offset, from.right + LANE_END_GAP, fromY + offset, turn + offset),
      })
    }
    if (link.kind === "split") {
      nextMarks.set(`split-${link.from}`, { x: turn - offset, y: fromY - offset, kind: "split" })
    }
    if (link.kind === "assembly") {
      nextMarks.set(`assembly-${link.to}`, { x: turn - offset, y: toY - offset, kind: "assembly" })
    }
    if (link.branch) {
      nextLabels.push({
        kind: "branch",
        x: to.left - LANE_END_GAP - 4,
        y: toY - offset - 6,
        text: short(link.branch),
      })
    }
    const gap = into.get(to.column)
    into.set(to.column, {
      x: Math.min(gap?.x ?? Infinity, to.left - TURN * 2),
      top: Math.min(gap?.top ?? Infinity, fromY, toY),
      bottom: Math.max(gap?.bottom ?? -Infinity, fromY, toY),
    })
  }
  if (!props.simple) {
    for (const [column, gap] of into) {
      nextLabels.push({ kind: "piece", x: gap.x, y: gap.top - LANE_OFFSET - 12, text: "Piece" })
      nextLabels.push({
        kind: "kanban",
        x: gap.x,
        y: gap.bottom + LANE_OFFSET + 20,
        text: `${props.kanbans?.[column] ?? 0} Kanban`,
      })
    }
  }
  lanes.value = nextLanes
  labels.value = nextLabels
  marks.value = [...nextMarks.values()]
}

let observer: ResizeObserver | null = null

let watched: HTMLElement | null = null

function observe() {
  observer?.disconnect()
  watched?.removeEventListener("transitionend", measure)
  watched = props.container
  watched?.addEventListener("transitionend", measure)
  if (!props.container) return
  observer = new ResizeObserver(() => measure())
  observer.observe(props.container)
  for (const card of props.container.querySelectorAll("[data-station]")) observer.observe(card)
  measure()
}

onMounted(() => {
  observe()
  window.addEventListener("resize", measure)
})

onBeforeUnmount(() => {
  observer?.disconnect()
  watched?.removeEventListener("transitionend", measure)
  window.removeEventListener("resize", measure)
})

watch(
  () => [props.container, props.links, props.kanbans] as const,
  () => nextTick(observe),
  { deep: true },
)
</script>

<template>
  <svg
    class="pointer-events-none absolute inset-0"
    :width="size.width"
    :height="size.height"
    :viewBox="`0 0 ${size.width} ${size.height}`"
    fill="none"
    aria-hidden="true"
  >
    <defs>
      <marker
        id="flow-head-piece"
        viewBox="0 0 10 10"
        refX="9"
        refY="5"
        markerWidth="6"
        markerHeight="6"
        orient="auto-start-reverse"
      >
        <path
          d="M 0 1 L 9 5 L 0 9"
          fill="none"
          stroke="var(--color-primary)"
          stroke-width="1.6"
          stroke-linecap="round"
          stroke-linejoin="round"
        />
      </marker>
      <marker
        id="flow-head-kanban"
        viewBox="0 0 10 10"
        refX="9"
        refY="5"
        markerWidth="6"
        markerHeight="6"
        orient="auto-start-reverse"
      >
        <path
          d="M 0 1 L 9 5 L 0 9"
          fill="none"
          stroke="var(--color-base-content)"
          stroke-width="1.6"
          stroke-linecap="round"
          stroke-linejoin="round"
        />
      </marker>
    </defs>

    <path
      v-for="(lane, index) in lanes"
      :key="`${lane.kind}-${index}`"
      :d="lane.d"
      :stroke="lane.kind === 'piece' ? 'var(--color-primary)' : 'var(--color-base-content)'"
      :stroke-opacity="lane.kind === 'piece' ? 0.9 : 0.5"
      stroke-width="2"
      stroke-linecap="round"
      stroke-linejoin="round"
      :marker-end="`url(#flow-head-${lane.kind})`"
    />

    <template v-for="(mark, index) in marks" :key="`mark-${index}`">
      <rect
        v-if="mark.kind === 'split'"
        :x="mark.x - 5"
        :y="mark.y - 5"
        width="10"
        height="10"
        :transform="`rotate(45 ${mark.x} ${mark.y})`"
        fill="var(--color-primary)"
      >
        <title>Split</title>
      </rect>
      <circle v-else :cx="mark.x" :cy="mark.y" r="5" fill="var(--color-primary)">
        <title>Assembly</title>
      </circle>
    </template>

    <text
      v-for="(label, index) in labels"
      :key="`label-${index}`"
      :x="label.x"
      :y="label.y"
      :text-anchor="label.kind === 'branch' ? 'end' : 'middle'"
      class="text-[0.6875rem] font-medium tracking-wide"
      :class="label.kind === 'branch' ? '' : 'uppercase'"
      :fill="label.kind === 'kanban' ? 'var(--color-base-content)' : 'var(--color-primary)'"
      :fill-opacity="label.kind === 'kanban' ? 0.7 : 1"
    >
      {{ label.text }}
    </text>
  </svg>
</template>
