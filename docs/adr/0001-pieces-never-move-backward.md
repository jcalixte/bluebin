# A Piece never moves backward

When a Work Station finds a defect, the Piece stays where it is. The Work Station raises Rework against the Work Station that made the defect, and a Person of that Work Station comes to repair the Piece in place. We chose this over "reopen", where the Piece goes back upstream, because a Piece that moves backward breaks the Blue Bin limits and the Kanban counts: the upstream Blue Bins may be full, and the upstream Work Station may hold no Kanban. Keeping the Piece in place also keeps the defect visible where it was found (Jidoka) and charges the repair to its source as Rework Time and First Pass Yield.

## Consequences

- Rework is not a Kanban. It enters the Priority List of the Work Station that made the defect, first, and goes by default to the Person who made the Piece; the team can reassign it.
- While Rework is open, the Work Station that found it does not pull a new Piece, except as a Deviation.
- The repair time is Touch Time of the Piece, so Lead Time = Touch Time + Stagnation Time stays exact.
