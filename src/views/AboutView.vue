<script setup lang="ts">
import { pageUrl } from "../api"
import { useLabels } from "../composables/useLabels"

const emit = defineEmits<{ open: [path: string] }>()

const { labels } = useLabels()

const rules = [
  {
    title: "No Kanban, no new work",
    text: "A Work Station starts a new piece of work only when it holds a Kanban. A Team Member with no Kanban does not start something new.",
  },
  {
    title: "The Blue Bins are the limit",
    text: "Each Work Station has a small number of Blue Bins, and each Blue Bin holds one finished piece. When all its Blue Bins are full, the Work Station stops making more.",
  },
  {
    title: "Finishing beats starting",
    text: "Across the Line, the Work Station nearest to production works first. Rework comes before new work, and the oldest Kanban comes before a new one.",
  },
  {
    title: "Help Downstream",
    text: "With no Kanban, a Team Member helps the downstream Work Station that holds up the flow. When nobody needs help, they wait: idle hands cost less than full queues.",
  },
  {
    title: "Work never moves backward",
    text: "A Work Station that finds a defect raises Rework against the Work Station that made it. A Team Member of that Work Station comes to repair the piece where it is.",
  },
  {
    title: "Break a rule only in the open",
    text: "Every rule can be broken, but only as a Deviation: the Team Member gives a reason, and everybody sees it at once.",
  },
]

const tools = [
  {
    term: "Takt Time",
    text: "The pace the Client asks for: the available Working Time divided by the number of pieces asked for. Bluebin compares the real flow with it all day.",
  },
  {
    term: "Heijunka",
    text: "The Backlog is not a priority list. Bluebin computes its order to mix the pieces of all active work at the pace of each one, so no work starves the others.",
  },
  {
    term: "Andon",
    text: "A signal that everybody in the Line sees when the flow has a problem. Any Team Member can raise one; it stops their Work Station until its Team Leader closes it.",
  },
  {
    term: "Measures",
    text: "Lead Time, Touch Time, Stagnation Time and First Pass Yield show where the work waits, so the team improves the flow, not the speed of each person.",
  },
]
</script>

<template>
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
              Each step takes new work as soon as it has finished its own. Work piles up in front of
              the slowest step, a lot is started and little is finished, and nobody sees where the
              work waits.
            </p>
          </div>
        </div>
        <div class="card border border-primary/40 bg-base-100">
          <div class="card-body gap-2">
            <h4 class="font-semibold">Pull: each step starts when the next one asks</h4>
            <p class="text-pretty opacity-80">
              A step makes one more piece only when the step after it takes one. The queues stay
              small, the work flows piece by piece, and a problem shows at once because the flow
              stops around it.
            </p>
          </div>
        </div>
      </div>
    </section>

    <section class="grid gap-4" aria-labelledby="kanban">
      <h3 id="kanban" class="text-xl font-semibold">The Kanban and the Blue Bin</h3>
      <p class="text-pretty">
        A <strong>Kanban</strong> is not a card on a board: it is a signal. It tells one Work
        Station that it can make one more {{ labels.piece }}. When a Work Station finishes a
        {{ labels.piece }}, it puts it in a <strong>Blue Bin</strong>. When the downstream Work
        Station pulls the {{ labels.piece }} out of that Blue Bin, the upstream Work Station gets a
        Kanban, and only then makes the next one.
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
              <span class="font-medium">{{ labels.pieces }}</span>
              <span class="opacity-70">flow downstream, from left to right, one at a time.</span>
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
          A Line: the Backlog, then Development with two Blue Bins, one full and one empty, then QA
          with one empty Blue Bin, then production.
        </figcaption>
      </figure>

      <p class="text-pretty">
        The number of Blue Bins of a Work Station is its limit of finished work that waits. With one
        empty Blue Bin, Development holds one Kanban and can make one more
        {{ labels.piece }}. When both Blue Bins are full, Development stops: making more would only
        make the queue in front of QA longer.
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
              <td>
                {{ labels.demand }}: a request for a quantity of {{ labels.pieces }} by a due date
              </td>
            </tr>
            <tr>
              <td>User Story</td>
              <td>{{ labels.piece }}: the work that flows, one at a time</td>
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
              <td>Blue Bin: holds one finished {{ labels.piece }} until the next step pulls it</td>
            </tr>
            <tr>
              <td>Bug sent back to development</td>
              <td>Rework: repaired where the {{ labels.piece }} is</td>
            </tr>
          </tbody>
        </table>
      </div>
    </section>

    <section class="grid gap-4" aria-labelledby="where">
      <h3 id="where" class="text-xl font-semibold">Where to find it in Bluebin</h3>
      <ul class="grid gap-2">
        <li>
          <a
            :href="pageUrl('/demands')"
            class="link font-medium"
            @click.exact.prevent="emit('open', '/demands')"
            >{{ labels.demands }}</a
          >: add the work your Clients ask for, and follow its Takt Time and Forecast.
        </li>
        <li>
          <a
            :href="pageUrl('/backlog')"
            class="link font-medium"
            @click.exact.prevent="emit('open', '/backlog')"
            >Backlog</a
          >: see the {{ labels.pieces }} that wait, in Heijunka order.
        </li>
        <li>
          <a
            :href="pageUrl('/line')"
            class="link font-medium"
            @click.exact.prevent="emit('open', '/line')"
            >Line</a
          >: see each Work Station, its Kanbans, its Blue Bins and its Andons.
        </li>
        <li>
          <a
            :href="pageUrl('/next')"
            class="link font-medium"
            @click.exact.prevent="emit('open', '/next')"
            >My next thing</a
          >: see the one thing to do now, as a Team Member.
        </li>
        <li>
          <a
            :href="pageUrl('/measures')"
            class="link font-medium"
            @click.exact.prevent="emit('open', '/measures')"
            >Measures</a
          >: see where the work waits, and improve the flow.
        </li>
      </ul>
    </section>
  </article>
</template>
