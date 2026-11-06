import { onBeforeUnmount, onMounted } from "vue"
import { api } from "../api"

/** A closed stream (the proxy or the SSO answered something else) is not retried by the browser. */
const reopenAfterMs = 5000

/**
 * Reloads the screen on each change the API announces, and after a lost
 * stream comes back: events missed meanwhile are not replayed, the current
 * state is read again instead.
 */
export function useLiveUpdates(reload: () => Promise<unknown>) {
  let source: EventSource | null = null
  let reopen: ReturnType<typeof setTimeout> | undefined
  let lost = false
  let running = false
  let again = false

  async function refresh() {
    if (running) {
      again = true
      return
    }
    running = true
    try {
      do {
        again = false
        await reload()
      } while (again)
    } finally {
      running = false
    }
  }

  function open() {
    source = new EventSource(api("/api/events"))
    source.addEventListener("change", refresh)
    source.onopen = () => {
      if (lost) {
        lost = false
        void refresh()
      }
    }
    source.onerror = () => {
      lost = true
      if (source?.readyState === EventSource.CLOSED) {
        source.close()
        reopen = setTimeout(open, reopenAfterMs)
      }
    }
  }

  onMounted(open)
  onBeforeUnmount(() => {
    clearTimeout(reopen)
    source?.close()
  })
}
