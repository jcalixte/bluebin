<script setup lang="ts">
import { computed, ref } from "vue"

type Theme = "light" | "dark"

// No stored choice: the page follows the system setting (daisyUI `prefersdark`).
// index.html applies a stored choice before the first paint.
const root = document.documentElement
const theme = ref<Theme>(
  root.dataset.theme === "dark" ||
    (root.dataset.theme !== "light" && matchMedia("(prefers-color-scheme: dark)").matches)
    ? "dark"
    : "light",
)

const label = computed(() =>
  theme.value === "dark" ? "Use the light theme" : "Use the dark theme",
)

function toggle() {
  theme.value = theme.value === "dark" ? "light" : "dark"
  root.dataset.theme = theme.value
  localStorage.setItem("theme", theme.value)
}
</script>

<template>
  <button
    type="button"
    class="btn btn-sm btn-ghost btn-square"
    :aria-label="label"
    :title="label"
    @click="toggle"
  >
    <svg
      class="size-5"
      viewBox="0 0 24 24"
      fill="none"
      stroke="currentColor"
      stroke-width="2"
      stroke-linecap="round"
      stroke-linejoin="round"
      aria-hidden="true"
    >
      <template v-if="theme === 'dark'">
        <path d="M8 12a4 4 0 1 0 8 0a4 4 0 1 0 -8 0" />
        <path
          d="M3 12h1m8 -9v1m8 8h1m-9 8v1m-6.4 -15.4l.7 .7m12.1 -.7l-.7 .7m0 11.4l.7 .7m-12.1 -.7l-.7 .7"
        />
      </template>
      <path
        v-else
        d="M12 3c.132 0 .263 0 .393 0a7.5 7.5 0 0 0 7.92 12.446a9 9 0 1 1 -8.313 -12.454l0 .008"
      />
    </svg>
  </button>
</template>
