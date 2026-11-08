<script setup lang="ts">
import { onBeforeUnmount, onMounted, ref } from "vue"
import BrandMark from "../components/BrandMark.vue"
import ThemeToggle from "../components/ThemeToggle.vue"

const sections = [
  { id: "push-pull", title: "Push or pull" },
  { id: "kanban", title: "The Kanban and the Blue Bin" },
  { id: "rules", title: "The pull rules" },
  { id: "stop", title: "Stop to fix" },
  { id: "pace", title: "Pace, levelling and measures" },
  { id: "where", title: "Where to find it" },
  { id: "more", title: "Learn more" },
] as const

type SectionId = (typeof sections)[number]["id"]

const section = Object.fromEntries(
  sections.map((s, i) => [s.id, { ...s, number: String(i + 1).padStart(2, "0") }]),
) as Record<SectionId, { id: SectionId; title: string; number: string }>

const active = ref<SectionId | null>(null)
let pinned = false
let unpinTimer: ReturnType<typeof setTimeout> | undefined

/** The active section is the last one whose heading is above the top third of the window. */
function updateActive() {
  if (pinned) return
  const scroller = document.documentElement
  if (scroller.scrollTop + innerHeight >= scroller.scrollHeight - 1) {
    // The last sections are too short to reach the line at the bottom of the page.
    active.value = sections[sections.length - 1].id
    return
  }
  let current: SectionId | null = null
  for (const s of sections) {
    const heading = document.getElementById(s.id)
    if (heading && heading.getBoundingClientRect().top <= innerHeight / 3) current = s.id
  }
  active.value = current
}

/**
 * A click marks its section at once and ignores the smooth scroll of the jump, which can end at the bottom.
 * The timeout covers a click that does not scroll, and browsers with no `scrollend`.
 */
function pick(id: SectionId) {
  active.value = id
  pinned = true
  clearTimeout(unpinTimer)
  unpinTimer = setTimeout(unpin, 1000)
}

function unpin() {
  pinned = false
  clearTimeout(unpinTimer)
}

onMounted(() => {
  updateActive()
  addEventListener("scroll", updateActive, { passive: true })
  addEventListener("scrollend", unpin)
})
onBeforeUnmount(() => {
  removeEventListener("scroll", updateActive)
  removeEventListener("scrollend", unpin)
  clearTimeout(unpinTimer)
})

/** One Blue Bin glyph. Full and empty differ by fill and border style, not by colour alone. */
const fullBin = "size-7 rounded-field border-2 border-primary bg-primary"
const emptyBin = "size-7 rounded-field border-2 border-dashed border-primary"
const piece = "size-2.5 rounded-xs bg-base-content/70"

type Node =
  | { kind: "end"; name: string }
  | { kind: "station"; name: string }
  | { kind: "bins"; bins: boolean[]; label: string }

const line: Node[] = [
  { kind: "end", name: "Backlog" },
  { kind: "station", name: "Development" },
  { kind: "bins", bins: [true, false], label: "1 full, 1 empty" },
  { kind: "station", name: "QA" },
  { kind: "bins", bins: [false], label: "1 empty" },
  { kind: "end", name: "Production" },
]

const cycle = [
  "Development finishes a Piece and puts it in a Blue Bin.",
  "QA pulls the Piece out of the Blue Bin when it is ready to work on it.",
  "The empty Blue Bin gives Development a Kanban.",
  "Development makes the next Piece. With no Kanban, it does not start one.",
]

