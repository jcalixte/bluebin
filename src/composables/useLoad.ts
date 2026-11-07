import { ref } from "vue"

/**
 * Wraps a read of the API in the `loading` and `error` state a screen shows. Only the
 * latest call writes: a slow answer that comes back after a newer call is dropped.
 */
export function useLoad<T>(read: () => Promise<T>, apply: (value: T) => void) {
  const error = ref<string | null>(null)
  const loading = ref(true)
  let latest = 0

  async function load() {
    const call = ++latest
    loading.value = true
    error.value = null
    try {
      const value = await read()
      if (call === latest) apply(value)
    } catch (cause) {
      if (call === latest) error.value = cause instanceof Error ? cause.message : String(cause)
    } finally {
      if (call === latest) loading.value = false
    }
  }

  return { error, loading, load }
}
