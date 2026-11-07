# Flow event log and current state, written in one transaction

Status: accepted

Every action in a Line (pull, put in Blue Bin, pause, Assembly, Rework, Deviation, Andon, Line change) appends one flow event to an append-only log and updates the current-state tables in the same SQLite transaction. The log is the source of truth for every measure; the current-state tables serve the daily screens (Assignments, Priority Lists, Line view) fast. We need the full history because the measures must stay exact (Lead Time = Touch Time + Stagnation Time), must be recomputed when the Working Calendar changes, and must compare periods before and after a Line change.

## Considered Options

| Option              | Tradeoff                                                                                  | Outcome                                    |
| ------------------- | ----------------------------------------------------------------------------------------- | ------------------------------------------ |
| Current state only  | Simplest, but measures cannot be recomputed and the history of Line changes is lost       | Rejected                                   |
| Full event sourcing | Every state rebuilt from events: projection, replay and event-versioning code to maintain | Rejected: one team's Line does not need it |

## Consequences

- Two writes per action must stay consistent: they always share one transaction.
- If the current-state tables and the log disagree, the log wins: the tables are rebuilt from it.
- The log grows forever; nothing archives it.
- New screens push from the log over Server-Sent Events.
