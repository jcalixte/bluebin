import assert from "node:assert/strict"
import { test } from "node:test"
import { inflow, isUpstream, laneRows, type ShapeNode } from "./shape.ts"

const trunk = (id: string, position: number): ShapeNode => ({
  id,
  position,
  branch: null,
  parentBranch: null,
})
const branch = (id: string, position: number, name: string): ShapeNode => ({
  id,
  position,
  branch: name,
  parentBranch: null,
})
const nested = (id: string, position: number, name: string, outer: string): ShapeNode => ({
  id,
  position,
  branch: name,
  parentBranch: outer,
})

function inflowOf(nodes: ShapeNode[], id: string) {
  const node = nodes.find((one) => one.id === id)
  assert.ok(node)
  return inflow(nodes, node)
}

const even = [
  trunk("analysis", 1),
  trunk("conception", 2),
  branch("web", 3, "Web"),
  branch("ios", 3, "iOS"),
  branch("android", 3, "Android"),
  branch("qa-web", 4, "Web"),
  branch("qa-ios", 4, "iOS"),
  branch("qa-android", 4, "Android"),
  trunk("uat", 5),
]

test("the routes of Branches of the same length match the Gleam shape", () => {
  assert.deepEqual(inflowOf(even, "analysis"), { kind: "backlog" })
  assert.deepEqual(inflowOf(even, "web"), {
    kind: "split",
    from: "conception",
    branches: ["Android", "Web", "iOS"],
  })
  assert.deepEqual(inflowOf(even, "qa-ios"), { kind: "straight", from: "ios" })
  assert.deepEqual(inflowOf(even, "uat"), {
    kind: "assembly",
    ends: ["qa-android", "qa-web", "qa-ios"],
  })
})

test("a short Branch ends at its only Work Station", () => {
  const nodes = [
    trunk("spec", 1),
    branch("web", 2, "Web"),
    branch("ios", 2, "iOS"),
    branch("qa-ios", 3, "iOS"),
    trunk("uat", 4),
  ]
  assert.deepEqual(inflowOf(nodes, "uat"), { kind: "assembly", ends: ["web", "qa-ios"] })
})

test("a Branch skips a step", () => {
  const nodes = [
    trunk("spec", 1),
    branch("web", 2, "Web"),
    branch("ios", 2, "iOS"),
    branch("build-ios", 3, "iOS"),
    branch("qa-web", 4, "Web"),
    trunk("uat", 5),
  ]
  assert.deepEqual(inflowOf(nodes, "qa-web"), { kind: "straight", from: "web" })
  assert.deepEqual(inflowOf(nodes, "uat"), { kind: "assembly", ends: ["qa-web", "build-ios"] })
})

const nesting = [
  trunk("spec", 1),
  branch("web", 2, "Web"),
  branch("mobile-api", 2, "Mobile"),
  nested("ios", 3, "iOS", "Mobile"),
  nested("android", 3, "Android", "Mobile"),
  branch("qa-web", 4, "Web"),
  nested("qa-ios", 4, "iOS", "Mobile"),
  branch("qa-mobile", 5, "Mobile"),
  trunk("uat", 6),
]

test("a nested Split opens and closes inside its outer Branch", () => {
  assert.deepEqual(inflowOf(nesting, "ios"), {
    kind: "split",
    from: "mobile-api",
    branches: ["Android", "iOS"],
  })
  assert.deepEqual(inflowOf(nesting, "qa-mobile"), {
    kind: "assembly",
    ends: ["android", "qa-ios"],
  })
  assert.deepEqual(inflowOf(nesting, "uat"), { kind: "assembly", ends: ["qa-mobile", "qa-web"] })
})

test("upstream follows the Branches", () => {
  assert.equal(isUpstream(nesting, "ios", "uat"), true)
  assert.equal(isUpstream(nesting, "mobile-api", "qa-ios"), true)
  assert.equal(isUpstream(nesting, "web", "qa-ios"), false)
  assert.equal(isUpstream(nesting, "android", "qa-ios"), false)
})

test("each Branch keeps its row across its Split, nested Branches under their outer one", () => {
  const { lanes, rows } = laneRows(nesting, [1, 2, 3, 4, 5, 6])
  assert.equal(rows, 4)
  assert.deepEqual(lanes.get(1), [null])
  assert.deepEqual(lanes.get(3), ["Mobile", "Android", "iOS", "Web"])
  assert.deepEqual(lanes.get(6), [null])
})

test("an empty step inside a Split shows the lanes of the Split", () => {
  const nodes = [trunk("a", 1), branch("w", 2, "Web"), branch("i", 4, "iOS"), trunk("b", 5)]
  const { lanes } = laneRows(nodes, [1, 2, 3, 4, 5])
  assert.deepEqual(lanes.get(3), ["Web", "iOS"])
})

test("a Branch name used in two Splits stays in its own Split", () => {
  const nodes = [
    trunk("spec", 1),
    branch("web-1", 2, "Web"),
    branch("ios-1", 2, "iOS"),
    trunk("mid", 3),
    branch("web-2", 4, "Web"),
    branch("ios-2", 4, "iOS"),
    trunk("end", 5),
  ]
  assert.deepEqual(inflowOf(nodes, "web-2"), {
    kind: "split",
    from: "mid",
    branches: ["Web", "iOS"],
  })
  assert.deepEqual(inflowOf(nodes, "end"), { kind: "assembly", ends: ["web-2", "ios-2"] })
})
