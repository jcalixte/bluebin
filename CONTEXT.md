# Bluebin

A pull system for software teams, built on Toyota Production System principles: Takt Time, one-piece flow, Heijunka and Just-In-Time. Teams design their Value Stream and then run their daily work in it. Work moves only when a downstream Work Station signals that it can take more.

## Language

### Flow

**Value Stream**:
The ordered chain of Work Stations that a Piece crosses from Demand to production.
_Avoid_: value flow, kanban system, pipeline, workflow, board

**Work Station**:
A team of People that does one step of the Value Stream.
_Avoid_: column, stage, step, lane

**Demand**:
A request for a quantity of Pieces by a due date, for example a Feature.
_Avoid_: request, ticket, epic

**Client**:
The person or group that asks for a Demand and receives its Pieces in production.
_Avoid_: customer, stakeholder, user, requester

**Backlog**:
The queue where Pieces wait, in Heijunka Sequence, for a Kanban from the first Work Station.
_Avoid_: inbox, todo, icebox

**Piece**:
The matter that a Work Station transforms, and that follows the Kanbans through the Value Stream, for example a User Story.
_Avoid_: card, ticket, task, item

**Sub-Piece**:
A part of a Piece, created by a Split, that must rejoin the other parts before the Piece is complete, for example the iOS part of a User Story.
_Avoid_: subtask, child ticket

**Split**:
The point where a Piece divides into Sub-Pieces that flow in parallel, one per Branch.
_Avoid_: fork

**Branch**:
A chain of one or more Work Stations between a Split and its Assembly, that transforms one Sub-Piece.
_Avoid_: lane, track, path

**Assembly**:
The explicit action by which the Work Station after the Branches pulls all Sub-Pieces of one Piece together, to make the Piece complete again.
_Avoid_: restructure, merge, join

**Kanban**:
A signal that authorizes one Work Station to make one more Piece, sent when a downstream Work Station pulls a Piece out of a Blue Bin.
_Avoid_: card, ticket, task

**Blue Bin**:
A container that holds one finished Piece until the downstream Work Station pulls it.
_Avoid_: done column, outbox, buffer

**Rework**:
The repair of a defect in a Piece, found downstream of the Work Station that made it.
_Avoid_: bug fix, fix, back to dev, reopen

**Deviation**:
An action that breaks a pull rule or the Heijunka Sequence after a warning, recorded with its reason.
_Avoid_: override, exception, violation, bypass

**Help Downstream**:
The act of a Person without a Kanban helping the downstream Work Station that holds up the flow, instead of starting new work.
_Avoid_: swarm, help out, firefighting

### Pace

**Takt Time**:
The available Working Time divided by the number of Pieces asked for in that time, for one Demand or for the whole Value Stream.
_Avoid_: velocity, cycle time

**Takt Gap**:
The number of Pieces that a Demand is ahead of (+) or behind (−) its Takt Time at a given moment.
_Avoid_: delay, slippage, burn-down, variance

**Andon**:
A signal, visible to all People of a Value Stream, that the flow has a problem, for example a Demand behind its Takt Time.
_Avoid_: alert, alarm, notification

**Heijunka**:
The levelling of volume and Product Mix of the Pieces that leave the Backlog.
_Avoid_: load balancing, smoothing

**Heijunka Sequence**:
The computed order of the Pieces in the Backlog that levels the Product Mix, from the Takt Time of each active Demand.
_Avoid_: priority, ranking, backlog order

**Product Mix**:
The proportion of Pieces from different Demands in the flow.
_Avoid_: ratio, allocation

### Measures

**Working Calendar**:
The working days, working hours and holidays of a Value Stream.
_Avoid_: schedule, business hours, opening hours

**Calendar Time**:
Elapsed time on the clock, nights, weekends and holidays included.
_Avoid_: wall time, real time

**Working Time**:
Elapsed time counted only inside the Working Calendar.
_Avoid_: business time, office time

**Lead Time**:
The time from entering the Backlog to reaching production, measured for each Piece and for each Demand (until its last Piece).
_Avoid_: cycle time, delivery time

**Touch Time**:
The time People actually spend transforming a Piece at a Work Station, between pulling it in and putting it in a Blue Bin, without pauses.
_Avoid_: processing time, work time, cycle time

**Rework Time**:
The Touch Time spent on Rework, counted against the Work Station that made the defect.
_Avoid_: bug time, fix time

**First Pass Yield**:
The share of Pieces that leave a Work Station and need no Rework later.
_Avoid_: quality rate, success rate, defect rate

**Stagnation Time**:
The time a Piece waits with nobody transforming it: in the Backlog, in a Blue Bin, or paused.
_Avoid_: idle time, wait time, blocked time

**Station Lead Time**:
The time from a Work Station pulling a Piece in to the downstream Work Station pulling it out of the Blue Bin.
_Avoid_: stage time, column time

