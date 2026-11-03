# Pull Kanban — Design (QFD)

This document designs the Pull Kanban app: how a team designs its Value Stream and then runs its daily work in it, with pull, Takt Time and Heijunka. It does not define terms: every term in **bold** is defined in [CONTEXT.md](./CONTEXT.md). Decisions that are hard to reverse go in [docs/adr/](./docs/adr/).

Strength weights used in matrices: **9** strong, **3** medium, **1** weak, blank none.

---

## 1. Goals — the WHATs

User-facing outcomes, weight 1–10, grouped by the parts of the Toyota Production System house: the roof is the goal, two pillars hold it, People work in the centre, and the foundation carries everything.

| ID | Goal | Weight | Source |
|----|------|:------:|--------|
| **Roof — Client satisfaction** | | | |
| G1 | Everyone is aligned on the active **Demands** and sees, at all times, whether each one is on its **Takt Time** for its **Client** | 10 | Session decision (2026-11-03) |
| **Pillar — Just-In-Time** | | | |
| G2 | Starting work without a **Kanban** is never silent: each **Deviation** is visible and has a reason | 9 | Kick-off conversation (2026-11-03) |
| G3 | Each **Piece** flows alone and reaches production at its **Demand**'s **Takt Time** | 8 | Kick-off conversation |
| **Pillar — Jidoka** | | | |
| G4 | A defect stops the flow where it is found, and its author repairs it first (**Rework**) | 8 | Session decision (2026-11-03) |
| **Centre — People and teamwork** | | | |
| G5 | A **Person** always knows the next thing to do: an **Assignment**, a **Rework**, **Help Downstream**, or wait | 9 | Kick-off conversation |
| **Foundation — Heijunka** | | | |
| G6 | The **Pieces** that leave the **Backlog** have a levelled **Product Mix** | 7 | Kick-off conversation |
| **Foundation — Stability and visual management** | | | |
| G7 | The whole **Value Stream** is visible at a glance: **Kanbans**, **Blue Bins**, **Rework**, bottleneck | 8 | Kick-off conversation |
| G8 | Recording work costs seconds, so the data stays true | 8 | Kick-off conversation |
| **Foundation — Kaizen** | | | |
| G9 | Flow problems show as numbers: **Lead Time**, **Stagnation Time**, **Starvation Time**, **Rework Time** | 8 | Kick-off conversation |
| G10 | A **Value Stream** can be designed and changed without code: **Work Stations**, **Branches**, **Blue Bins**, **People**, **Working Calendar** | 6 | Kick-off conversation |

User segments: **Person** (daily work), Value Stream designer (design and Kaizen), **Client** and Demand owner (Demands and **Takt Time**).

Deferred: **Standardized Work** (foundation). The Definition of Done of each **Work Station** stays out of the app for now. **Trigger to revisit:** **Rework** shows that **Work Stations** disagree on what "done" means.

---

## 2. Functions — the HOWs

Measurable responsibilities. Direction: ↑ higher is better, ↓ lower is better, → fixed value.

