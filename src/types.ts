// Written by `gleam dev` from backend/src/bluebin/wire.gleam: change it there.
import type { Duration, ReorderEffect } from "./wire"

export type {
  Backlog,
  BacklogPiece,
  Demand,
  DemandMeasures,
  Duration,
  Holiday,
  LineEntry,
  LineRole,
  Measures,
  MixCell,
  MixRow,
  PieceMeasures,
  RecordedDeviation,
  ReorderEffect,
  StationMeasures,
  WorkingCalendar,
  Workspace,
} from "./wire"

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
  /** An open Rework repairs it: finishing it accepts the repair. */
  underRework: boolean
  /** The Team Members who Help the Rework on this Piece. */
  helpers: TeamMemberName[]
}

export type TeamMemberName = { id: string; name: string }

export type Rework = {
  id: string
  piece: string
  description: string
  /** The Work Station that found the defect and holds the Piece. */
  foundBy: string
  foundById: string | null
  assignee: string | null
  assigneeId: string | null
  helpers: TeamMemberName[]
  /** Who may join as Helper now: the two Work Stations concerned, while someone repairs. */
  canHelp: TeamMemberName[]
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

/** Help the Rework, offered in a pull warning before the Deviation (F14). */
export type HelpOffer = {
  rework: string
  label: string
  /** Why this help cannot start now, or null. */
  blocked: string | null
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

/** A deployed Piece that waits for its Release; `waitingHours` since its Deployment, in Calendar Time. */
export type HeldForRelease = {
  id: string
  piece: string
  demand: string
  demandLabel: string
  waitingHours: number
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
  heldForRelease: HeldForRelease[]
}

/** `stations` is ordered nearest to Deployment first. */
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
  | {
      kind: "helping" | "help_the_rework"
      rework: string
      piece: string
      assignee: string
      station: string
      stationName: string
    }
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

export type TimeView = keyof Duration

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
 * Suggested Blue Bins (DESIGN.md F55): the last `passes` (at most 20) that went
 * in the Blue Bin. `replenishmentHours` is their 85th percentile in Working
 * Time, without the pauses while the Team Member held another Piece; null
 * under 5 passes. `blueBins` is null without it or without a Takt Time.
 */
export type BlueBinSuggestion = {
  passes: number
  replenishmentHours: number | null
  blueBins: number | null
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
  suggestion: BlueBinSuggestion
}

/** Steps are in flow order: the first step pulls from the Backlog. */
export type DesignStep = {
  name: string
  stations: DesignStation[]
}

export type Design = {
  labels: Labels
  /** The Takt Time of the Line, in hours of Working Time; 0 with no active Demand. */
  taktTimeHours: number
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
