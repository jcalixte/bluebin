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
  /** `YYYY-MM-DD`; null until a Piece of the Demand reached production. */
  forecastOn: string | null
  /** Working days from `dueOn` to `forecastOn`: above 0 is late, 0 or less is on time. */
  forecastLateDays: number | null
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
  teamMember: string | null
  teamMemberId: string | null
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
  teamMembers: Member[]
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

/** A stop raised by hand (F42), or a Rework that waits with nobody on it (F15). */
export type Andon =
  | {
      kind: "stop"
      station: string
      stationName: string
      raisedBy: string | null
      raisedAt: string
      teamLeaderId: string | null
      teamLeader: string | null
    }
  | {
      kind: "rework_waits"
      station: string
      stationName: string
      rework: string
      piece: string
      waitingHours: number
    }

/** An active Assignment with no event for more than one working day. */
export type StaleAssignment = {
  kind: "piece" | "rework"
  id: string
}

/** `capacityHours` is the average Touch Time per Piece over the last 7 days, divided by its Team Members. */
export type Bottleneck = {
  station: string
  capacityHours: number | null
  slower: boolean
  fullInFront: boolean
}

export type Line = {
  stations: WorkStation[]
  steps: Step[]
  taktTimeHours: number
  demandsBehind: number
  andons: Andon[]
  stale: StaleAssignment[]
  activeAssignments: number
  bottlenecks: Bottleneck[]
}

/** `stations` is ordered nearest to production first. */
export type TeamMember = {
  id: string
  name: string
  stations: string[]
}

/** One Assignment of a Team Member is active; the others wait, paused. */
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
  teamMembers: { id: string; name: string }[]
  items: PriorityItem[]
}

export type TeamMemberView = {
  teamMember: { id: string; name: string }
  /** The Andons of the Team Member's Work Stations only. */
  andons: Andon[]
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

/** Hours, in each view; the whole Duration is null when there is nothing to average. */
export type Duration = {
  calendar: number | null
  working: number | null
}

export type TimeView = keyof Duration

/** Averages per Piece that reached production in the period. */
export type PieceMeasures = {
  count: number
  leadTime: Duration | null
  touchTime: Duration | null
  stagnationTime: Duration | null
  backlogTime: Duration | null
}

export type DemandMeasures = {
  id: string
  label: string
  client: string
  pieces: number
  leadTime: Duration | null
  touchTime: Duration | null
  stagnationTime: Duration | null
  /** The Demand's own Lead Time: null until its last Piece reached production. */
  demandLeadTime: Duration | null
}

/** `stationLeadTime` and `touchTime` are averages per pass; `starvationTime` and `andonTime` are totals. */
export type StationMeasures = {
  id: string
  name: string
  branch: string | null
  position: number
  passes: number
  stationLeadTime: Duration | null
  touchTime: Duration | null
  /** A fraction in 0..1. */
  touchShare: number | null
  starvationTime: Duration | null
  /** The time an Andon stopped the Work Station inside the period. */
  andonTime: Duration | null
  /** The Andons raised on the Work Station inside the period. */
  andons: number
  pulls: number
  deviations: number
}

export type RecordedDeviation = {
  at: string
  rule: string
  station: string
  stationName: string
  piece: string | null
  reason: string
}

export type Measures = {
  from: string
  to: string
  pieces: PieceMeasures
  demands: DemandMeasures[]
  stations: StationMeasures[]
  /** The time at least one Work Station is stopped by an Andon; stops at the same time count once. */
  andonTime: Duration | null
  /** Demands delivered in the period, and those delivered by their due date. */
  onTime: { delivered: number; onTime: number }
  deviations: {
    byRule: { rule: string; count: number }[]
    list: RecordedDeviation[]
  }
}

export type Holiday = {
  day: string
  label: string
}

/** `days` uses 0 for Sunday to 6 for Saturday; `start` and `end` are UTC "HH:MM". */
export type WorkingCalendar = {
  days: number[]
  start: string
  end: string
  holidays: Holiday[]
}

/** The names a Line gives to its Demands and Pieces (F41). */
export type Labels = {
  demand: string
  demands: string
  piece: string
  pieces: string
}

/**
 * `email` links the Team Member to the Account that has it; `account` stays
 * null until that Account signs in ("not linked yet"). Both are empty while
 * nobody is signed in.
 */
export type DesignTeamMember = {
  id: string
  name: string
  email: string
  account: { firstName: string; lastName: string } | null
}

/**
 * `locked`: the Work Station holds a Piece, an open Rework or an open Andon.
 * `minBlueBins`: max(1, Pieces in its Blue Bins).
 */
export type DesignStation = {
  id: string
  name: string
  branch: string | null
  blueBins: number
  teamLeader: string
  teamMembers: string[]
  locked: boolean
  minBlueBins: number
}

/** Steps are in flow order: the first step pulls from the Backlog. */
export type DesignStep = {
  name: string
  stations: DesignStation[]
}

export type Design = {
  labels: Labels
  teamMembers: DesignTeamMember[]
  steps: DesignStep[]
}

/** `id` is null for a new Work Station. */
export type DesignStationInput = {
  id: string | null
  name: string
  branch: string | null
  blueBins: number
  teamLeader: string
  teamMembers: string[]
}

export type DesignInput = {
  labels: Labels
  teamMembers: { id: string; name: string; email: string }[]
  steps: { name: string; stations: DesignStationInput[] }[]
}

/** `GET /api/account`. Nobody is signed in while SSO is off. */
export type Account =
  | { signedIn: false }
  | {
      signedIn: true
      named: boolean
      /** authentik's own admin, who invites people. */
      admin: boolean
      email: string
      firstName: string
      lastName: string
    }

/** What the Account may do in a Line; the server checks it again (H10). */
export type LineRole = "owner" | "member" | "viewer"

export type LineEntry = {
  id: string
  name: string
  /** Anyone with its look-only link sees a Shared Line, signed in or not. */
  shared: boolean
  role: LineRole
  /** The Account's own Team Member, for a member. */
  teamMember: string | null
}

/** One Workspace of the Line menu, from `GET /api/workspaces`. */
export type Workspace = {
  owner: string
  /** The owner's name; null before their first sign-in. */
  name: string | null
  own: boolean
  lines: LineEntry[]
}
