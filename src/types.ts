// Written by `gleam dev` from backend/src/bluebin/wire.gleam: change it there.
import type { Duration, Labels, ReorderEffect } from "./wire"

export type {
  Andon,
  Assignment,
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
  NextThing,
  Overflow,
  PieceMeasures,
  PriorityItem,
  PriorityList,
  RecordedDeviation,
  ReorderEffect,
  Rework,
  StaleAssignment,
  StationMeasures,
  Step,
  TeamMember,
  TeamMemberName,
  TeamMemberView,
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