const rules = [
  {
    title: "No Kanban, no new work",
    text: "A Work Station starts a new Piece only when it holds a Kanban. Until then, the next Piece waits in the Backlog or in the upstream Blue Bin.",
  },
  {
    title: "The Blue Bins are the limit",
    text: "Each Work Station has a small number of Blue Bins, and each Blue Bin holds one finished Piece. When all its Blue Bins are full, the Work Station stops making more.",
  },
  {
    title: "Finishing beats starting",
    text: "Across the Line, the Work Station nearest to Deployment works first. Rework comes before new work, and the oldest Kanban comes before a new one.",
  },
  {
    title: "Help Downstream",
    text: "With no Kanban, a Team Member helps the downstream Work Station that holds up the flow. When nobody needs help, they wait, because a new Piece would only add to the queue.",
  },
  {
    title: "Work never moves backward",
    text: "A Work Station that finds a defect raises Rework against the Work Station that made it. A Team Member of that Work Station comes to repair the Piece where it is.",
  },
  {
    title: "Break a rule only in the open",
    text: "Every rule can be broken, but only as a Deviation: the Team Member gives a reason, and everybody sees it at once. A Demand that cannot wait is a Deviation too, when someone moves its Pieces up the Backlog by hand.",
  },
]

const stops = [
  {
    title: "Anyone can stop",
    text: "Any Team Member can raise an Andon on their Work Station with one button. It stops that Work Station and calls its Team Leader.",
  },
  {
    title: "Bluebin raises some by itself",
    text: "Bluebin raises an Andon when a Demand is one Piece or more behind its Takt Time, and when a Rework waits one hour of Working Time with nobody to repair it. These Andons show the problem to everybody but do not stop a Work Station.",
  },
  {
    title: "Pull stops the rest",
    text: "A stopped Work Station pulls a new Piece only as a Deviation. Upstream, its Blue Bins stay full and give no Kanban. Downstream, no new Piece comes. Nobody stops the full Line by hand.",
  },
  {
    title: "The Team Leader helps, then closes",
    text: "The Team Leader comes to the Work Station, helps to fix the problem and closes the Andon. A Team Leader never pushes work to a Team Member. Each stop counts as Andon Time in the Measures.",
  },
]

const tools = [
  {
    term: "Takt Time",
    text: "The pace the Client asks for: the available Working Time divided by the number of Pieces asked for. A Demand one Piece or more behind its Takt Time raises an Andon.",
  },
  {
    term: "Heijunka",
    text: "Bluebin computes the order of the Backlog. It mixes the Pieces of all active Demands, each at the pace of its own Takt Time, so one large Demand does not hold back the small ones.",
  },
  {
    term: "Measures",
    text: "Lead Time, Touch Time, Stagnation Time and First Pass Yield show where each Piece waits and which Work Station makes the defects, so the team knows what to improve first.",
  },
]

const places = [
  {
    href: "/demands",
    name: "Demands",
    text: "Add the work your Clients ask for, and follow its Takt Time and Forecast.",
  },
  { href: "/backlog", name: "Backlog", text: "The Pieces that wait, in Heijunka order." },
  {
    href: "/line",
    name: "Line",
    text: "Every Work Station with its Kanbans, Blue Bins and Andons.",
  },
  { href: "/next", name: "My next thing", text: "What a Team Member does now." },
  {
    href: "/measures",
    name: "Measures",
    text: "Where the work waits, and a Before and After period to see if a change helped.",
  },
]

const readings = [
  {
    href: "https://thinking-people-system.house/",
    name: "Explorable Thinking People System",
    text: "The Toyota Production System that Bluebin comes from, drawn as a house with Just-in-Time and Jidoka as its two pillars.",
  },
  {
    href: "https://thinking-people-system.house/pull-system",
    name: "Exploring Pull System",
    text: "How a pull system helps a team finish more of what it starts.",
  },
]
</script>