**Starvation Time**:
The time a Work Station holds a Kanban but has no Piece to pull.
_Avoid_: idle time, blocked time, starving

**Andon Time**:
The time an Andon stops a Work Station, from its raise until its Team Leader closes it.
_Avoid_: downtime, stop time, outage

### People

**Person**:
Someone who belongs to one or more Work Stations.
_Avoid_: user, member, resource

**Team Leader**:
A Person of a Work Station who answers its Andons.
_Avoid_: manager, lead, supervisor, dispatcher

**Priority List**:
The ordered list of Rework and Kanbans that one Work Station must do next.
_Avoid_: my kanban, personal kanban, board, inbox, to-do, work queue

**Assignment**:
The link between one item of a Work Station's Priority List and the one Person of that Work Station who does it.
_Avoid_: allocation, dispatch, affectation, ownership

**Workspace**:
All the data of one Value Stream, private to the signed-in account that owns it. Visitors who are not signed in share the one public Workspace.
_Avoid_: tenant, organization, board

## Relationships

- A **Value Stream** is an ordered chain of **Work Stations**; a **Split** opens parallel **Branches** and an **Assembly** closes them
- A **Work Station** has one or more **People**; a **Person** belongs to one or more **Work Stations**
- A **Work Station** has a configured number of **Blue Bins**; each **Blue Bin** holds zero or one **Piece**; a second **Piece** is a **Deviation**
- A **Work Station** never has more **Kanbans** than empty **Blue Bins**
- A **Kanban** targets exactly one **Work Station**
- A **Demand** is decomposed into one or more **Pieces**; a **Piece** belongs to exactly one **Demand**
- A **Demand** comes from exactly one **Client**; a **Client** can have many **Demands**
- A **Demand** has one **Takt Time**: its available Working Time divided by its number of **Pieces**
- The **Takt Time** of the **Value Stream** combines all active **Demands**: 1 ÷ (sum of 1 ÷ **Takt Time** of each active **Demand**); it changes when a **Demand** enters or ends
- A **Work Station** compares its **Touch Time** per **Piece** with the **Takt Time** of the **Value Stream**, not of one **Demand**
- A **Piece** waits in the **Backlog**, then flows alone through the **Value Stream** (one-piece flow)
- The **Heijunka Sequence** decides which **Piece** leaves the **Backlog**; a **Kanban** from the first **Work Station** decides when
- In the **Heijunka Sequence**, each **Piece** has an ideal slot at a multiple of its **Demand**'s **Takt Time**; the earliest slot goes first, then the earliest due date, then first-in, first-out
- Inside one **Demand**, **Pieces** keep first-in, first-out order
- A **Person** can reorder the **Heijunka Sequence** by hand for urgent work, only as a **Deviation**
- A manual reorder moves the next **Piece** of one **Demand** to the top of the **Backlog**, behind the **Pieces** already moved there; **Pieces** further back in the same **Demand** keep their order
- A **Split** opens one **Branch** per **Sub-Piece**; each **Branch** ends at the same **Assembly**
- A **Branch** can hold several **Work Stations**, for example iOS then QA iOS
- A **Piece** is complete only when all its **Sub-Pieces** pass the **Assembly**
- An **Assembly** is possible only when every **Sub-Piece** of the **Piece** is in the last **Blue Bin** of its **Branch**, and needs a **Kanban** of the **Work Station** after the **Branches**
- One **Assembly** sends one **Kanban** to the last **Work Station** of each **Branch**
- At a **Split**, each **Branch** pulls its own **Sub-Piece** with its own **Kanban**; the **Piece** leaves the upstream **Blue Bin** only when all its **Sub-Pieces** are pulled
- Across a **Split**, the **Lead Time** of a **Piece** is set by its slowest **Sub-Piece**
- Every **Work Station** transforms one **Piece** at a time; no **Work Station** waits for all **Pieces** of a **Demand**
- Each **Piece** goes to production as soon as it is complete, at the pace of its **Demand**'s **Takt Time**
- **Lead Time** = **Touch Time** + **Stagnation Time**
- **Lead Time** = the **Backlog** wait + the sum of the **Station Lead Times**
- **Station Lead Time** = **Touch Time** at that **Work Station** + the wait in its **Blue Bin**
- **Lead Time**, **Station Lead Time**, **Stagnation Time**, **Starvation Time** and **Andon Time** are shown in **Calendar Time** by default, and in **Working Time** as a second view
- **Touch Time** is net time, so it is the same in both views
- **Takt Time** always uses **Working Time**
- The **Takt Gap** of a **Demand** = its **Pieces** in production − the elapsed **Working Time** ÷ its **Takt Time**
- A **Demand** with a **Takt Gap** of −1 or less raises an **Andon**
- A **Rework** that waits one hour of **Working Time** with no active **Assignment** raises an **Andon** on the **Work Station** that made the defect
- Any **Person** can raise an **Andon** on their **Work Station**; it stops that **Work Station** until its **Team Leader** closes it
- While an **Andon** stops a **Work Station**, its **People** pull a new **Piece** only as a **Deviation**; pull spreads the stop upstream and downstream by itself
- A **Work Station** has exactly one **Team Leader**; a **Person** can be **Team Leader** of several **Work Stations**
- A **Team Leader** answers **Andons** and never pushes **Assignments**
- A **Value Stream** has exactly one **Working Calendar**
- A **Value Stream** can change while it runs: only an empty **Blue Bin** or a **Work Station** with no **Piece**, open **Rework** or open **Andon** can go, and each change is dated in the flow log
- A new **Blue Bin** brings one **Kanban** to its **Work Station**; a removed empty **Blue Bin** takes one back
- **Starvation Time** belongs to a **Work Station**, never to a **Piece**, and is not part of the **Lead Time**
- The **Andon Time** of a **Value Stream** is the time at least one of its **Work Stations** is stopped; stops at the same time count once
- A **Person** transforms at most one **Piece** at a time; when another **Piece** comes into their hands, the one nearest to production stays active and the other pauses, and the paused time is **Stagnation Time**. On a tie, the new **Piece** waits: finishing beats starting
- A **Work Station** transforms as many **Pieces** at the same time as it has **People** working
- Priority works in two stages: first which **Work Station** must work, then which **Person** of that **Work Station** does it (**Assignment**)
- Stage 1: across the **Value Stream**, the **Work Station** nearest to production comes first
- A **Work Station** has one **Priority List**, made of its **Rework** and its **Kanbans**, ordered: **Rework** first, then the oldest **Kanban**
- Stage 2: an **Assignment** gives one item of a **Priority List** to one **Person** of that **Work Station**
- A **Person** sees the **Assignments** they hold in all their **Work Stations**; the **Assignment** in the **Work Station** nearest to production comes first
- For a **Kanban**, a free **Person** takes the top item of the **Priority List** of their **Work Station** nearest to production; nobody pushes a **Kanban** to a **Person**
- For **Rework**, the **Assignment** goes by default to the **Person** who transformed the **Piece** at that **Work Station**
- Any **Person** of a **Work Station** can reassign an **Assignment** to another **Person** of the same **Work Station**
- A **Person** has at most one active **Assignment**; the others are paused
- **Rework** pauses the **Piece** that the **Person** is transforming upstream
- A **Piece** never moves backward: the **Work Station** that finds a defect raises **Rework** and names the **Work Station** that made it; a **Person** of that **Work Station** comes to repair the **Piece** where it is
- While **Rework** waits or runs, the downstream **Work Station** does not pull a new **Piece**; it does **Help Downstream** or waits
- **Rework** is **Touch Time** of the **Piece**, and also **Rework Time** of the **Work Station** that made the defect
- Each **Rework** lowers the **First Pass Yield** of the **Work Station** that made the defect
- Inside one **Work Station**, the **Piece** to pull is the first one in the upstream **Blue Bin**, which keeps the **Heijunka Sequence**
- A **Deviation** always has a reason given by the **Person**, and is visible to everyone at once
- A **Person** with no **Kanban** does **Help Downstream** when possible, and waits otherwise; a **Person** starts work without a **Kanban** only as a **Deviation**

