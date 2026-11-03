# Flow event log and current state, written in one transaction

Every action in a Value Stream (pull, put in Blue Bin, pause, Assembly, Rework, Deviation, Andon, Value Stream change) appends one flow event to an append-only log and updates the current-state tables in the same SQLite transaction. The log is the source of truth for every measure; the current-state tables serve the daily screens (Assignments, Priority Lists, Value Stream view) fast. We need the full history because the measures must stay exact (Lead Time = Touch Time + Stagnation Time), must be recomputed when the Working Calendar changes, and must compare periods before and after a Value Stream change.

## Considered Options

- **Current state only** — simplest, but measures cannot be recomputed and the history of Value Stream changes is lost.
- **Full event sourcing** — every state rebuilt from events; rejected for the extra projection, replay and event-versioning code that one team's Value Stream does not need.

## Consequences

- Two writes per action must stay consistent: they always share one transaction.
- If the current-state tables and the log disagree, the log wins: the tables are rebuilt from it.
- The log grows forever; archiving is a later concern.
- New screens push from the log over Server-Sent Events.