| ID | Function | Dir | Target | Goal |
|----|----------|:---:|--------|------|
| **Roof — Client satisfaction** | | | | |
| F1 | Show every active **Demand** with its **Client**, due date, **Takt Time** and **Takt Gap**, in one view that is the same for everyone | → | 1 shared view, open in ≤ 1 s | G1 |
| F2 | Update the **Takt Gap** when a **Piece** reaches production, and as **Working Time** passes | ↓ | ≤ 1 min after the event | G1 |
| F3 | Raise an **Andon** to all **People** when a **Demand** falls behind its **Takt Time** (**Takt Gap** ≤ −1) | ↓ | ≤ 1 min | G1 |
| F4 | Forecast the delivery date of each **Demand** from its current flow, and compare it with the due date | ↓ | error ≤ 1 working day | G1 |
| F5 | Measure the share of **Demands** that reach production by their due date | ↑ | ≥ 90 % | G1 |
| **Pillar — Just-In-Time** | | | | |
| F6 | Warn before a pull without a **Kanban**, and record a **Deviation** with its reason if the **Person** goes on | → | 100 % warned and recorded | G2 |
| F7 | Send one **Kanban** upstream for each pull out of a **Blue Bin**, and one **Kanban** to each **Branch** for each **Assembly** | → | **Kanbans** ≤ empty **Blue Bins**, at all times | G2 |
| F8 | Warn before an **Assembly** when a **Sub-Piece** is not in the last **Blue Bin** of its **Branch**, and record a **Deviation** with its reason if the **Person** goes on | → | 100 % warned and recorded | G2 |
| F9 | Warn before a second **Piece** goes in a **Blue Bin**, and record a **Deviation** with its reason if the **Person** goes on | → | 100 % warned and recorded | G3 |
| F10 | Compare the capacity of each **Work Station** (average **Touch Time** ÷ **People** working) with the **Takt Time** of the **Value Stream**, and flag the slower ones | ↓ | flag ≤ 1 working day after the change | G3 |
| F11 | Recompute the **Takt Time** of the **Value Stream** when a **Demand** enters or ends | ↓ | ≤ 1 min | G3 |
| **Pillar — Jidoka** | | | | |
| F12 | Raise **Rework** on a **Piece**: name the **Work Station** that made the defect, and describe the defect in one line | ↓ | ≤ 2 clicks, ≤ 10 s | G4 |
| F13 | Give the **Rework** to its author by default: put it first in their **Assignments** and pause their current **Piece** | ↓ | ≤ 1 min after the **Rework** is raised | G4 |
| F14 | Warn before the downstream **Work Station** pulls a new **Piece** while its **Rework** is open, and record a **Deviation** if it goes on | → | 100 % warned and recorded | G4 |
| F15 | Raise an **Andon** when a **Rework** waits without an active **Assignment** | ↓ | after ≤ 1 h of **Working Time** | G4 |
| F16 | Measure, for each **Work Station**, its **Rework Time** and its **First Pass Yield** | ↑ | **First Pass Yield** ≥ 90 % | G4 |
| F42 | Let any **Person** raise an **Andon** on their **Work Station** with one button: it stops the **Work Station** and calls its **Team Leader**, who closes it | ↓ | 1 click; **Team Leader** called ≤ 1 min | G4 |
| **Centre — People and teamwork** | | | | |
| F17 | Update the **Priority List** of each **Work Station** and the **Assignments** of each **Person** after any flow event | ↓ | ≤ 2 s | G5 |
| F18 | Order **Priority Lists** and **Assignments** by the glossary rules: **Rework**, then nearest to production, then oldest | → | 100 % of cases | G5 |
| F19 | Show each **Person** one next thing: their active **Assignment**, the top **Kanban** they can take, a **Help Downstream** target, or "wait" | ↓ | 1 screen, ≤ 1 s | G5 |
| F20 | Let a free **Person** take the top **Kanban** of their **Work Station** nearest to production | ↓ | 1 click | G5 |
| F21 | Let any **Person** of a **Work Station** reassign an **Assignment** to another **Person** of the same **Work Station** | ↓ | ≤ 2 clicks | G5 |
| F22 | Propose a **Help Downstream** target: the nearest downstream **Work Station** that holds up the flow (open **Rework**, or a full **Blue Bin** in front of it) | → | always shown when the **Person** has no **Kanban** | G5 |
| **Foundation — Heijunka** | | | | |
| F23 | Compute the **Heijunka Sequence** from the **Takt Time** of each active **Demand**: earliest slot, then earliest due date, then first-in, first-out | ↓ | recomputed ≤ 1 min after a **Demand** enters, ends or changes | G6 |
| F24 | Release the top **Piece** of the **Backlog** only when the first **Work Station** takes a **Kanban** | → | 100 % of releases | G6 |
| F25 | Let a **Person** reorder the **Heijunka Sequence** by hand as a **Deviation** with its reason, and show the effect on the **Takt Gap** and the forecast of each **Demand** before they confirm | ↓ | effect shown ≤ 2 s | G6 |
| F26 | Measure, for each day, the gap between the planned and the real **Product Mix** of the **Pieces** that leave the **Backlog** | ↓ | ≤ 1 **Piece** for each **Demand**, each day | G6 |
| **Foundation — Stability and visual management** | | | | |
| F27 | Show the **Value Stream** view: each **Work Station** with its **Blue Bins** (full or empty), **Kanbans**, **People**, active **Assignments**, open **Rework**, **Deviations** and **Andons** | ↓ | 1 screen, readable on a wall TV | G7 |
| F28 | Update every open view after a flow event, with no manual refresh | ↓ | ≤ 2 s | G7 |
| F29 | Highlight the bottleneck: the **Work Stations** flagged by F10, or with a full **Blue Bin** in front of them | ↓ | ≤ 1 min after the change | G7 |
| F30 | Record a flow event (pull, put in **Blue Bin**, **Assembly**, take a **Kanban**, reassign) | ↓ | ≤ 2 clicks, ≤ 5 s | G8 |
| F31 | Record a **Deviation** reason in one line | ↓ | ≤ 10 s | G8 |
| F32 | Pause the current **Piece** automatically when a **Person** takes another **Assignment** | → | 100 %, with no manual step | G8 |
| F33 | Show stale **Assignments**: active, with no event for more than 1 working day | ↓ | ≤ 5 % of active **Assignments** | G8 |
| **Foundation — Kaizen** | | | | |
| F34 | Compute **Lead Time**, **Station Lead Time**, **Touch Time** and **Stagnation Time** for each **Piece** and each **Demand**, and **Starvation Time** for each **Work Station**, from the flow events | → | **Lead Time** = **Touch Time** + **Stagnation Time**, exactly | G9 |
| F35 | Switch every measure between **Calendar Time** (the default) and **Working Time** | ↓ | 1 click | G9 |
| F36 | Show, for each **Work Station**, the share of **Touch Time** in the **Station Lead Time** | ↑ | value visible for each **Work Station** | G9 |
| F37 | Show the **Deviations** for each **Work Station** and for each rule, with their reasons | ↓ | ≤ 5 % of pulls | G9 |
| F38 | Compare two periods (before and after a **Value Stream** change) on all measures | ↓ | 1 view | G9 |
| F39 | Design a **Value Stream**: **Work Stations**, **Splits**, **Branches**, **Assembly**, **Blue Bin** count, **People**, **Working Calendar** | ↓ | the software team example in ≤ 30 min | G10 |
| F40 | Change a **Value Stream** while it runs (**Blue Bins**, **People**, **Work Stations**), keep all past events, and date each change | → | 0 lost events, 100 % of changes dated | G10 |
| F41 | Let each **Value Stream** name its own **Demands** and **Pieces**, for example "Feature" and "User Story" | → | free labels for each **Value Stream** | G10 |

