/** A Demand as the API reports it, with its Takt Time and Takt Gap. */
export type Demand = {
  id: string
  label: string
  client: string
  dueOn: string
  piecesAsked: number
  piecesProduced: number
  workingDaysTotal: number
  workingDaysElapsed: number
  taktTimeHours: number
  taktGap: number
  andon: boolean
}

/** One Blue Bin slot of a Work Station; `piece` is null when the bin is empty. */
export type BlueBin = {
  slot: number
  id: string | null
  piece: string | null
  demand: string | null
  /** At a Split, the Branches that already pulled their Sub-Piece of it. */
  pulledBy: string | null
}

/** A Piece a Deviation put in a Blue Bin that was already full (F9). */
export type Overflow = {
  id: string
  piece: string
  demand: string
}

/** A pull rule broken on purpose, with the reason the Person gave (F6, F31). */
export type Deviation = {
  rule: string
  piece: string | null
  reason: string
  at: string
}

/** A Person of a Work Station, busy when they transform a Piece there. */
export type Member = {
  name: string
  busy: boolean
}

export type WorkStation = {
  id: string
  name: string
  position: number
  branch: string | null
  blueBinCount: number
  teamLeader: string | null
  blueBins: BlueBin[]
  overflow: Overflow[]
  people: Member[]
  inProgress: { id: string; piece: string; demand: string; person: string | null }[]
  rework: { piece: string; description: string }[]
  deviations: Deviation[]
  kanbans: number
}

/** A pull rule the API warns about: the action goes through only with a
 *  reason, and is then recorded as a Deviation. */
export type FlowConfirm = {
  confirm: string
  message: string
}

/** A named position in the chain; a Split puts several Work Stations on one. */
export type Step = {
  position: number
  name: string
}

export type ValueStream = {
  stations: WorkStation[]
  steps: Step[]
  taktTimeHours: number
  demandsBehind: number
}