## Example dialogue

> **Dev:** "Both **Blue Bins** of Development are full and I just finished my **Piece**. What do I do?"
> **Domain expert:** "You have no **Kanban**, so you don't start a new **Piece**. **Help Downstream** on QA if you can, otherwise wait. When QA pulls a **Piece** out of a **Blue Bin**, Development gets a **Kanban**."

> **Dev:** "Tech Conception is done. Does the **Piece** go to Frontend?"
> **Domain expert:** "It reaches a **Split**: the web, iOS and Android **Branches** each pull a **Sub-Piece**, and each **Branch** has its own QA. UAT starts only with the **Assembly**, when all three **Sub-Pieces** are ready."

> **Dev:** "My **Piece** sat in the Development **Blue Bin** all night, and QA had nothing to do all morning. Is that the same waste?"
> **Domain expert:** "No. The night is the **Stagnation Time** of the **Piece**. The morning is the **Starvation Time** of QA. Only the first one is inside the **Lead Time**."

> **Dev:** "QA iOS found a defect in US-3. Do I move it back to iOS?"
> **Domain expert:** "No, a **Piece** never moves backward. QA iOS raises **Rework** against iOS. The **Rework** goes to the top of the iOS **Priority List**, Alice gets the **Assignment**, pauses her current **Piece**, and repairs US-3 where it is. The repair counts as **Rework Time** for iOS."

