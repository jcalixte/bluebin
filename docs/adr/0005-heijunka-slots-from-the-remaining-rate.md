# Heijunka slots come from the remaining rate

Status: accepted

The Heijunka Sequence gives each Piece in the Backlog an ideal slot. A Demand spreads the Pieces it has left in the Backlog evenly over the Working Time it has left until its due date, and the slot of its k-th Piece is (k − 0.5) of that interval from now. We chose this over absolute slots, where the n-th Piece of a Demand goes n Takt Times after the Demand started. With absolute slots, a Demand behind its Takt Time has all its slots in the past, so all its Pieces go ahead of every other Demand in one block, and the Demands that are on time stop until it catches up. That is not a levelled Product Mix. The remaining rate is how the Toyota Goal Chasing Method works: the plan is made again from the demand that is left. The 0.5 puts each Piece at the middle of its interval, so the last Pieces of different Demands do not all tie on the due date.

## Consequences

- A late Demand gets a higher rate, so it gets more slots, still mixed with the other Demands. It recovers more slowly than with absolute slots, and its Andon can stay on longer.
- The Takt Gap and the Andon still use the Takt Time of the Demand (Working Time from start to due date ÷ Pieces asked). The Andon says that a Demand is late; the Heijunka Sequence gives the levelled way to recover.
- A Demand past its due date keeps one working day, so all its Pieces go first.
