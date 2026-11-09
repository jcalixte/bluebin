/**
 * Who plays which Team Member in a shared Simulation: Team Member id → peer id of the Guest. The
 * Host plays the owner and every Team Member with no seat.
 */
export type Seats = Record<string, string>

/** The Team Member a peer plays, or `null`. */
export function seatOf(seats: Seats, peer: string): string | null {
  return Object.keys(seats).find((teamMember) => seats[teamMember] === peer) ?? null
}

/** Frees the seat of a peer, as when it leaves. */
export function release(seats: Seats, peer: string): Seats {
  return Object.fromEntries(Object.entries(seats).filter(([, one]) => one !== peer))
}

/**
 * The peer takes the seat of a Team Member and frees its own. `""` only frees it. Answers the new
 * seats, or why the peer cannot take it.
 */
export function claim(
  seats: Seats,
  peer: string,
  teamMember: string,
  teamMembers: string[],
): Seats | string {
  if (teamMember === "") return release(seats, peer)
  if (!teamMembers.includes(teamMember)) return "This Team Member is no longer in the Line."
  const holder = seats[teamMember]
  if (holder !== undefined && holder !== peer) return "Another Guest took this Team Member."
  return { ...release(seats, peer), [teamMember]: peer }
}

/** Drops the seats of Team Members removed from the Line. */
export function keepPresent(seats: Seats, teamMembers: string[]): Seats {
  return Object.fromEntries(
    Object.entries(seats).filter(([teamMember]) => teamMembers.includes(teamMember)),
  )
}