---

## 4. Cascade — Goals → Functions → How → Components

- **G1** Client satisfaction, Takt Time visible to everyone  _W:10_ — F1–F5
- **G2** Pull, every **Deviation** visible  _W:9_ — F6–F9
- **G3** One-piece flow at **Takt Time**  _W:8_ — F10–F11
- **G4** Jidoka, stop and fix  _W:8_ — F12–F16, F42
- **G5** A **Person** knows the next thing to do  _W:9_ — F17–F22
- **G6** Levelled **Product Mix**  _W:7_ — F23–F26
- **G7** **Value Stream** at a glance  _W:8_ — F27–F29
- **G8** Recording costs seconds  _W:8_ — F30–F33
- **G9** Flow problems as numbers  _W:8_ — F34–F38
- **G10** Design and change without code  _W:6_ — F39–F41

Core How decisions, shared by many Functions:

- **How H3 — flow events + current state, in one transaction** (chosen, see T1)
  - Serves: F2, F34, F35, F38, F40 (history and measures), F17, F27 (fast reads)
  - Each action appends one flow event to an append-only log, and updates the current-state tables in the same transaction
  - Every measure can be recomputed from the log, for example after a **Working Calendar** change
- **How H1 — current state only** (rejected, see T1)
- **How H2 — full event sourcing** (rejected, see T1)
- **How H5 — Server-Sent Events** (chosen, see T2)
  - Serves: F2, F3, F15, F17, F27, F28 (every open screen updated in ≤ 2 s)
  - Each new flow event in the log is pushed to the open screens of its **Value Stream**; actions still go as normal HTTP requests
  - A screen that reconnects reloads the current state; nothing is lost, because the log is the source of truth
