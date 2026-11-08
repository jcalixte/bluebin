// `NODE_OPTIONS=--import=./test/sql_js.mjs gleam test`: the tests run on the
// sql.js stand-in of the browser, not on Node's own `node:sqlite`, which reads
// rows as objects and so loses one of two columns with the same name.
import { register } from "node:module"

const shim = new URL("../../src/simulation/sqlite.ts", import.meta.url).href

register(
  "data:text/javascript," +
    encodeURIComponent(`export async function resolve(specifier, context, next) {
      return specifier === "node:sqlite"
        ? { url: ${JSON.stringify(shim)}, shortCircuit: true }
        : next(specifier, context)
    }`),
)

const { loadSqlite } = await import(shim)
await loadSqlite()
