import tailwindcss from "@tailwindcss/vite"
import vue from "@vitejs/plugin-vue"
import { defineConfig } from "vite"

export default defineConfig({
  plugins: [vue(), tailwindcss()],
  server: {
    proxy: {
      // In production Traefik forward auth sets this header from the authentik
      // session; in dev every request is the one "dev" workspace.
      "/api": {
        target: "http://localhost:8000",
        headers: { "X-authentik-uid": "dev" },
      },
    },
  },
})
