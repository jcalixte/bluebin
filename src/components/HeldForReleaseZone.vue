<script setup lang="ts">
import { computed } from "vue"
import type { HeldForRelease } from "../types"

const props = defineProps<{
  held: HeldForRelease[]
  busy: boolean
  canRelease: boolean
}>()

defineEmits<{
  release: [pieces: string[]]
}>()

/** One group per Demand, in the order of its first Deployment. */
const demands = computed(() => {
  const groups = new Map<string, { label: string; pieces: HeldForRelease[] }>()
  for (const one of props.held) {
    const group = groups.get(one.demand) ?? { label: one.demandLabel, pieces: [] }
    group.pieces.push(one)
    groups.set(one.demand, group)
  }
  return [...groups.entries()].map(([id, group]) => ({ id, ...group }))
})

function waiting(hours: number): string {
  return hours < 24 ? `${hours} h` : `${Math.round((hours / 24) * 10) / 10} d`
}
</script>

<template>
  <section aria-labelledby="held-for-release" class="flex min-w-[15rem] flex-col gap-3">
    <div class="flex min-h-6 items-center">
      <h3 id="held-for-release" class="text-xs font-semibold uppercase tracking-wide opacity-70">
        Held for Release
      </h3>
    </div>
    <article class="card border border-dashed border-base-content/40 bg-base-100">
      <div class="card-body gap-4 p-4">
        <p class="text-xs opacity-70">
          Deployed, but the Client cannot use them yet. The wait counts as Stagnation Time.
        </p>
        <div v-for="demand in demands" :key="demand.id" class="flex flex-col gap-2">
          <div class="flex items-center justify-between gap-2">
            <h4 class="truncate text-sm font-semibold">{{ demand.label }}</h4>
            <button
              v-if="canRelease && demand.pieces.length > 1"
              class="btn btn-primary btn-xs shrink-0"
              :disabled="busy"
              @click="
                $emit(
                  'release',
                  demand.pieces.map((one) => one.id),
                )
              "
            >
              Release all
            </button>
          </div>
          <ul class="flex flex-col gap-1.5">
            <li
              v-for="one in demand.pieces"
              :key="one.id"
              class="flex items-center justify-between gap-2 text-sm"
            >
              <span class="truncate font-medium">{{ one.piece }}</span>
              <span class="flex items-center gap-2">
                <span
                  class="tabular-nums text-xs opacity-70"
                  :title="`${one.waitingHours} h since its Deployment`"
                >
                  {{ waiting(one.waitingHours) }}
                </span>
                <button
                  v-if="canRelease"
                  class="btn btn-xs"
                  :disabled="busy"
                  @click="$emit('release', [one.id])"
                >
                  Release
                </button>
              </span>
            </li>
          </ul>
        </div>
      </div>
    </article>
  </section>
</template>
