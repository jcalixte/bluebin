<script setup lang="ts">
import { nextTick, onBeforeUnmount, onMounted, ref, watch } from "vue"

const props = defineProps<{
  container: HTMLElement | null
  columns: { position: number; kanbans: number }[]
}>()

const CORNER_RADIUS = 10
const LANE_OFFSET = 9
const LANE_END_GAP = 5

type Card = { branch: string; left: number; right: number; middle: number }
type Lane = { d: string; kind: "piece" | "kanban" }
type Label = { x: number; y: number; text: string; kind: "piece" | "kanban" }

const size = ref({ width: 0, height: 0 })
const lanes = ref<Lane[]>([])
const labels = ref<Label[]>([])

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

function linked(one: Card, other: Card): boolean {
  return one.branch === "" || other.branch === "" || one.branch === other.branch
}

function measure() {
  const root = props.container
  if (!root) return
  size.value = { width: root.offsetWidth, height: root.offsetHeight }

  const base = root.getBoundingClientRect()
  const byColumn = new Map<number, Card[]>()
  for (const card of root.querySelectorAll<HTMLElement>("[data-column]")) {
    const index = Number(card.dataset.column)
    const box = card.getBoundingClientRect()
    const cards = byColumn.get(index) ?? []
    cards.push({
      branch: card.dataset.branch ?? "",
      left: box.left - base.left,
      right: box.right - base.left,
      middle: box.top - base.top + box.height / 2,
    })
    byColumn.set(index, cards)
  }

  const nextLanes: Lane[] = []
  const nextLabels: Label[] = []
  for (let index = 0; index + 1 < props.columns.length; index += 1) {
    const upstream = byColumn.get(index)
    const downstream = byColumn.get(index + 1)
    if (!upstream?.length || !downstream?.length) continue

    const leftEdge = Math.max(...upstream.map((card) => card.right))
    const rightEdge = Math.min(...downstream.map((card) => card.left))
    const middle = (leftEdge + rightEdge) / 2

    for (const from of upstream) {
      for (const to of downstream) {
        if (!linked(from, to)) continue
        nextLanes.push({
          kind: "piece",
          d: elbow(
            leftEdge,
            from.middle - LANE_OFFSET,
            rightEdge - LANE_END_GAP,
            to.middle - LANE_OFFSET,
            middle - LANE_OFFSET,
          ),
        })
      }
    }
    for (const from of downstream) {
      for (const to of upstream) {
        if (!linked(from, to)) continue
        nextLanes.push({
          kind: "kanban",
          d: elbow(
            rightEdge,
            from.middle + LANE_OFFSET,
            leftEdge + LANE_END_GAP,
            to.middle + LANE_OFFSET,
            middle + LANE_OFFSET,
          ),
        })
      }
    }

    const tops = [...upstream, ...downstream].map((card) => card.middle)
    nextLabels.push({
      kind: "piece",
      x: middle,
      y: Math.min(...tops) - LANE_OFFSET - 12,
      text: "Piece",
    })
    nextLabels.push({
      kind: "kanban",
      x: middle,
      y: Math.max(...tops) + LANE_OFFSET + 20,
      text: `${props.columns[index + 1]?.kanbans ?? 0} Kanban`,
    })
  }
  lanes.value = nextLanes
  labels.value = nextLabels
}

let observer: ResizeObserver | null = null

function observe() {
  observer?.disconnect()
  if (!props.container) return
  observer = new ResizeObserver(() => measure())
  observer.observe(props.container)
  for (const card of props.container.querySelectorAll("[data-column]")) observer.observe(card)
  measure()
}

onMounted(() => {
  observe()
  window.addEventListener("resize", measure)
})

onBeforeUnmount(() => {
  observer?.disconnect()
  window.removeEventListener("resize", measure)
})

watch(
  () => [props.container, props.columns] as const,
  () => nextTick(observe),
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

    <text
      v-for="(label, index) in labels"
      :key="`label-${index}`"
      :x="label.x"
      :y="label.y"
      text-anchor="middle"
      class="text-[0.6875rem] font-medium uppercase tracking-wide"
      :fill="label.kind === 'piece' ? 'var(--color-primary)' : 'var(--color-base-content)'"
      :fill-opacity="label.kind === 'piece' ? 1 : 0.7"
    >
      {{ label.text }}
    </text>
  </svg>
</template>
