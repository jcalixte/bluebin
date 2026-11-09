import { onBeforeUnmount, onMounted } from "vue"
import { api } from "../api"
import { onSimulatedChange, simulation } from "../simulation/state"

/** A closed stream (the proxy or the SSO answered something else) is not retried by the browser. */
const reopenAfterMs = 5000

/**
 * Events missed while the stream is lost are not replayed: the state is read again when it comes
 * back.
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

  if (simulation) {
    let stop = () => {}
    onMounted(() => (stop = onSimulatedChange(() => void refresh())))
    onBeforeUnmount(() => stop())
    return
  }

  onMounted(open)
  onBeforeUnmount(() => {
    clearTimeout(reopen)
    source?.close()
  })
}