## Flagged ambiguities

- "value flow" and "kanban system" — resolved: both mean **Value Stream**. "Kanban system" is avoided because **Kanban** is the signal, not the whole design.
- "user" was used for the Person who moves work — resolved: in the domain this is a **Person**; "user" is reserved for the app account, if ever needed.
- "piece" vs **Kanban** — resolved: distinct. The **Piece** is the matter; the **Kanban** is the signal that the **Piece** follows.
- "blue bins are configurable" — resolved: the number of **Blue Bins** is configured per **Work Station**; one **Blue Bin** holds one **Piece** (one-piece flow).
- "processing time" — resolved: **Touch Time**.
- "restructured" (Sub-Pieces coming back together) — resolved: **Assembly**.
- Feature / User Story vs **Demand** / **Piece** / **Sub-Piece** — resolved: a Feature is a **Demand**, a User Story is a **Piece**, a platform part (web, iOS, Android) is a **Sub-Piece**. "Feature" and "User Story" are the software team's names, not domain terms.
- "the Demand is one piece" — resolved: a **Demand** is decomposed into **Pieces**, so that **Heijunka** can mix **Pieces** of different **Demands**.
- **Stagnation Time** between two **Work Stations** — resolved: the wait from "Kanban sent" to "pulled in" is the **Starvation Time** of the **Work Station**, not the **Stagnation Time** of the **Piece**. This stops the same wait being counted twice.
- Pauses during **Touch Time** — resolved: a **Person** transforms one **Piece** at a time, so a new **Piece** pauses the current one only when it is nearer to production; otherwise the new **Piece** starts paused. **Touch Time** is net time; the paused time is **Stagnation Time**.
- Time measures and the working calendar — resolved: measures show **Calendar Time** by default and **Working Time** as a second view; **Takt Time** uses **Working Time** only.
- **Takt Time** of a **Demand** vs of the **Value Stream** — resolved: one term, two scopes. The **Takt Time** of the **Value Stream** is computed from all active **Demands**.
- **Heijunka** order — resolved: computed as the **Heijunka Sequence**, released only on a **Kanban** (pull, not a timed pitch), with manual reorder allowed.
- "Heijunka sequencer" — the part of the app that computes the **Heijunka Sequence**; a design name, not a domain term.
- "branch" — resolved: **Branch** is the chain of **Work Stations** between a **Split** and an **Assembly**; "fork" is avoided.
- **Assembly** — resolved: an explicit action, not a **Work Station**; it has no **People** and no **Blue Bins**.
- "swarm" — resolved: renamed **Help Downstream**, clearer for the team.
- "Final Inspection" of a whole **Demand** — rejected: with **Heijunka**, the **Pieces** of one **Demand** arrive mixed with others, so waiting for the last one adds **Stagnation Time** and breaks the **Takt Time**. It also blocks the upstream **Blue Bins**. Like a car on a Toyota line, each **Piece** goes to production alone.
- UAT of a whole Feature — deferred: the software analogy for Feature-level acceptance comes later.
- **Kanbans** at a **Split** and an **Assembly** — resolved: a **Branch** gets a new **Kanban** only from an **Assembly** of a complete **Piece**, never when its own **Blue Bin** empties alone. A fast **Branch** runs ahead only as a **Deviation**; normally its **People** **Help Downstream**.
- Order of a **Person**'s **Kanbans** — resolved: **Rework** first, then downstream first, then the oldest **Kanban**. Finishing beats starting, also when a **Person** pulls a new **Piece** upstream while they hold one downstream.
- Where **Rework** happens — resolved: the **Piece** stays downstream and the **Person** goes to it. Moving it back ("reopen") would break the **Blue Bin** limits and the **Kanban** counts.
- "her kanban" (the list a **Person** sees) — resolved: a **Kanban** is one signal. The **Priority List** belongs to a **Work Station** and holds its **Kanbans** and **Rework**; a **Person** sees their **Assignments**.
- "affectation" — resolved: **Assignment**.
- Hard vs soft pull rules — resolved: the pull rules are the norm, and a **Person** can break one only as a **Deviation**, with a reason. "Never" in this glossary means "never without a **Deviation**" for the pull rules. A manual reorder of the **Heijunka Sequence** is also a **Deviation**.
- "team leader" — resolved: **Team Leader** answers **Andons**; it does not assign work, so pull stays intact.
- "stop the line" — resolved: an **Andon** stops one **Work Station**, not the whole **Value Stream**; pull spreads the stop.
- "client" — resolved: **Client** is who asks for a **Demand**; "user" stays reserved for the app account.
- Who makes the **Assignment** — resolved: a **Person** takes a **Kanban** (pull); **Rework** goes to its author by default; the team can reassign. No team lead pushes work.
