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
  piece: string | null
  demand: string | null
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
  people: Member[]
  inProgress: { piece: string; demand: string; person: string | null }[]
  rework: { piece: string; description: string }[]
  kanbans: number
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
