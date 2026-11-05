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

export type BlueBin = {
  slot: number
  id: string | null
  piece: string | null
  demand: string | null
  /** At a Split, the Branches that already pulled their Sub-Piece of it. */
  pulledBy: string | null
}

export type Overflow = {
  id: string
  piece: string
  demand: string
}

export type Deviation = {
  rule: string
  piece: string | null
  reason: string
  at: string
}

export type Member = {
  id: string
  name: string
  busy: boolean
}

export type InProgressPiece = {
  id: string
  piece: string
  demand: string
  person: string | null
  personId: string | null
  paused: boolean
}

export type Rework = {
  id: string
  piece: string
  description: string
  /** The Work Station that found the defect and holds the Piece. */
  foundBy: string
  assignee: string | null
  assigneeId: string | null
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
  inProgress: InProgressPiece[]
  rework: Rework[]
  /** A fraction in 0..1; null until a Piece has left. */
  firstPassYield: number | null
  reworkHours: number
  deviations: Deviation[]
  kanbans: number
}

/** What a reorder of the Heijunka Sequence costs one Demand. */
export type ReorderEffect = {
  demand: string
  label: string
  /** Places its next Piece moves: positive is later. */
  places: number
  hours: number
  taktGap: number
}

export type FlowConfirm = {
  confirm: string
  message: string
  effects?: ReorderEffect[]
}

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

/** `stations` is ordered nearest to production first. */
export type Person = {
  id: string
  name: string
  stations: string[]
}

/** One Assignment of a Person is active; the others wait, paused. */
export type Assignment =
  | {
      kind: "rework"
      id: string
      piece: string
      station: string
      stationName: string
      active: boolean
      foundBy: string
      description: string
    }
  | {
      kind: "piece"
      id: string
      piece: string
      station: string
      stationName: string
      active: boolean
    }

export type NextThing =
  | { kind: "continue"; assignment: Assignment }
  | { kind: "take_rework"; rework: string; piece: string; station: string; stationName: string }
  | { kind: "take_kanban"; station: string; stationName: string }
  | { kind: "help_downstream"; station: string; stationName: string; because: string }
  | { kind: "wait" }

/** A Priority List is ordered Rework first, then the oldest Kanban. */
export type PriorityItem =
  | { kind: "rework"; id: string; piece: string; description: string; assignee: string | null }
  | { kind: "kanban"; id: string; since: string }

export type PriorityList = {
  station: string
  name: string
  people: { id: string; name: string }[]
  items: PriorityItem[]
}

export type PersonView = {
  person: { id: string; name: string }
  next: NextThing
  assignments: Assignment[]
  priorityLists: PriorityList[]
}

export type BacklogPiece = {
  id: string
  reference: string
  demand: string
  demandLabel: string
  client: string
  dueOn: string
  slotHours: number
  urgent: boolean
  canBeUrgent: boolean
}

export type MixCell = {
  day: string
  planned: number
  real: number
  onPlan: boolean
}

export type MixRow = {
  demand: string
  label: string
  cells: MixCell[]
}

/** `sequence` is the Heijunka Sequence: its first Piece leaves the Backlog next. */
export type Backlog = {
  taktTimeHours: number
  sequence: BacklogPiece[]
  mix: MixRow[]
}
