# Icons

Reusable in-app icons. Source: https://tabler.io/icons (outline variant by default).

## Add an icon

1. Find the icon on https://tabler.io/icons, click it, copy the SVG (or download).
2. Save it here as `<slug>.svg` — same slug Tabler uses (`bolt.svg`, `qrcode.svg`).
3. Keep `stroke="currentColor"` in the SVG so colour follows Tailwind classes.

## Use an icon

Static colour (cheapest, no extra component):

```vue
<img src="@/assets/icons/bolt.svg" alt="" class="size-5" />
```

Dynamic colour (needs `currentColor` to flow through — paste the SVG inline as a component):

```vue
<template>
  <svg
    class="size-5 text-primary"
    viewBox="0 0 24 24"
    fill="none"
    stroke="currentColor"
    stroke-width="2"
    stroke-linecap="round"
    stroke-linejoin="round"
  >
    <!-- paste paths from the Tabler SVG here -->
  </svg>
</template>
```

The favicon at `public/favicon.svg` was generated from this same icon set with `currentColor` replaced by the app's primary hex at scaffold time.
