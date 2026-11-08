import tailwindcss from "@tailwindcss/vite"
import vue from "@vitejs/plugin-vue"
import { fileURLToPath } from "node:url"
import { defineConfig } from "vite"

export default defineConfig({
  plugins: [vue(), tailwindcss()],
  resolve: {
    // sqlight's JavaScript side opens SQLite through `node:sqlite`; the Simulation runs it on
    // sql.js in the browser instead.
    alias: { "node:sqlite": fileURLToPath(new URL("./src/simulation/sqlite.ts", import.meta.url)) },
  },
  server: {
    proxy: {
      // In production Traefik forward auth sets these headers from the authentik
      // session; in dev every request is the one "dev" Account and Workspace.
      // The API trusts the email and name only with BLUEBIN_SSO=on.
      "/api": {
        target: "http://localhost:8000",
        headers: {
          "X-authentik-uid": "dev",
          "X-authentik-email": "dev@bluebin.app",
          "X-authentik-name": "Dev Team Member",
          "X-authentik-username": "akadmin",
        },
      },
    },
  },
})
