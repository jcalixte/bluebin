import { createApp } from "vue"
import "./style.css"
import App from "./App.vue"
import AboutView from "./views/AboutView.vue"

/** `/about` stands outside every Line: it reads no Line and needs none. */
const about = location.pathname.replace(/\/+$/, "") === "/about"

// The mode itself, not `simulation`: Vite folds it here, so the real build drops sql.js and the
// Gleam code.
if (import.meta.env.MODE === "simulation") {
  const { startSimulation } = await import("./simulation/start")
  await startSimulation()
}

createApp(about ? AboutView : App).mount("#app")
