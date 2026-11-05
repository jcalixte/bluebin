<script setup lang="ts">
import { nextTick, ref } from "vue"

const props = defineProps<{ name: string; maxLength: number }>()
const emit = defineEmits<{ rename: [name: string] }>()

const editing = ref(false)
const draft = ref("")
const input = ref<HTMLInputElement | null>(null)

async function start() {
  draft.value = props.name
  editing.value = true
  await nextTick()
  input.value?.select()
}

function save() {
  const name = draft.value.trim()
  editing.value = false
  if (name !== "" && name !== props.name) {
    emit("rename", name)
  }
}
</script>

<template>
  <div class="flex min-h-6 items-center">
    <input
      v-if="editing"
      ref="input"
      v-model="draft"
      class="input input-xs w-full max-w-[12rem] uppercase tracking-wide"
      :maxlength="maxLength"
      @keyup.enter="save"
      @keyup.escape="editing = false"
      @blur="save"
    />
    <button
      v-else
      class="group flex items-center gap-1 text-xs font-semibold uppercase tracking-wide opacity-70 hover:opacity-100 focus-visible:opacity-100"
      :title="`Rename ${name}`"
      @click="start"
    >
      {{ name }}
      <svg
        class="size-3 opacity-0 transition-opacity group-hover:opacity-100 group-focus-visible:opacity-100 motion-reduce:transition-none"
        viewBox="0 0 24 24"
        fill="none"
        stroke="currentColor"
        stroke-width="2"
        stroke-linecap="round"
        stroke-linejoin="round"
        aria-hidden="true"
      >
        <path d="M4 20h4l10.5 -10.5a2.828 2.828 0 1 0 -4 -4l-10.5 10.5v4" />
        <path d="M13.5 6.5l4 4" />
      </svg>
    </button>
  </div>
</template>
