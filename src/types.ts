// Written by `gleam dev` from backend/src/bluebin/wire.gleam: change it there.
import type { Andon, Duration, Labels, ReorderEffect } from "./wire"

export type {
  Andon,
  Backlog,
  BacklogPiece,
  BlueBin,
  BlueBinSuggestion,
  Bottleneck,
  Demand,
  DemandMeasures,
  Design,
  DesignStation,
  DesignStep,
  DesignTeamMember,
  Deviation,
  Duration,
  HeldForRelease,
  Holiday,
  InProgressPiece,
  Labels,
  Line,
  LineEntry,
  LineRole,
  Measures,
  Member,
  MixCell,
  MixRow,
  Overflow,
  PieceMeasures,
  RecordedDeviation,
  ReorderEffect,
  Rework,
  StaleAssignment,
  StationMeasures,
  Step,
  TeamMemberName,
  WorkStation,
  WorkingCalendar,
  Workspace,
} from "./wire"

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
