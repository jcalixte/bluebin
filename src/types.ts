// The API shapes come from `./wire`, which `gleam dev` writes from
// backend/src/bluebin/wire.gleam: change them there. Below: the SPA's own types.
import type { Duration, ReorderEffect } from "./wire"

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
  DesignInput,
  DesignStation,
  DesignStationInput,
  DesignStep,
  DesignTeamMember,
  Deviation,
  Duration,
  HeldForRelease,
  Holiday,
  InProgressPiece,
  Labels,
  LineChange,
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
