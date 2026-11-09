<script setup lang="ts">
import { computed, ref } from "vue"
import { lineFetch } from "../api"
import { useLabels } from "../composables/useLabels"
import { codePattern } from "../demandCode"
import type { Demand } from "../types"
import type { DemandCodeInput } from "../wire"

const props = defineProps<{ demand: Demand; canChangeCode: boolean }>()
const emit = defineEmits<{ changed: [] }>()

const { labels } = useLabels()

/** The code being typed, or null when the Demand Code is not being changed. */
const newCode = ref<string | null>(null)
const savingCode = ref(false)
const codeProblem = ref<string | null>(null)

function startChangingCode() {
  newCode.value = props.demand.code
  codeProblem.value = null
}

async function changeCode() {
  const code = newCode.value?.trim().toUpperCase() ?? ""
  if (!codePattern.test(code) || savingCode.value) return
  if (code === props.demand.code) {
    newCode.value = null
    return
  }
  savingCode.value = true
  codeProblem.value = null
  try {
    const response = await lineFetch(`/api/demands/${encodeURIComponent(props.demand.id)}/code`, {
      method: "PUT",
      headers: { "content-type": "application/json" },
      body: JSON.stringify({ code } satisfies DemandCodeInput),
    })
    if (!response.ok) {
      throw new Error((await response.text()) || `API answered ${response.status}`)
    }
    newCode.value = null
    emit("changed")
  } catch (cause) {
    codeProblem.value = cause instanceof Error ? cause.message : String(cause)
  } finally {
    savingCode.value = false
  }
}

/** Past this count, one tick per Piece is too dense to read. */
const maxTicks = 60

const round = (value: number) => Math.round(value * 10) / 10

const status = computed(() => {
  if (props.demand.andon) return "andon"
  return props.demand.taktGap < 0 ? "behind" : "ok"
})

const gapLabel = computed(() => {
  const gap = props.demand.taktGap
  if (gap > 0) return `+${gap}`
  return gap < 0 ? `−${Math.abs(gap)}` : "0"
})

/** Same share as takt_gap in backend/src/bluebin/demand.gleam. */
const timeShare = computed(() => {
  const { workingDaysElapsed, workingDaysTotal } = props.demand
  return workingDaysTotal === 0 ? 0 : Math.min(1, workingDaysElapsed / workingDaysTotal)
})

const expected = computed(() => round(timeShare.value * props.demand.piecesAsked))

const percentOf = (pieces: number) =>
  props.demand.piecesAsked === 0 ? 0 : Math.min(100, (pieces / props.demand.piecesAsked) * 100)

const deployedPercent = computed(() => percentOf(props.demand.piecesDeployed))
const taktPercent = computed(() => timeShare.value * 100)

/** The Pieces the Takt Time asked for by now and that are not deployed yet. */
const owedPercent = computed(() => Math.max(0, taktPercent.value - deployedPercent.value))

const ticks = computed(() => {
  const asked = props.demand.piecesAsked
  return asked > 1 && asked <= maxTicks ? asked : 0
})

const taktLabel = computed(() => {
  const hours = props.demand.taktTimeHours
  return hours >= 7 ? `${round(hours / 7)} working days` : `${round(hours)} h`
})

/** Noon keeps a `YYYY-MM-DD` day on the same date in every time zone. */
function dayLabel(day: string) {
  return new Date(`${day}T12:00:00`).toLocaleDateString(undefined, {
    day: "numeric",
    month: "short",
    year: "numeric",
  })
}

const dueLabel = computed(() => dayLabel(props.demand.dueOn))

const forecast = computed(() => {
  const { forecastOn, forecastLateDays } = props.demand
  if (forecastOn === null || forecastLateDays === null) return null
  const days = `${forecastLateDays} working ${forecastLateDays === 1 ? "day" : "days"}`
  return {
    on: forecastOn,
    label: dayLabel(forecastOn),
    late: forecastLateDays > 0,
    status: forecastLateDays > 0 ? `Late by ${days}` : "On time",
  }
})

const barLabel = computed(
  () =>
    `${props.demand.piecesDeployed} of ${props.demand.piecesAsked} Pieces deployed. ` +
    `The Takt Time asks for ${expected.value} by now.`,
)
</script>