<template>
  <div class="min-h-screen bg-base-200">
    <header class="bg-primary text-primary-content">
      <div class="mx-auto flex max-w-[110rem] items-center justify-between gap-4 px-6 py-6">
        <a href="/" class="flex items-center gap-3 rounded-field">
          <BrandMark />
          <h1 class="text-2xl font-semibold leading-tight">Bluebin</h1>
        </a>
        <ThemeToggle class="[--btn-rest-fg:var(--color-primary-content)]" />
      </div>
    </header>

    <main>
      <section class="border-b border-base-300 bg-base-100" aria-labelledby="about-title">
        <div class="mx-auto grid max-w-6xl gap-10 px-6 py-12 sm:py-16">
          <div class="grid max-w-3xl gap-5">
            <p class="text-sm font-semibold uppercase tracking-wide text-primary">About Bluebin</p>
            <h2
              id="about-title"
              class="text-[clamp(2rem,1.4rem+2.6vw,3.25rem)] font-semibold leading-[1.1] tracking-tight text-balance"
            >
              A pull system for software teams, built on the Toyota Production System
            </h2>
            <p class="max-w-2xl text-lg text-pretty text-base-content/80">
              In Bluebin, work moves only when the next step asks for it. The team finishes what it
              started before it starts something new, at the pace its Clients need.
            </p>
            <div class="flex flex-wrap gap-3 pt-2">
              <a href="/line" class="btn btn-primary h-11 px-5">Open your Line</a>
              <a href="https://try.bluebin.app/line" class="btn btn-outline h-11 px-5">
                Try the Simulation
              </a>
              <a href="#rules" class="btn btn-ghost h-11 px-5">Read the pull rules</a>
            </div>
          </div>

          <figure class="rounded-box border border-base-300 bg-base-200 p-5 sm:p-8">
            <ol class="flex flex-col items-stretch gap-2 sm:flex-row sm:items-center">
              <template v-for="(node, index) in line" :key="index">
                <li v-if="index > 0" aria-hidden="true" class="grid place-items-center">
                  <svg
                    class="size-5 rotate-90 text-base-content/50 sm:rotate-0"
                    viewBox="0 0 24 24"
                    fill="none"
                    stroke="currentColor"
                    stroke-width="2"
                    stroke-linecap="round"
                    stroke-linejoin="round"
                  >
                    <path d="M5 12h14M13 6l6 6l-6 6" />
                  </svg>
                </li>
                <li
                  v-if="node.kind === 'end'"
                  class="rounded-box border border-dashed border-base-content/30 px-4 py-3 text-center text-sm text-base-content/80 sm:flex-1"
                >
                  {{ node.name }}
                </li>
                <li
                  v-else-if="node.kind === 'station'"
                  class="rounded-box border border-base-300 bg-base-100 px-4 py-3 text-center font-semibold shadow-sm sm:flex-[1.4]"
                >
                  {{ node.name }}
                </li>
                <li v-else class="grid justify-items-center gap-1.5">
                  <span class="flex gap-1.5">
                    <span
                      v-for="(full, bin) in node.bins"
                      :key="bin"
                      :class="full ? fullBin : emptyBin"
                    />
                  </span>
                  <span class="text-xs text-base-content/70">
                    <span class="sr-only">Blue Bins:</span>{{ node.label }}
                  </span>
                </li>
              </template>
            </ol>

            <figcaption class="mt-8 grid gap-4 border-t border-base-300 pt-6 sm:grid-cols-2">
              <p class="flex items-start gap-3">
                <span
                  aria-hidden="true"
                  class="mt-0.5 grid size-7 shrink-0 place-items-center rounded-full bg-base-100 text-base-content/70"
                >
                  <svg
                    class="size-4"
                    viewBox="0 0 24 24"
                    fill="none"
                    stroke="currentColor"
                    stroke-width="2"
                    stroke-linecap="round"
                    stroke-linejoin="round"
                  >
                    <path d="M5 12h14M13 6l6 6l-6 6" />
                  </svg>
                </span>
                <span class="text-pretty">
                  <strong class="font-semibold">Pieces</strong>
                  <span class="text-base-content/80">
                    flow downstream, toward Production, one at a time.</span
                  >
                </span>
              </p>
              <p class="flex items-start gap-3">
                <span
                  aria-hidden="true"
                  class="mt-0.5 grid size-7 shrink-0 place-items-center rounded-full bg-primary text-primary-content"
                >
                  <svg
                    class="size-4"
                    viewBox="0 0 24 24"
                    fill="none"
                    stroke="currentColor"
                    stroke-width="2"
                    stroke-linecap="round"
                    stroke-linejoin="round"
                  >
                    <path d="M19 12H5M11 6l-6 6l6 6" />
                  </svg>
                </span>
                <span class="text-pretty">
                  <strong class="font-semibold">Kanbans</strong>
                  <span class="text-base-content/80">
                    flow upstream, toward the Backlog: each empty Blue Bin asks for one more.</span
                  >
                </span>
              </p>
              <span class="sr-only">
                A Line: the Backlog, then Development with two Blue Bins, one full and one empty,
                then QA with one empty Blue Bin, then Production.
              </span>
            </figcaption>
          </figure>
        </div>
      </section>

      <div
        class="mx-auto grid max-w-6xl gap-12 px-6 py-12 sm:py-16 lg:grid-cols-[13rem_minmax(0,1fr)]"
      >
        <nav aria-label="On this page" class="hidden lg:block">
          <div class="sticky top-8 grid gap-1">
            <p class="mb-2 px-3 text-xs font-semibold uppercase tracking-wide text-base-content/70">
              On this page
            </p>
            <a
              v-for="s in sections"
              :key="s.id"
              :href="`#${s.id}`"
              class="flex gap-3 rounded-r-field border-l-2 px-3 py-2 text-sm transition-colors hover:bg-base-300 hover:text-base-content"
              :class="
                active === s.id
                  ? 'border-primary bg-base-100 font-semibold text-base-content'
                  : 'border-transparent text-base-content/80'
              "
              :aria-current="active === s.id ? 'location' : undefined"
              @click="pick(s.id)"
            >
              <span class="font-semibold tabular-nums text-primary">{{
                section[s.id].number
              }}</span>
              {{ s.title }}
            </a>
          </div>
        </nav>

        <article class="grid max-w-3xl gap-16">
          <section class="grid gap-6" :aria-labelledby="section['push-pull'].id">
            <header class="flex items-baseline gap-3">
              <span class="font-semibold tabular-nums text-primary">{{
                section["push-pull"].number
              }}</span>
              <h3
                :id="section['push-pull'].id"
                class="scroll-mt-8 text-2xl font-semibold tracking-tight"
              >
                {{ section["push-pull"].title }}
              </h3>
            </header>
            <div class="grid gap-4 md:grid-cols-2">
              <div
                class="grid content-start gap-4 rounded-box border border-base-300 bg-base-100 p-5"
              >
                <div
                  aria-hidden="true"
                  class="flex h-16 items-center gap-1 rounded-field bg-base-200 px-2 text-xs"
                >
                  <span class="rounded-field bg-base-100 px-1.5 py-1">Design</span>
                  <span class="grid grid-cols-3 gap-0.5">
                    <span v-for="n in 6" :key="n" :class="piece" />
                  </span>
                  <span class="rounded-field bg-base-100 px-1.5 py-1 font-semibold"
                    >Development</span
                  >
                  <span :class="piece" />
                  <span class="rounded-field bg-base-100 px-1.5 py-1">QA</span>
                </div>
                <div class="grid gap-2">
                  <h4 class="font-semibold">Push: each step starts when it is free</h4>
                  <p class="text-pretty text-base-content/80">
                    Each step takes new work as soon as it has finished its own. The work piles up
                    in front of the slowest step, and many items are open at once while few reach
                    production.
                  </p>
                </div>
              </div>
              <div
                class="grid content-start gap-4 rounded-box border border-primary/50 bg-base-100 p-5"
              >
                <div
                  aria-hidden="true"
                  class="flex h-16 items-center gap-1 rounded-field bg-base-200 px-2 text-xs"
                >
                  <span class="rounded-field bg-base-100 px-1.5 py-1">Design</span>
                  <span class="flex gap-0.5">
                    <span class="size-4 rounded-sm bg-primary" />
                    <span class="size-4 rounded-sm border border-dashed border-primary" />
                  </span>
                  <span class="rounded-field bg-base-100 px-1.5 py-1 font-semibold"
                    >Development</span
                  >
                  <span class="size-4 rounded-sm border border-dashed border-primary" />
                  <span class="rounded-field bg-base-100 px-1.5 py-1">QA</span>
                </div>
                <div class="grid gap-2">
                  <h4 class="font-semibold">Pull: each step starts when the next one asks</h4>
                  <p class="text-pretty text-base-content/80">
                    A step makes one more item only when the step after it takes one. The queue in
                    front of each step stays as small as its Blue Bins. When one step stops, the
                    steps around it soon have nothing to pull or nowhere to put their work, so the
                    whole team sees the problem.
                  </p>
                </div>
              </div>
            </div>
          </section>

          <section class="grid gap-6" :aria-labelledby="section.kanban.id">
            <header class="flex items-baseline gap-3">
              <span class="font-semibold tabular-nums text-primary">{{
                section.kanban.number
              }}</span>
              <h3 :id="section.kanban.id" class="scroll-mt-8 text-2xl font-semibold tracking-tight">
                {{ section.kanban.title }}
              </h3>
            </header>
            <p class="text-lg text-pretty">
              A <strong class="font-semibold">Kanban</strong> is a signal: it tells one Work Station
              that it can make one more Piece. A <strong class="font-semibold">Blue Bin</strong>
              holds one finished Piece until the downstream Work Station pulls it. In the Line at
              the top of this page, one Piece goes through this cycle:
            </p>
            <ol class="grid gap-3">
              <li
                v-for="(step, index) in cycle"
                :key="index"
                class="flex items-start gap-4 rounded-box bg-base-100 p-4"
              >
                <span
                  aria-hidden="true"
                  class="grid size-8 shrink-0 place-items-center rounded-full border-2 border-primary font-semibold tabular-nums text-primary"
                  >{{ index + 1 }}</span
                >
                <span class="pt-1 text-pretty">{{ step }}</span>
              </li>
            </ol>
          </section>

          <section class="grid gap-6" :aria-labelledby="section.rules.id">
            <header class="flex items-baseline gap-3">
              <span class="font-semibold tabular-nums text-primary">{{
                section.rules.number
              }}</span>
              <h3 :id="section.rules.id" class="scroll-mt-8 text-2xl font-semibold tracking-tight">
                {{ section.rules.title }}
              </h3>
            </header>
            <ol class="grid gap-x-10 md:grid-cols-2">
              <li
                v-for="(rule, index) in rules"
                :key="rule.title"
                class="grid grid-cols-[2.75rem_minmax(0,1fr)] gap-x-2 border-t-2 border-base-300 py-5"
              >
                <span
                  aria-hidden="true"
                  class="text-3xl font-semibold leading-none tabular-nums text-primary"
                  >{{ index + 1 }}</span
                >
                <div class="grid gap-1.5">
                  <h4 class="font-semibold leading-snug">{{ rule.title }}</h4>
                  <p class="text-pretty text-base-content/80">{{ rule.text }}</p>
                </div>
              </li>
            </ol>
          </section>

          <section class="grid gap-6" :aria-labelledby="section.stop.id">
            <header class="flex items-baseline gap-3">
              <span class="font-semibold tabular-nums text-primary">{{ section.stop.number }}</span>
              <h3 :id="section.stop.id" class="scroll-mt-8 text-2xl font-semibold tracking-tight">
                {{ section.stop.title }}
              </h3>
            </header>
            <p class="text-lg text-pretty">
              An <strong class="font-semibold">Andon</strong> stops the work where a problem
              appears. The team fixes the cause at once, before more Pieces go through with the same
              problem.
            </p>
            <ul class="grid gap-x-10 md:grid-cols-2">
              <li
                v-for="stop in stops"
                :key="stop.title"
                class="grid gap-1.5 border-t-2 border-base-300 py-5"
              >
                <h4 class="flex items-center gap-2 font-semibold leading-snug">
                  <span class="size-2 shrink-0 rounded-full bg-andon" aria-hidden="true" />
                  {{ stop.title }}
                </h4>
                <p class="text-pretty text-base-content/80">{{ stop.text }}</p>
              </li>
            </ul>
          </section>

          <section class="grid gap-6" :aria-labelledby="section.pace.id">
            <header class="flex items-baseline gap-3">
              <span class="font-semibold tabular-nums text-primary">{{ section.pace.number }}</span>
              <h3 :id="section.pace.id" class="scroll-mt-8 text-2xl font-semibold tracking-tight">
                {{ section.pace.title }}
              </h3>
            </header>
            <dl class="divide-y divide-base-300 rounded-box border border-base-300 bg-base-100">
              <div
                v-for="tool in tools"
                :key="tool.term"
                class="grid gap-1 p-5 sm:grid-cols-[9rem_minmax(0,1fr)] sm:gap-6"
              >
                <dt class="font-semibold">{{ tool.term }}</dt>
                <dd class="text-pretty text-base-content/80">{{ tool.text }}</dd>
              </div>
            </dl>
          </section>

          <section class="grid gap-6" :aria-labelledby="section.where.id">
            <header class="grid gap-2">
              <div class="flex items-baseline gap-3">
                <span class="font-semibold tabular-nums text-primary">{{
                  section.where.number
                }}</span>
                <h3
                  :id="section.where.id"
                  class="scroll-mt-8 text-2xl font-semibold tracking-tight"
                >
                  {{ section.where.title }}
                </h3>
              </div>
              <p class="text-pretty text-base-content/80">
                Each link opens the last Line you used.
              </p>
            </header>
            <ul class="grid gap-3 sm:grid-cols-2">
              <li v-for="place in places" :key="place.href">
                <a
                  :href="place.href"
                  class="group flex h-full min-h-11 items-start gap-3 rounded-box border border-base-300 bg-base-100 p-4 transition-colors hover:border-primary focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-primary"
                >
                  <span class="grid flex-1 gap-1">
                    <span class="font-semibold text-primary">{{ place.name }}</span>
                    <span class="text-pretty text-base-content/80">{{ place.text }}</span>
                  </span>
                  <svg
                    aria-hidden="true"
                    class="mt-0.5 size-5 shrink-0 text-base-content/50 transition-transform group-hover:text-primary motion-safe:group-hover:translate-x-0.5"
                    viewBox="0 0 24 24"
                    fill="none"
                    stroke="currentColor"
                    stroke-width="2"
                    stroke-linecap="round"
                    stroke-linejoin="round"
                  >
                    <path d="M5 12h14M13 6l6 6l-6 6" />
                  </svg>
                </a>
              </li>
            </ul>
          </section>

          <section class="grid gap-6" :aria-labelledby="section.more.id">
            <header class="flex items-baseline gap-3">
              <span class="font-semibold tabular-nums text-primary">{{ section.more.number }}</span>
              <h3 :id="section.more.id" class="scroll-mt-8 text-2xl font-semibold tracking-tight">
                {{ section.more.title }}
              </h3>
            </header>
            <ul class="grid gap-3 sm:grid-cols-2">
              <li v-for="reading in readings" :key="reading.href">
                <a
                  :href="reading.href"
                  target="_blank"
                  rel="noopener"
                  class="group flex h-full min-h-11 items-start gap-3 rounded-box border border-base-300 bg-base-100 p-4 transition-colors hover:border-primary focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-primary"
                >
                  <span class="grid flex-1 gap-1">
                    <span class="font-semibold text-primary"
                      >{{ reading.name }}<span class="sr-only"> (opens in a new tab)</span></span
                    >
                    <span class="text-pretty text-base-content/80">{{ reading.text }}</span>
                    <span class="text-sm text-base-content/70">thinking-people-system.house</span>
                  </span>
                  <svg
                    aria-hidden="true"
                    class="mt-0.5 size-5 shrink-0 text-base-content/50 transition-transform group-hover:text-primary motion-safe:group-hover:-translate-y-0.5 motion-safe:group-hover:translate-x-0.5"
                    viewBox="0 0 24 24"
                    fill="none"
                    stroke="currentColor"
                    stroke-width="2"
                    stroke-linecap="round"
                    stroke-linejoin="round"
                  >
                    <path d="M17 7l-10 10M8 7h9v9" />
                  </svg>
                </a>
              </li>
            </ul>
          </section>
        </article>
      </div>
    </main>
  </div>
</template>
