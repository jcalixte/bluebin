import { createApp } from "vue"
import "./style.css"
import App from "./App.vue"
import AboutView from "./views/AboutView.vue"

/** `/about` stands outside every Line: it reads no Line and needs none. */
const about = location.pathname.replace(/\/+$/, "") === "/about"

createApp(about ? AboutView : App).mount("#app")