<template>
  <article
    class="card overflow-hidden border bg-base-100 shadow-sm"
    :class="status === 'andon' ? 'border-2 border-error' : 'border-base-300'"
  >
    <div
      class="card-body grid gap-x-8 gap-y-4 p-4 sm:p-5 lg:grid-cols-[minmax(12rem,18rem)_1fr_9rem] lg:items-center"
    >
      <header class="min-w-0">
        <h3 class="flex items-baseline gap-2 text-base font-semibold leading-tight">
          <button
            v-if="canChangeCode && newCode === null"
            type="button"
            class="badge badge-outline shrink-0 cursor-pointer font-mono hover:bg-base-200"
            :title="`Change the code of ${demand.label}: it names each of its ${labels.pieces}`"
            :aria-label="`Code ${demand.code}. Change it`"
            @click="startChangingCode"
          >
            {{ demand.code }}
          </button>
          <span
            v-else-if="newCode === null"
            class="badge badge-outline shrink-0 font-mono"
            :title="`The code of ${demand.label}: it names each of its ${labels.pieces}`"
          >
            {{ demand.code }}
          </span>
          <span class="min-w-0">{{ demand.label }}</span>
        </h3>
        <form
          v-if="newCode !== null"
          class="mt-2 flex flex-wrap items-center gap-2"
          @submit.prevent="changeCode"
          @keydown.esc="newCode = null"
        >
          <input
            v-model="newCode"
            class="input input-sm w-20 font-mono uppercase"
            maxlength="4"
            pattern="[A-Za-z]{2,4}"
            autocomplete="off"
            :aria-label="`New code of ${demand.label}`"
            required
            autofocus
          />
          <button type="submit" class="btn btn-primary btn-sm" :disabled="savingCode">Save</button>
          <button type="button" class="btn btn-ghost btn-sm" @click="newCode = null">Cancel</button>
          <p class="w-full text-xs opacity-70">
            Each {{ labels.piece }} takes the new code: {{ newCode.toUpperCase() || "CHK" }}-1,
            {{ newCode.toUpperCase() || "CHK" }}-2…
          </p>
          <p v-if="codeProblem" role="alert" class="w-full text-sm text-error">
            {{ codeProblem }}
          </p>
        </form>
        <p class="mt-1 text-sm opacity-70">
          {{ demand.client }} · due <time :datetime="demand.dueOn">{{ dueLabel }}</time>
        </p>
        <p v-if="forecast" class="mt-2 flex flex-wrap items-center gap-x-2 gap-y-1 text-sm">
          <span>
            Forecast <time :datetime="forecast.on" class="font-medium">{{ forecast.label }}</time>
          </span>
          <span
            class="badge badge-sm font-medium whitespace-nowrap"
            :class="forecast.late ? 'badge-error' : 'badge-success'"
            title="The forecast against the due date, by the Working Calendar"
          >
            {{ forecast.status }}
          </span>
        </p>
        <p v-else class="mt-2 text-sm opacity-70">
          No forecast yet: no {{ labels.piece }} deployed
        </p>
        <p class="mt-1 text-xs opacity-70">
          Takt Time <span class="font-medium tabular-nums">{{ taktLabel }}</span> per Piece
        </p>
      </header>

      <div class="min-w-0">
        <div class="relative pt-2">
          <div
            role="img"
            :aria-label="barLabel"
            class="relative h-7 overflow-hidden rounded-field border border-base-content/30 bg-base-200"
          >
            <div
              class="absolute inset-y-0 left-0 bg-primary"
              :style="{ width: `${deployedPercent}%` }"
            />
            <div
              v-if="owedPercent > 0"
              class="owed absolute inset-y-0"
              :class="status === 'andon' ? 'text-error' : 'text-warning-ink'"
              :style="{ left: `${deployedPercent}%`, width: `${owedPercent}%` }"
            />
            <div
              v-if="ticks > 0"
              class="ticks absolute inset-0"
              :style="{ '--ticks': ticks }"
              aria-hidden="true"
            />
          </div>
          <!-- The Takt line stands out of the track so it stays visible over any fill. -->
          <div
            class="absolute top-0 bottom-[-0.25rem] w-0.5 -translate-x-1/2 rounded-full bg-base-content ring-2 ring-base-100"
            :style="{ left: `${taktPercent}%` }"
            aria-hidden="true"
          />
        </div>
        <p
          class="mt-2.5 flex flex-wrap items-center gap-x-4 gap-y-1 text-xs tabular-nums"
          aria-hidden="true"
        >
          <span class="flex items-center gap-1.5">
            <span class="size-2.5 rounded-xs bg-primary" />
            <span>
              <strong class="font-semibold">{{ demand.piecesDeployed }}</strong>
              <span class="opacity-70">/{{ demand.piecesAsked }} deployed</span>
            </span>
          </span>
          <span class="flex items-center gap-1.5">
            <span class="h-3 w-0.5 rounded-full bg-base-content" />
            <span>
              <strong class="font-semibold">{{ expected }}</strong>
              <span class="opacity-70"> asked by now</span>
            </span>
          </span>
          <span class="opacity-70 sm:ml-auto">
            working day {{ demand.workingDaysElapsed }} of {{ demand.workingDaysTotal }}
          </span>
        </p>
      </div>

      <div
        class="flex items-center justify-between gap-3 border-t border-base-300 pt-3 lg:flex-col lg:items-end lg:justify-center lg:gap-1 lg:border-t-0 lg:pt-0"
      >
        <p class="flex items-baseline gap-1.5 lg:flex-col lg:items-end lg:gap-0">
          <span
            class="text-3xl font-semibold leading-none tabular-nums"
            :class="{
              'text-error': status === 'andon',
              'text-warning-ink': status === 'behind',
            }"
          >
            {{ gapLabel }}
          </span>
          <span class="text-xs opacity-70">Takt Gap, in Pieces</span>
        </p>
        <span
          v-if="status === 'andon'"
          class="badge badge-error gap-1.5 font-semibold whitespace-nowrap"
          title="A Takt Gap of −1 Piece or less raises an Andon"
        >
          <span class="size-2 rounded-full bg-current" aria-hidden="true" />
          Andon
        </span>
        <span
          v-else-if="status === 'behind'"
          class="badge badge-warning font-medium whitespace-nowrap"
          title="Less than 1 Piece behind the Takt Time: no Andon yet"
        >
          Behind Takt
        </span>
        <span v-else class="badge badge-success font-medium whitespace-nowrap">On Takt</span>
      </div>
    </div>
  </article>
</template>

<style scoped>
.owed {
  background-image: repeating-linear-gradient(
    -45deg,
    currentColor 0 0.25rem,
    transparent 0.25rem 0.5rem
  );
}

/* One gap per Piece boundary: Pieces flow one at a time, so the bar counts them. */
.ticks {
  background: linear-gradient(to right, transparent calc(100% - 2px), var(--color-base-100) 0) 0 0 /
    calc(100% / var(--ticks)) 100% repeat-x;
}
</style>
