import bluebin/shape.{Assembly, AtSplit, FromBacklog, Node, Straight}
import gleam/list
import gleam/option.{None, Some}

fn trunk(id: String, position: Int) -> shape.Node {
  Node(id:, position:, branch: None, parent: None)
}

fn branch(id: String, position: Int, name: String) -> shape.Node {
  Node(id:, position:, branch: Some(name), parent: None)
}

fn nested(
  id: String,
  position: Int,
  name: String,
  outer: String,
) -> shape.Node {
  Node(id:, position:, branch: Some(name), parent: Some(outer))
}

fn inflow_of(nodes: List(shape.Node), id: String) -> shape.Inflow {
  let assert Ok(node) = list.find(nodes, fn(node) { node.id == id })
  let assert Ok(found) = shape.inflow(nodes, node)
  found
}

/// The Line of the seed: three Branches of the same length.
fn even() -> List(shape.Node) {
  [
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
}

pub fn the_first_work_station_pulls_from_the_backlog_test() {
  assert inflow_of(even(), "analysis") == FromBacklog
  assert inflow_of(even(), "conception") == Straight("analysis")
}

pub fn each_branch_pulls_at_the_split_test() {
  assert inflow_of(even(), "web")
    == AtSplit("conception", ["Android", "Web", "iOS"])
  assert inflow_of(even(), "qa-ios") == Straight("ios")
}

pub fn the_trunk_after_the_branches_assembles_them_test() {
  assert inflow_of(even(), "uat")
    == Assembly(["qa-android", "qa-web", "qa-ios"])
}

pub fn a_short_branch_ends_at_its_only_work_station_test() {
  let nodes = [
    trunk("spec", 1),
    branch("web", 2, "Web"),
    branch("ios", 2, "iOS"),
    branch("qa-ios", 3, "iOS"),
    trunk("uat", 4),
  ]
  assert inflow_of(nodes, "web") == AtSplit("spec", ["Web", "iOS"])
  assert inflow_of(nodes, "qa-ios") == Straight("ios")
  assert inflow_of(nodes, "uat") == Assembly(["web", "qa-ios"])
}

pub fn a_branch_skips_a_step_test() {
  let nodes = [
    trunk("spec", 1),
    branch("web", 2, "Web"),
    branch("ios", 2, "iOS"),
    branch("build-ios", 3, "iOS"),
    branch("qa-web", 4, "Web"),
    branch("qa-ios", 4, "iOS"),
    trunk("uat", 5),
  ]
  assert inflow_of(nodes, "qa-web") == Straight("web")
  assert inflow_of(nodes, "uat") == Assembly(["qa-web", "qa-ios"])
}

pub fn a_branch_can_open_after_the_first_step_of_the_split_test() {
  let nodes = [
    trunk("spec", 1),
    branch("web", 2, "Web"),
    branch("ios", 3, "iOS"),
    trunk("uat", 4),
  ]
  assert inflow_of(nodes, "ios") == AtSplit("spec", ["Web", "iOS"])
  assert inflow_of(nodes, "uat") == Assembly(["web", "ios"])
}

pub fn two_splits_follow_each_other_test() {
  let nodes = [
    trunk("spec", 1),
    branch("a", 2, "A"),
    branch("b", 2, "B"),
    trunk("mid", 3),
    branch("c", 4, "C"),
    branch("d", 4, "D"),
    trunk("end", 5),
  ]
  assert inflow_of(nodes, "mid") == Assembly(["a", "b"])
  assert inflow_of(nodes, "c") == AtSplit("mid", ["C", "D"])
  assert inflow_of(nodes, "end") == Assembly(["c", "d"])
}

/// Web, and Mobile that splits again into iOS and Android until QA Mobile.
fn nesting() -> List(shape.Node) {
  [
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
}

pub fn a_nested_split_opens_inside_its_outer_branch_test() {
  assert inflow_of(nesting(), "web") == AtSplit("spec", ["Mobile", "Web"])
  assert inflow_of(nesting(), "ios")
    == AtSplit("mobile-api", ["Android", "iOS"])
  assert inflow_of(nesting(), "qa-ios") == Straight("ios")
}

pub fn the_outer_branch_assembles_its_nested_branches_test() {
  assert inflow_of(nesting(), "qa-mobile") == Assembly(["android", "qa-ios"])
  assert inflow_of(nesting(), "uat") == Assembly(["qa-mobile", "qa-web"])
}

pub fn upstream_follows_the_branches_test() {
  let nodes = nesting()
  assert shape.is_upstream(nodes, "ios", "uat")
  assert shape.is_upstream(nodes, "mobile-api", "qa-ios")
  assert shape.is_upstream(nodes, "spec", "android")
  assert !shape.is_upstream(nodes, "web", "qa-ios")
  assert !shape.is_upstream(nodes, "android", "qa-ios")
  assert !shape.is_upstream(nodes, "uat", "spec")
}

pub fn a_branch_name_used_in_two_splits_stays_in_its_own_split_test() {
  // Saved before Branch names were unique in the Line.
  let nodes = [
    trunk("spec", 1),
    branch("web-1", 2, "Web"),
    branch("ios-1", 2, "iOS"),
    trunk("mid", 3),
    branch("web-2", 4, "Web"),
    branch("ios-2", 4, "iOS"),
    trunk("end", 5),
  ]
  assert inflow_of(nodes, "web-2") == AtSplit("mid", ["Web", "iOS"])
  assert inflow_of(nodes, "end") == Assembly(["web-2", "ios-2"])
}

pub fn a_trunk_work_station_with_a_parent_branch_stays_on_the_trunk_test() {
  let nodes = [
    Node(id: "spec", position: 1, branch: None, parent: Some("Mobile")),
    branch("web", 2, "Web"),
    branch("mobile", 2, "Mobile"),
    trunk("uat", 3),
  ]
  assert inflow_of(nodes, "mobile") == AtSplit("spec", ["Mobile", "Web"])
}
