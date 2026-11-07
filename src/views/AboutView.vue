<script setup lang="ts">
import BrandMark from "../components/BrandMark.vue"
import ThemeToggle from "../components/ThemeToggle.vue"

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
    text: "Across the Line, the Work Station nearest to production works first. Rework comes before new work, and the oldest Kanban comes before a new one.",
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
    term: "Andon",
    text: "A signal that everybody in the Line sees when the flow has a problem. Any Team Member can raise one; it stops their Work Station until its Team Leader closes it.",
  },
  {
    term: "Measures",
    text: "Lead Time, Touch Time, Stagnation Time and First Pass Yield show where each Piece waits and which Work Station makes the defects, so the team knows what to improve first.",
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
    <main class="px-6 py-8">
      <article class="mx-auto grid max-w-4xl gap-10">
        <header class="grid gap-3">
          <p class="text-sm font-semibold uppercase tracking-wide text-primary">About Bluebin</p>
          <h2 class="text-3xl font-semibold text-balance">
            A pull system for software teams, built on the Toyota Production System
          </h2>
          <p class="text-lg text-pretty opacity-80">
            In Bluebin, work moves only when the next step asks for it. The team finishes what it
            started before it starts something new, at the pace its Clients need.
          </p>
        </header>

        <section class="grid gap-4" aria-labelledby="push-pull">
          <h3 id="push-pull" class="text-xl font-semibold">Push or pull</h3>
          <div class="grid gap-4 md:grid-cols-2">
            <div class="card border border-base-300 bg-base-100">
              <div class="card-body gap-2">
                <h4 class="font-semibold">Push: each step starts when it is free</h4>
                <p class="text-pretty opacity-80">
                  Each step takes new work as soon as it has finished its own. The work piles up in
                  front of the slowest step, and many items are open at once while few reach
                  production.
                </p>
              </div>
            </div>
            <div class="card border border-primary/40 bg-base-100">
              <div class="card-body gap-2">
                <h4 class="font-semibold">Pull: each step starts when the next one asks</h4>
                <p class="text-pretty opacity-80">
                  A step makes one more item only when the step after it takes one. The queue in
                  front of each step stays as small as its Blue Bins. When one step stops, the steps
                  around it soon have nothing to pull or nowhere to put their work, so the whole
                  team sees the problem.
                </p>
              </div>
            </div>
          </div>
        </section>

        <section class="grid gap-4" aria-labelledby="kanban">
          <h3 id="kanban" class="text-xl font-semibold">The Kanban and the Blue Bin</h3>
          <p class="text-pretty">
            In Bluebin, a <strong>Kanban</strong> is a signal. It tells one Work Station that it can
            make one more Piece. When a Work Station finishes a Piece, it puts it in a
            <strong>Blue Bin</strong>. When the downstream Work Station pulls the Piece out of that
            Blue Bin, the upstream Work Station gets a Kanban, and only then makes the next one.
          </p>

          <figure class="card border border-base-300 bg-base-100">
            <div class="card-body gap-4 overflow-x-auto">
              <div class="flex min-w-max items-center gap-2 text-sm">
                <div class="rounded-box border border-base-300 px-3 py-2">Backlog</div>
                <span aria-hidden="true" class="opacity-60">→</span>
                <div class="rounded-box bg-base-200 px-3 py-2 font-medium">Development</div>
                <span aria-hidden="true" class="opacity-60">→</span>
                <div class="flex gap-1" title="Two Blue Bins: one full, one empty">
                  <span class="size-8 rounded-field bg-primary" />
                  <span class="size-8 rounded-field border-2 border-dashed border-primary" />
                </div>
                <span aria-hidden="true" class="opacity-60">→</span>
                <div class="rounded-box bg-base-200 px-3 py-2 font-medium">QA</div>
                <span aria-hidden="true" class="opacity-60">→</span>
                <div class="flex gap-1" title="One empty Blue Bin">
                  <span class="size-8 rounded-field border-2 border-dashed border-primary" />
                </div>
                <span aria-hidden="true" class="opacity-60">→</span>
                <div class="rounded-box border border-base-300 px-3 py-2">Production</div>
              </div>
              <div class="grid min-w-max gap-1 text-sm">
                <p>
                  <span class="font-medium">Pieces</span>
                  <span class="opacity-70"
                    >flow downstream, from left to right, one at a time.</span
                  >
                </p>
                <p>
                  <span class="font-medium">Kanbans</span>
                  <span class="opacity-70"
                    >flow upstream, from right to left: each empty Blue Bin asks for one more.</span
                  >
                </p>
              </div>
            </div>
            <figcaption class="sr-only">
              A Line: the Backlog, then Development with two Blue Bins, one full and one empty, then
              QA with one empty Blue Bin, then production.
            </figcaption>
          </figure>

          <p class="text-pretty">
            The number of Blue Bins of a Work Station is its limit of finished work that waits. With
            one empty Blue Bin, Development holds one Kanban and can make one more Piece. When both
            Blue Bins are full, Development stops: making more would only make the queue in front of
            QA longer.
          </p>
        </section>

        <section class="grid gap-4" aria-labelledby="rules">
          <h3 id="rules" class="text-xl font-semibold">The pull rules</h3>
          <ol class="grid gap-3 md:grid-cols-2">
            <li
              v-for="(rule, index) in rules"
              :key="rule.title"
              class="flex gap-3 rounded-box border border-base-300 bg-base-100 p-4"
            >
              <span
                class="grid size-7 shrink-0 place-items-center rounded-full bg-primary text-sm font-semibold text-primary-content"
                >{{ index + 1 }}</span
              >
              <div class="grid gap-1">
                <h4 class="font-semibold">{{ rule.title }}</h4>
                <p class="text-sm text-pretty opacity-80">{{ rule.text }}</p>
              </div>
            </li>
          </ol>
        </section>

        <section class="grid gap-4" aria-labelledby="pace">
          <h3 id="pace" class="text-xl font-semibold">Pace, levelling and problems</h3>
          <dl class="grid gap-3 md:grid-cols-2">
            <div
              v-for="tool in tools"
              :key="tool.term"
              class="rounded-box border border-base-300 bg-base-100 p-4"
            >
              <dt class="font-semibold">{{ tool.term }}</dt>
              <dd class="mt-1 text-sm text-pretty opacity-80">{{ tool.text }}</dd>
            </div>
          </dl>
        </section>

        <section class="grid gap-4" aria-labelledby="words">
          <h3 id="words" class="text-xl font-semibold">Your words, Bluebin words</h3>
          <div class="overflow-x-auto rounded-box border border-base-300 bg-base-100">
            <table class="table">
              <thead>
                <tr>
                  <th scope="col">In a software team</th>
                  <th scope="col">In Bluebin</th>
                </tr>
              </thead>
              <tbody>
                <tr>
                  <td>Feature</td>
                  <td>Demand: a request for a quantity of Pieces by a due date</td>
                </tr>
                <tr>
                  <td>User Story</td>
                  <td>Piece: the work that flows, one at a time</td>
                </tr>
                <tr>
                  <td>Team or step (design, development, QA)</td>
                  <td>Work Station</td>
                </tr>
                <tr>
                  <td>Board or workflow</td>
                  <td>Line: the ordered chain of Work Stations</td>
                </tr>
                <tr>
                  <td>"Done" column</td>
                  <td>Blue Bin: holds one finished Piece until the next step pulls it</td>
                </tr>
                <tr>
                  <td>Bug sent back to development</td>
                  <td>Rework: repaired where the Piece is</td>
                </tr>
              </tbody>
            </table>
          </div>
        </section>

        <section class="grid gap-4" aria-labelledby="where">
          <h3 id="where" class="text-xl font-semibold">Where to find it in Bluebin</h3>
          <p class="text-pretty">Each link opens the last Line you used.</p>
          <ul class="grid gap-2">
            <li>
              <a href="/demands" class="link font-medium">Demands</a>: add the work your Clients ask
              for, and follow its Takt Time and Forecast.
            </li>
            <li>
              <a href="/backlog" class="link font-medium">Backlog</a>: the Pieces that wait, in
              Heijunka order.
            </li>
            <li>
              <a href="/line" class="link font-medium">Line</a>: every Work Station with its
              Kanbans, Blue Bins and Andons.
            </li>
            <li>
              <a href="/next" class="link font-medium">My next thing</a>: what a Team Member does
              now.
            </li>
            <li>
              <a href="/measures" class="link font-medium">Measures</a>: where the work waits, and a
              Before and After period to see if a change helped.
            </li>
          </ul>
        </section>
      </article>
    </main>
  </div>
</template>