- **How H4 — polling every 2 s** (rejected, see T2)
- **How H6 — WebSockets** (rejected, see T2)

Components that realise these How decisions:

- **C1** SPA — Vite + Vue 3 + TypeScript + Tailwind v4 + DaisyUI
- **C2** API — Gleam (wisp + mist): flow rules, **Deviations**, **Priority List** ordering, Heijunka sequencer
- **C3** Store — SQLite (sqlight): flow event log + current-state tables (H3)
- **C4** Event stream — Server-Sent Events from mist (H5)
- **C5** Deploy — Coolify, docker compose (web + API), on bluebin.app

---

## 6. Roof — Function × Function conflicts

Symbols: `⊗` strong conflict, `×` mild conflict.

| ID | Conflict | Strength | Mitigation |
|----|----------|:--------:|------------|
| R1 | F40 change while running vs F34 exact measures | ⊗ | A change can remove only an empty **Blue Bin**, or a **Work Station** with no **Piece**; measures split at the date of the change |
| R2 | F3, F15, F42 **Andons** vs F19 one next thing | × | **Andons** show on the wall TV and the **Demand** view; on a **Person**'s screen, only their own **Rework** and their **Work Station**'s **Andons** interrupt them |
| R3 | **Deviation** reasons (F6, F8, F9, F14, F25) vs F30 recording costs seconds | × | One-line reason, past reasons suggested, ≤ 10 s (F31) |
| R4 | F25 manual reorder vs F26 levelled **Product Mix** | ⊗ | Accepted by design: each reorder is a **Deviation**, its cost is shown before confirmation, F26 shows the drift |
| R5 | F13 **Rework** pauses its author vs F10 flow at **Takt Time** upstream | × | Accepted: fix first; the pause shows as **Stagnation Time** |
| R6 | F2 **Takt Gap** "as **Working Time** passes" vs H5 push on events | × | The API emits a timer event every minute of **Working Time**; SSE pushes it like a flow event |

---

## 7. Components

| ID | Component | Role | Main Functions | ADR |
|----|-----------|------|----------------|-----|
| C1 | SPA: Vite + Vue 3 + TypeScript + Tailwind v4 + DaisyUI | All screens: **Demands** and **Takt Gap**, **Assignments**, **Value Stream** view (wall TV), **Value Stream** designer, measures | F1, F19, F25, F27, F35, F38, F39 | — |
| C2 | API: Gleam (wisp + mist) | HTTP actions; pull rules and **Deviations**; **Priority List** and **Assignment** ordering; Heijunka sequencer; measures | F6–F26, F30–F34, F40 | — |
| C3 | Store: SQLite (sqlight) | Flow event log and current-state tables, written in one transaction | F34, F38, F40 | [ADR-0002](./docs/adr/0002-flow-event-log-with-current-state.md) |
| C4 | Event stream: Server-Sent Events from mist | Pushes each new flow event to the open screens | F2, F3, F15, F17, F28 | — |
| C5 | Deploy: Coolify, docker compose (web + API), bluebin.app | Hosting | — | — |

---

## 8. Critical performance budget

