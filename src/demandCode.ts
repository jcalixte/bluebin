/** A Demand Code: 2 to 4 letters, A to Z. */
export const codePattern = /^[A-Z]{2,4}$/

/**
 * The code proposed for a Demand label: the initials of its words, or the
 * first three letters of a one-word label. Same rule as `propose` in
 * backend/src/bluebin/demand_code.gleam, without the codes in use: the backend
 * refuses a code that another active Demand has.
 */
export function proposeCode(label: string): string {
  const words = label
    .toUpperCase()
    .split(" ")
    .map((word) => word.replace(/[^A-Z]/g, ""))
    .filter((word) => word !== "")
  if (words.length === 0) return label.trim() === "" ? "" : "DM"
  const base = words.length === 1 ? words[0].slice(0, 3) : words.map((word) => word[0]).join("")
  return base.length === 1 ? `${base}D` : base.slice(0, 4)
}
