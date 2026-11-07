# Split, Sub-Piece and the Kanban that comes back

Design for how Bluebin runs a Split: how two Branches pull the same Piece, what
each one carries away, and how many Kanbans travel upstream.

Terms in **bold** are defined in [CONTEXT.md](../../../CONTEXT.md). Functions
referenced as F7, F22 and so on are in [DESIGN.md](../../../DESIGN.md) §2.

## Intent

The software-team **Value Stream** that Bluebin is built for has a **Split**:
Tech Conception feeds an Android **Branch** and a Web **Branch**, which rejoin at
an **Assembly**. Bluebin names Split, Branch, Sub-Piece and Assembly in
CONTEXT.md and commits to them in DESIGN.md (F7, F8, F39), but none of them
exist in the data model or in the running code. Today a Split is only a visual
accident: two **Work Stations** that happen to share a `position`.

The gap has already produced a wrong number on the screen. The link between
Step 2 and Step 3 reads `3 KANBAN`, which tells Sofia at Tech Conception to
build three more **Pieces**. One Piece feeds both Branches. Acting on that
number is overproduction, which is the single thing pull exists to prevent.

## Why now

The Kanban count is the number a Team Leader acts on. A Value Stream with a
Split is the first one the tool will meet in real use (DESIGN.md §8 row 6: the
software-team template ships with a Split for Web, iOS and Android). Shipping a
Split that miscounts Kanbans makes the tool worse than the physical board it
replaces.

## Goals

1. One Piece crossing a Split produces exactly one Kanban upstream, no matter
   how many Branches pull it.
2. Each Branch pulls on its own schedule, without waiting for the others.
3. Each Branch carries away its own **Sub-Piece**, linked to the parent Piece,
   so the Assembly has something to rejoin later.
4. A **Person** with no Kanban, stalled by a lagging Branch, is pointed at that
   Branch as a **Help Downstream** target (F22).
5. The Kanban number shown on every link is the number that link actually
   carries.

## Non-goals

- **The Assembly itself.** Pulling Sub-Pieces back together, F7's "one Kanban to
  each Branch for each Assembly", and F8's warning and **Deviation** are a
  separate change. The data model here must not block them; it does not
  implement them.
- **Designing a Value Stream in the UI** (F39). Splits stay seeded in SQL.
- **Nested Splits.** A Branch that itself splits is out of scope. The model
  should not make it impossible, but nothing here needs to support it.
- **Measures.** **Starvation Time** at a station stalled by a Split (F34) is
  not computed here.

## Anti-goals

Things that would make this a failure even if the code works:

- Any screen that tells a station to make more Pieces than are wanted. A Kanban
  count that is too high is worse than no count.
- A Branch forced to wait for a sibling Branch before it can start. That
  converts a Split into a queue and hides the lag instead of showing it.
- A Piece disappearing from a Blue Bin before every Branch has had it. That
  starves a Branch silently.

## How a Split runs

Decided in conversation. These are the rules the builder implements.

### The Split happens at the pull

Tech Conception finishes one Piece, US-9, and puts it in one of its **Blue
Bins**. It does not divide the Piece and does not know about Branches. US-9 sits
in that bin as one Piece.

Android holds a Kanban and pulls US-9. At that instant, and only then, a
Sub-Piece is created: the Android part of US-9, linked to US-9 as its parent.
Android works on the Sub-Piece. US-9 itself never enters a Branch.

Web does the same later, producing the Web Sub-Piece of US-9.

### Branches pull independently

Android does not wait for Web. If Android holds a Kanban and Web does not,
Android pulls and starts; Web pulls when it frees up. This raises no warning and no
Deviation: it is normal operation.

### The Blue Bin frees on the last pull

US-9 stays in Tech Conception's Blue Bin after Android pulls, marked as already
pulled by the Android Branch. The bin is not empty and cannot take a new Piece.
Only when every Branch of the Split has pulled US-9 does the bin free.

