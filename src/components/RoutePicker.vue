<script setup lang="ts">
import { computed } from "vue"

type RouteStation = {
  id: string
  name: string
  position: number
  branch: string | null
  parentBranch?: string | null
}

type Group =
  | { kind: "trunk"; station: RouteStation }
  | { kind: "branch"; name: string; stations: RouteStation[] }

const props = defineProps<{ stations: RouteStation[] }>()

const skips = defineModel<string[]>({ required: true })

const groups = computed<Group[]>(() => {
  const groups: Group[] = []
  const branches = new Map<string, RouteStation[]>()
  for (const station of [...props.stations].sort((a, b) => a.position - b.position)) {
    if (station.branch === null) {
      groups.push({ kind: "trunk", station })
      continue
    }
    const outer = station.parentBranch ?? station.branch
    let stations = branches.get(outer)
    if (!stations) {
      stations = []
      branches.set(outer, stations)
      groups.push({ kind: "branch", name: outer, stations })
    }
    stations.push(station)
  }
  return groups
})

function goes(id: string) {
  return !skips.value.includes(id)
}

function setGoes(ids: string[], event: Event) {
  const on = (event.target as HTMLInputElement).checked
  const skipped = new Set(skips.value)
  for (const id of ids) {
    if (on) skipped.delete(id)
    else skipped.add(id)
  }
  skips.value = [...skipped].sort()
}

function ids(stations: RouteStation[]) {
  return stations.map((station) => station.id)
}
</script>

<template>
  <fieldset class="grid gap-1.5">
    <legend class="mb-1 text-sm font-medium">Work Stations it goes through</legend>
    <template
      v-for="group in groups"
      :key="group.kind === 'trunk' ? group.station.id : `branch:${group.name}`"
    >
      <label v-if="group.kind === 'trunk'" class="flex min-h-8 items-center gap-2 text-sm">
        <input
          type="checkbox"
          class="checkbox checkbox-sm"
          :checked="goes(group.station.id)"
          @change="setGoes([group.station.id], $event)"
        />
        {{ group.station.name }}
      </label>
      <div v-else class="rounded-box border border-base-300 px-2 py-1">
        <label class="flex min-h-8 items-center gap-2 text-sm font-medium">
          <input
            type="checkbox"
            class="checkbox checkbox-sm"
            :checked="group.stations.every((one) => goes(one.id))"
            :indeterminate="
              group.stations.some((one) => goes(one.id)) &&
              !group.stations.every((one) => goes(one.id))
            "
            @change="setGoes(ids(group.stations), $event)"
          />
          Branch {{ group.name }}
        </label>
        <label
          v-for="station in group.stations"
          :key="station.id"
          class="flex min-h-8 items-center gap-2 text-sm"
          :class="station.parentBranch ? 'pl-12' : 'pl-6'"
        >
          <input
            type="checkbox"
            class="checkbox checkbox-sm"
            :checked="goes(station.id)"
            @change="setGoes([station.id], $event)"
          />
          {{ station.name }}
        </label>
      </div>
    </template>
  </fieldset>
</template>
