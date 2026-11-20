import assert from "node:assert/strict"
import { test } from "node:test"
import { useFlowRunner } from "./useFlowRunner.ts"

const wait = (ms: number) => new Promise((resolve) => setTimeout(resolve, ms))

test("a quick action never shows busy", async () => {
  const { busy, run } = useFlowRunner()
  const seen: boolean[] = []
  await run(async () => {
    await wait(50)
    seen.push(busy.value)
    return null
  })
  assert.deepEqual(seen, [false])
  assert.equal(busy.value, false)
})

test("a slow action shows busy, then clears it", async () => {
  const { busy, run } = useFlowRunner()
  const running = run(() => wait(400).then(() => null))
  await wait(350)
  assert.equal(busy.value, true)
  await running
  assert.equal(busy.value, false)
})

test("a second action while one runs is dropped", async () => {
  const { run } = useFlowRunner()
  let calls = 0
  const action = async () => {
    calls++
    await wait(20)
    return null
  }
  await Promise.all([run(action), run(action)])
  assert.equal(calls, 1)
  await run(action)
  assert.equal(calls, 2)
})
