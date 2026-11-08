# Additive schema changes migrate, other changes are refused

Status: accepted

Each workspace is one SQLite file with a `schema_version`. Until version 2, a file of another version was refused and never migrated, and a schema change meant wiping every workspace (T10). From version 3, a change that only adds (a new table, a new nullable column, a new index) ships as a migration step that runs once in `prepare`, in one transaction, from each version to the next. A change that renames, removes or rewrites existing data is still refused, so it still needs a wipe. We chose this because the first additive change, the `helper` table for Helpers, would otherwise wipe Lines in daily use for a feature that touches none of their data. Additive steps cannot damage the data that is there, which is why "never migrate" existed.

## Considered Options

- Raise the version and wipe (H28): no migration code, but all data is lost again, for a change that does not need it.
- `create table if not exists` on each open, version unchanged (H30): no version step, but the version no longer describes the schema, and the drift stays hidden.

## Consequences

- `schema` in `db.gleam` always describes the latest version, for a new file. Each migration step describes only the delta from one version to the next. A test opens a file at each old version and checks that it ends equal to a new one.
- A step that is not additive is a design decision of its own: wipe, or write this ADR again.
