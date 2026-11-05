import type { FlowConfirm } from "./types"

export async function postAction(
  path: string,
  body: Record<string, unknown>,
): Promise<FlowConfirm | null> {
  const response = await fetch(path, {
    method: "POST",
    headers: { "content-type": "application/json" },
    body: JSON.stringify(body),
  })
  if (response.status === 409) {
    const answer = (await response.json()) as Partial<FlowConfirm> & { message: string }
    if (answer.confirm) {
      return { confirm: answer.confirm, message: answer.message, effects: answer.effects }
    }
    throw new Error(answer.message)
  }
  if (!response.ok) {
    throw new Error(await response.text())
  }
  return null
}