| Rank | Function | Target | Watched on | If we miss it |
|:----:|----------|--------|------------|---------------|
| 1 | F30 record a flow event | ≤ 2 clicks, ≤ 5 s | Time from opening the screen to confirming the action, measured in the SPA | Quick-action button on each **Assignment**, plus keyboard shortcuts; if events are still skipped, F33 shows the gaps and the **Team Leader** fixes them |
| 2 | F17 / F28 **Assignments** and screens updated | ≤ 2 s | Time from writing the event to the screen update, logged by the API and the SPA | The SPA reloads the current state when SSE is late (H4 polling as fallback) |
| 3 | F34 **Lead Time** = **Touch Time** + **Stagnation Time** | exact | Nightly job that recomputes the measures from the log and compares | The log is the truth: rebuild the current-state tables from it ([ADR-0002](./docs/adr/0002-flow-event-log-with-current-state.md)) |
| 4 | F2 / F3 **Takt Gap** and **Andon** | ≤ 1 min | Time from the timer tick or event to the **Andon** on screen | The **Takt Gap** is also computed when a screen opens, so a missed tick does no harm |
| 5 | F4 delivery forecast | error ≤ 1 working day | Forecast date vs real date, for each finished **Demand** | Show a date range, not one date, until the error goes down |
| 6 | F39 design the software team's **Value Stream** | ≤ 30 min | Time measured in the first real session with the team | Supply a "software team" template, with the **Split** for Web, iOS and Android |

---

## 9. Tradeoffs — Got / Paid / ADR

| ID | Tradeoff | Got | Paid | ADR |
|----|----------|-----|------|-----|
| T1 | Flow events + current state in one transaction (H3), over current state only (H1) and full event sourcing (H2) | Full history; every measure can be recomputed; dated **Value Stream** changes; simple, fast reads for daily screens | Two writes for each action that must stay consistent; the log grows forever | [ADR-0002](./docs/adr/0002-flow-event-log-with-current-state.md) |
| T2 | Server-Sent Events (H5), over polling (H4) and WebSockets (H6) | Updates in less than 1 s; standard browser reconnect; one direction is all we need | One open connection for each screen; actions and updates use two channels | — |
| T3 | SQLite (C3), over Postgres | One file, real transactions, no database server; fits the one-writer flow of a team | Single writer: a move to Postgres when many teams share one instance (H3 does not change) | — |

### Tensions being watched (unresolved by design)

- **Single SQLite writer.** One instance serves one or a few teams. **Trigger to revisit:** many teams share one instance, or write latency breaks F17.
- **Standardized Work out of the app.** No Definition of Done per **Work Station**. **Trigger to revisit:** **Rework** shows that **Work Stations** disagree on what "done" means.
- **Acceptance of a whole Feature.** Each **Piece** goes to production alone; there is no **Demand**-level acceptance. **Trigger to revisit:** a **Client** cannot accept value one **Piece** at a time.
- **No personal notifications.** Only **Andons** interrupt. **Trigger to revisit:** stale **Assignments** (F33) stay above 5 %.

---

## 10. Inconsistencies spotted and fixed

- **Soft pull rules vs "never" in the glossary and in G2.** F6, F8 and F9 warn and do not block, but [CONTEXT.md](./CONTEXT.md) said a **Person** never starts work without a **Kanban**, and G2 said overproduction is impossible. Resolved: new term **Deviation** (a broken rule, with a required reason, visible at once); the glossary now says "only as a **Deviation**"; G2 now says "never silent".
- **Help Downstream target.** During the glossary session, Help Downstream was said to point at the **Work Station** with the most **Starvation Time**. A starved **Work Station** is downstream of the problem, not the problem. Resolved: F22 points at the nearest downstream **Work Station** that holds up the flow, which matches the **Help Downstream** definition.
- **F9 and the automatic pause.** F9 also warned before a second active **Assignment**, but taking an **Assignment** pauses the current one automatically, so a second active one cannot happen. Resolved: F9 covers only the second **Piece** in a **Blue Bin**.

---

## How to keep this honest

- When a new ADR lands, add its components to the component map and re-score the affected rows.
- When a measurement returns numbers, update the targets and the performance budget.
- Goals change rarely; functions change with each release; matrices are recomputed when either side changes.
- If a section becomes empty after edits, delete it.
