import { ref } from "vue"
import type { FlowConfirm } from "../types"

export type Pending = {
  message: string
  again: (reason: string) => Promise<FlowConfirm | null>
}

export function useFlowRunner() {
  const pending = ref<Pending | null>(null)
  const actionError = ref<string | null>(null)
  const busy = ref(false)

  async function run(action: (reason?: string) => Promise<FlowConfirm | null>) {
    actionError.value = null
    busy.value = true
    try {
      const confirm = await action()
      if (confirm) {
        pending.value = { message: confirm.message, again: (why) => action(why) }
      }
    } catch (cause) {
      actionError.value = cause instanceof Error ? cause.message : String(cause)
    } finally {
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
