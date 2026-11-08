import initSqlJs, { type Database, type SqlJsStatic, type SqlValue } from "sql.js"

/**
 * Stands in for `node:sqlite`, the module that the JavaScript side of sqlight imports (Vite aliases
 * it here, and so does `sim/test/sql_js.mjs` on Node). Only what sqlight calls: `exec`,
 * `prepare(...).all(...)` and `close`, synchronous.
 */

let sql: SqlJsStatic | null = null

/**
 * The WebAssembly loads once, before the Gleam code opens any database. The browser needs its URL;
 * Node finds it next to sql.js.
 */
export async function loadSqlite(wasmUrl?: string) {
  sql ??= await initSqlJs(wasmUrl ? { locateFile: () => wasmUrl } : undefined)
}

/**
 * sqlight opens a connection per request; the page has no file, so every connection to one name
 * shares one in-memory database, kept open for the life of the page.
 */
const open = new Map<string, Database>()

export class DatabaseSync {
  private database: Database

  constructor(name: string) {
    if (!sql) throw new Error("SQLite is not loaded yet.")
    const found = open.get(name) ?? new sql.Database()
    open.set(name, found)
    this.database = found
  }

  exec(text: string) {
    this.database.exec(text)
  }

  /** Rows as arrays, not objects: sqlight reads them by position, and two columns may share a name. */
  prepare(text: string) {
    const database = this.database
    return {
      all(...parameters: SqlValue[]): SqlValue[][] {
        const statement = database.prepare(text)
        try {
          statement.bind(parameters)
          const rows: SqlValue[][] = []
          while (statement.step()) rows.push(statement.get())
          return rows
        } finally {
          statement.free()
        }
      },
    }
  }

  close() {}
}
