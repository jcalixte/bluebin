import { ref } from "vue"
import type { FlowConfirm, ReorderEffect } from "../types.ts"

export type Pending = {
  /** The names of the rules the action breaks, space-separated. */
  confirm: string
  message: string
  effects?: ReorderEffect[]
  again: (reason: string) => Promise<FlowConfirm | null>
}

/** Most actions answer faster than this: showing a spinner for them only flickers. */
const SHOW_BUSY_AFTER_MS = 300
/** Once shown, the spinner stays this long, so it does not blink on and off. */
const KEEP_BUSY_FOR_MS = 500

export function useFlowRunner() {
  const pending = ref<Pending | null>(null)
  const actionError = ref<string | null>(null)
  /** True once an action runs longer than SHOW_BUSY_AFTER_MS. */
  const busy = ref(false)
  let running = false

  async function run(action: (reason?: string) => Promise<FlowConfirm | null>) {
    if (running) {
      return
    }
    running = true
    actionError.value = null
    let shownAt: number | null = null
    const showBusy = setTimeout(() => {
      busy.value = true
      shownAt = Date.now()
    }, SHOW_BUSY_AFTER_MS)
    try {
      const confirm = await action()
      if (confirm) {
        pending.value = {
          confirm: confirm.confirm,
          message: confirm.message,
          effects: confirm.effects,
          again: (why) => action(why),
        }
      }
    } catch (cause) {
      actionError.value = cause instanceof Error ? cause.message : String(cause)
    } finally {
      clearTimeout(showBusy)
      if (shownAt !== null) {
        const left = KEEP_BUSY_FOR_MS - (Date.now() - shownAt)
        if (left > 0) await new Promise((resolve) => setTimeout(resolve, left))
      }
      running = false
      busy.value = false
    }
  }

  async function recordDeviation(reason: string) {
    const why = reason.trim()
    if (!pending.value || why === "") {
      return
    }
    const action = pending.value.again
    pending.value = null
    await run(() => action(why))
  }

  return { pending, actionError, busy, run, recordDeviation }
}
