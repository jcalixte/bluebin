import assert from "node:assert/strict"
import { test } from "node:test"
import { claim, keepPresent, release, seatOf } from "./seats.ts"

const teamMembers = ["pe-ana", "pe-bo", "pe-cy"]

test("a guest takes a free Team Member", () => {
  assert.deepEqual(claim({}, "peer-1", "pe-ana", teamMembers), { "pe-ana": "peer-1" })
})

test("a guest cannot take a Team Member another guest plays", () => {
  assert.equal(
    claim({ "pe-ana": "peer-1" }, "peer-2", "pe-ana", teamMembers),
    "Another Guest took this Team Member.",
  )
})

test("taking a Team Member again keeps the seat", () => {
  assert.deepEqual(claim({ "pe-ana": "peer-1" }, "peer-1", "pe-ana", teamMembers), {
    "pe-ana": "peer-1",
  })
})

test("a guest that changes Team Member frees the first one", () => {
  const seats = claim({ "pe-ana": "peer-1", "pe-bo": "peer-2" }, "peer-1", "pe-cy", teamMembers)
  assert.deepEqual(seats, { "pe-bo": "peer-2", "pe-cy": "peer-1" })
})

test("an empty claim only frees the seat", () => {
  assert.deepEqual(claim({ "pe-ana": "peer-1" }, "peer-1", "", teamMembers), {})
})

test("a guest cannot take a Team Member that is not in the Line", () => {
  assert.equal(
    claim({}, "peer-1", "pe-zed", teamMembers),
    "This Team Member is no longer in the Line.",
  )
})

test("a guest that leaves frees its seat only", () => {
  assert.deepEqual(release({ "pe-ana": "peer-1", "pe-bo": "peer-2" }, "peer-1"), {
    "pe-bo": "peer-2",
  })
})

test("a Team Member removed in Design loses its seat", () => {
  assert.deepEqual(keepPresent({ "pe-ana": "peer-1", "pe-zed": "peer-2" }, teamMembers), {
    "pe-ana": "peer-1",
  })
})

test("seatOf finds the Team Member of a peer", () => {
  assert.equal(seatOf({ "pe-ana": "peer-1" }, "peer-1"), "pe-ana")
  assert.equal(seatOf({ "pe-ana": "peer-1" }, "peer-2"), null)
})