### One Kanban upstream, on the last pull

F7 says "one **Kanban** upstream for each pull out of a **Blue Bin**". At a
Split that sentence needs its qualifier: the Kanban goes upstream when the bin
frees, which is the last Branch's pull. Android's pull sends nothing. Web's pull
sends one Kanban to Tech Conception.

This keeps F7's invariant (Kanbans ≤ empty Blue Bins) true at Tech Conception,
and it is what makes goal 1 hold.

### The stall is the signal

While Web lags, US-9 occupies one of Tech Conception's two Blue Bins, so Sofia's
Kanban count is capped at one and eventually reaches zero. Sofia stops.

This is intended: the lag shows as the station before the Split running out
of work, rather than as a queue in front of Web. A Person with no Kanban
Helps Downstream (F22), and the Branch that has not yet pulled is exactly where
the help belongs.

So F22's list of "holds up the flow" conditions gains a third entry, next to
open **Rework** and a full Blue Bin: _a Branch of a Split that has not yet
pulled a Piece its sibling Branches already pulled._

## The counting bug on the link

Separate from the Split rules, and the visible symptom that started this.

A station's badge counts the Kanbans it **holds**, and those arrived from the
station _downstream_ of it. Android's two Kanbans came from the Assembly below,
not from Tech Conception.

`src/views/ValueStreamView.vue:61` labels the arrow entering a column with that
column's own count, and the comment at line 24 justifies it by treating
"Kanbans this station holds" and "Kanbans this station sent upstream" as one
quantity. They are two quantities. The arrow between Step 2 and Step 3 carries
the Kanbans Tech Conception holds (one), not the three held by Android and Web.

Fix the attribution: each link is labelled with the held Kanban count of the
column it points back into. The sum at line 26 then disappears, because the
column before a Split has one station in it.

## Constraints

- **ADR-0001, Pieces never move backward.** A Sub-Piece created at the pull
  moves forward only. Rework is repair in place, not a move back.
- **ADR-0002, flow event log with current state.** Every pull is already a
  `flow_event` (F30). The partial-pull state and the Sub-Piece creation are
  current-state tables derived from events, not a parallel source of truth.
- **F7 invariant: Kanbans ≤ empty Blue Bins, at all times.** Must hold at the
  station before the Split throughout a partial pull.
- Stack as it stands: Gleam + wisp + mist + sqlight on SQLite, Vue 3 + Tailwind
  v4 + DaisyUI. Schema changes go in a new `schema_v3` constant alongside
  `schema_v1` and `schema_v2` in `backend/src/bluebin/db.gleam`; those are
  append-only, run with `create table if not exists`.
- Red and green stay reserved for OK/NOK status only.

## What is left to the builder

The shape of the data is the builder's call, within these rules:

- A Sub-Piece needs a parent Piece and a Branch. Whether that is a `sub_piece`
  table or columns on `piece` is open; the Assembly will later need to find all
  Sub-Pieces of one Piece, so that lookup should be cheap.
- A Blue Bin needs to record which Branches have pulled its Piece. Open whether
  that lives on the bin, on the pull events, or is derived from the Sub-Pieces
  that exist for that Piece. Deriving it is attractive, since a Sub-Piece
  existing _is_ the record that its Branch pulled.
- How a Split is recognised. `work_station.branch` and a shared `position`
  already exist; whether a Split needs its own row is open.
- Test coverage: the Kanban count after a partial pull, and after the last
  pull, is the behaviour that can break silently and must be tested. The arrow
  label is a display detail and does not need a test.

## Calls made while writing this

Marked so they can be overruled on reading.

- The Assembly is deferred rather than designed here, to keep this change to
  one end of the Branch.
- F22's new Help Downstream condition is stated as a rule but its UI is not
  specified; F19 and F22 own that screen.
- `WorkStationCard.vue:33` has a tooltip reading "2 Kanban(s)" against a badge
  reading "2 Kanban". Fix the tooltip to match the badge while in the file.
