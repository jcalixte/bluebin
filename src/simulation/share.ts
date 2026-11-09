import { computed, ref } from "vue"
import type { Room } from "trystero"
import type { TeamMemberName } from "../wire"
import { claim, keepPresent, release, seatOf, type Seats } from "./seats"
import { actingAs, answer, changed, onSimulatedChange, plugRemote } from "./state"

/**
 * A shared Simulation: the page that invites is the Host and runs the Line; each page that opens
 * its link is a Guest that plays one Team Member. The pages talk peer to peer (WebRTC); Trystero
 * finds them through public Nostr relays, which see only encrypted connection offers. Trystero
 * loads only when a page invites or joins.
 */

const appId = "app.bluebin.try"

/** How long a Guest waits for its Host to answer one call. */
const callTimeoutMs = 15000

/** What the Host tells each Guest: who can be played, and who plays whom. */
type Table = { teamMembers: TeamMemberName[]; seats: Seats }
type Call = { method: string; path: string; body: string }
type Answer = { status: number; text: string }

/** Team Member id → peer id of the Guest who plays it. */
export const seats = ref<Seats>({})
export const teamMembers = ref<TeamMemberName[]>([])

/** Host: the link to send, once it invites; and the Guests in the room. */
export const inviteLink = ref<string | null>(null)
export const guests = ref<string[]>([])

/** Guest: whether its Host answered, and the Team Member it plays. */
export const host = ref<"looking" | "here" | "gone">("looking")
const me = ref("")
export const mySeat = computed(() => seatOf(seats.value, me.value))

function randomCode(bytes: number): string {
  const values = crypto.getRandomValues(new Uint8Array(bytes))
  return btoa(String.fromCharCode(...values))
    .replace(/\+/g, "-")
    .replace(/\//g, "_")
    .replace(/=+$/, "")
}

/** `<room>.<password>`: the password encrypts the offers that the relays carry. */
async function open(code: string): Promise<Room> {
  // The mode itself: Vite folds it, so the real build has no Trystero chunk.
  if (import.meta.env.MODE !== "simulation") throw new Error("Only the Simulation is shared.")
  const [roomId, password] = code.split(".")
  const { joinRoom, selfId } = await import("trystero")
  me.value = selfId
  return joinRoom({ appId, password }, roomId)
}

function actions(room: Room) {
  return {
    table: room.makeAction<Table>("table"),
    change: room.makeAction<null>("change"),
    call: room.makeAction<Call, Answer>("call", { kind: "request" }),
    take: room.makeAction<string, string>("take", { kind: "request" }),
  }
}

let inviting: Promise<string> | null = null

/** Host: opens the room once and answers the link that Guests open. */
export function invite(): Promise<string> {
  inviting ??= startHosting()
  return inviting
}

async function startHosting(): Promise<string> {
  const code = `${randomCode(9)}.${randomCode(16)}`
  const room = await open(code)
  const { table, change, call, take } = actions(room)

  function sendTable(target: string | null = null) {
    void table.send({ teamMembers: teamMembers.value, seats: seats.value }, { target })
  }

  /** The Host plays the owner and each Team Member no Guest plays. */
  function setSeats(next: Seats) {
    seats.value = next
    if (actingAs.value in next) actingAs.value = ""
    sendTable()
  }

  function readTeamMembers() {
    const [status, text] = answer("GET", "/api/team-members", "", "")
    if (status !== 200) return
    teamMembers.value = (JSON.parse(text) as TeamMemberName[]).map(({ id, name }) => ({ id, name }))
  }

  readTeamMembers()
  onSimulatedChange(() => {
    readTeamMembers()
    setSeats(
      keepPresent(
        seats.value,
        teamMembers.value.map((one) => one.id),
      ),
    )
    void change.send(null)
  })

  call.onRequest = ({ method, path, body }, { peerId }) => {
    const teamMember = seatOf(seats.value, peerId)
    if (teamMember === null) return { status: 403, text: "Pick a Team Member first." }
    try {
      const [status, text] = answer(method, path, body, teamMember)
      return { status, text }
    } catch (cause) {
      return { status: 500, text: cause instanceof Error ? cause.message : String(cause) }
    }
  }

  take.onRequest = (teamMember, { peerId }) => {
    const next = claim(
      seats.value,
      peerId,
      teamMember,
      teamMembers.value.map((one) => one.id),
    )
    if (typeof next === "string") return next
    setSeats(next)
    return ""
  }

  room.onPeerJoin = (peer) => {
    guests.value = [...guests.value, peer]
    sendTable(peer)
  }
  room.onPeerLeave = (peer) => {
    guests.value = guests.value.filter((one) => one !== peer)
    setSeats(release(seats.value, peer))
  }

  inviteLink.value = `${location.origin}/line#join=${code}`
  return inviteLink.value
}

let take: ((teamMember: string) => Promise<string>) | null = null

/** Guest: joins the room of the link and sends every call of the Line to its Host. */
export async function join(code: string) {
  const room = await open(code)
  const { table, change, call, take: takeSeat } = actions(room)
  let hostId: string | null = null

  table.onMessage = (found, { peerId }) => {
    hostId = peerId
    host.value = "here"
    teamMembers.value = found.teamMembers
    seats.value = found.seats
    actingAs.value = seatOf(found.seats, me.value) ?? ""
  }
  change.onMessage = (_, { peerId }) => {
    if (peerId === hostId) changed()
  }
  room.onPeerLeave = (peer) => {
    if (peer === hostId) host.value = "gone"
  }

  function toHost() {
    if (hostId === null || host.value !== "here") {
      throw new Error("The host of this Simulation is not here.")
    }
    return { target: hostId, timeoutMs: callTimeoutMs }
  }

  plugRemote(async (method, path, body) => {
    const { status, text } = await call.request({ method, path, body }, toHost())
    return [status, text]
  })
  take = (teamMember) => takeSeat.request(teamMember, toHost())
}

/** Guest: plays this Team Member, or `""` to pick again. */
export async function pick(teamMember: string) {
  if (!take) throw new Error("The Simulation is not joined yet.")
  const refused = await take(teamMember)
  if (refused) throw new Error(refused)
}
