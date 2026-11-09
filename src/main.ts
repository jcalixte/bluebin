import { createApp } from "vue"
import "./style.css"
import App from "./App.vue"
import AboutView from "./views/AboutView.vue"

const about = location.pathname.replace(/\/+$/, "") === "/about"

// The mode itself, not `simulation`: Vite folds it here, so the real build drops sql.js and the
// Gleam code. A Guest runs no Line: its Host answers every call.
let root = about ? AboutView : App
if (import.meta.env.MODE === "simulation") {
  const { guest } = await import("./simulation/state")
  if (guest && !about) {
    root = (await import("./components/GuestGate.vue")).default
  } else {
    const { startSimulation } = await import("./simulation/start")
    await startSimulation()
  }
}

createApp(root).mount("#app")
