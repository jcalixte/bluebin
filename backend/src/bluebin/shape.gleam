//// The routes of a Line: where each Work Station pulls its Piece from.
////
//// A Line is a grid of steps. The trunk has one Work Station at a step; a
//// Split opens Branches that run side by side over the next steps, each with
//// its own number of Work Stations, until the trunk Work Station after them
//// does the Assembly. A Branch can open one nested Split, closed by a later
//// Work Station of the same Branch. `src/shape.ts` mirrors this module.

import gleam/dynamic/decode
import gleam/int
import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/result
import gleam/set
import gleam/string
import sqlight

/// `branch` is None on the trunk; `parent` names the outer Branch of a nested
/// Branch.
pub type Node {
  Node(
    id: String,
    position: Int,
    branch: Option(String),
    parent: Option(String),
  )
}

pub type Inflow {
  FromBacklog
  /// The Work Station before it in its own Branch, or on the trunk.
  Straight(from: String)
  /// The first Work Station of a Branch pulls its Sub-Piece from `from`; the
  /// Piece leaves there once every Branch of `branches` has pulled.
  AtSplit(from: String, branches: List(String))
  /// The last Work Station of each Branch it closes, in Branch name order.
  Assembly(ends: List(String))
}

/// Every Work Station of the Line, in step order.
pub fn load(
  connection: sqlight.Connection,
) -> Result(List(Node), sqlight.Error) {
  sqlight.query(
    "select id, position, branch, parent_branch from work_station
      order by position, branch",
    on: connection,
    with: [],
    expecting: {
      use id <- decode.field(0, decode.string)
      use position <- decode.field(1, decode.int)
      use branch <- decode.field(2, decode.optional(decode.string))
      use parent <- decode.field(3, decode.optional(decode.string))
      decode.success(Node(id:, position:, branch:, parent:))
    },
  )
}

/// Error when the shape is broken, which a saved Design never is.
pub fn inflow(nodes: List(Node), node: Node) -> Result(Inflow, Nil) {
  let lane = node.branch
  let before =
    list.filter(nodes, fn(other) {
      other.position < node.position
      && { other.branch == lane || inside(other, lane) }
    })
  case nearest(before) {
    Error(Nil) ->
      case lane {
        None -> Ok(FromBacklog)
        Some(_) -> split_of(nodes, node)
      }
    Ok(position) ->
      case
        list.find(before, fn(other) {
          other.position == position && other.branch == lane
        })
      {
        Ok(from) -> Ok(Straight(from.id))
        Error(Nil) -> Ok(Assembly(ends(nodes, lane, node)))
      }
  }
}

/// The Work Stations it pulls from: none from the Backlog, one, or the end of
/// each Branch at an Assembly.
pub fn upstream(nodes: List(Node), node: Node) -> List(String) {
  upstream_of(nodes, node)
}

fn upstream_of(nodes: List(Node), node: Node) -> List(String) {
  case inflow(nodes, node) {
    Ok(Straight(from)) | Ok(AtSplit(from, _)) -> [from]
    Ok(Assembly(ends)) -> ends
    Ok(FromBacklog) | Error(Nil) -> []
  }
}

/// Every Piece that reaches `downstream` has passed `upstream` first.
pub fn is_upstream(
  nodes: List(Node),
  upstream: String,
  downstream: String,
) -> Bool {
  reaches(
    fn(id) {
      case list.find(nodes, fn(node) { node.id == id }) {
        Ok(node) -> upstream_of(nodes, node)
        Error(Nil) -> []
      }
    },
    upstream,
    downstream,
  )
}

/// `is_upstream` when the upstream list of each Work Station is known.
pub fn reaches(
  upstream: fn(String) -> List(String),
  from: String,
  to: String,
) -> Bool {
  ancestors(upstream, [to], set.new()) |> set.contains(from)
}

fn ancestors(
  upstream: fn(String) -> List(String),
  pending: List(String),
  seen: set.Set(String),
) -> set.Set(String) {
  case pending {
    [] -> seen
    [id, ..rest] -> {
      let fresh =
        upstream(id) |> list.filter(fn(one) { !set.contains(seen, one) })
      ancestors(
        upstream,
        list.append(fresh, rest),
        list.fold(fresh, seen, set.insert),
      )
    }
  }
}

/// A Work Station of a Branch that opens inside `lane`.
fn inside(node: Node, lane: Option(String)) -> Bool {
  case lane {
    None -> node.branch != None && node.parent == None
    Some(outer) -> node.parent == Some(outer)
  }
}

fn nearest(nodes: List(Node)) -> Result(Int, Nil) {
  nodes
  |> list.map(fn(node) { node.position })
  |> list.reduce(int.max)
}

/// The Work Station before the Split, in the lane around the Branch.
fn split_source(nodes: List(Node), first: Node) -> Result(Node, Nil) {
  nodes
  |> list.filter(fn(other) {
    other.position < first.position && other.branch == first.parent
  })
  |> list.reduce(fn(a, b) {
    case a.position > b.position {
      True -> a
      False -> b
    }
  })
}

fn first_of(nodes: List(Node), branch: Option(String)) -> Result(Node, Nil) {
  nodes
  |> list.filter(fn(node) { node.branch == branch })
  |> list.reduce(fn(a, b) {
    case a.position < b.position {
      True -> a
      False -> b
    }
  })
}

fn split_of(nodes: List(Node), node: Node) -> Result(Inflow, Nil) {
  case split_source(nodes, node) {
    Error(Nil) -> Error(Nil)
    Ok(from) -> {
      let branches =
        nodes
        |> list.filter(fn(other) {
          other.branch != None && other.parent == node.parent
        })
        |> list.filter_map(fn(other) {
          case first_of(nodes, other.branch) {
            Ok(first) ->
              case split_source(nodes, first) {
                Ok(source) if source.id == from.id ->
                  option.to_result(other.branch, Nil)
                _ -> Error(Nil)
              }
            Error(Nil) -> Error(Nil)
          }
        })
        |> list.unique
        |> list.sort(string.compare)
      Ok(AtSplit(from.id, branches))
    }
  }
}

/// The last Work Station of each Branch that opens inside `lane` and closes
/// at `node`.
fn ends(nodes: List(Node), lane: Option(String), node: Node) -> List(String) {
  let floor =
    nodes
    |> list.filter(fn(other) {
      other.branch == lane && other.position < node.position
    })
    |> nearest
    |> result.unwrap(-1)
  nodes
  |> list.filter(fn(other) {
    inside(other, lane)
    && other.position > floor
    && other.position < node.position
  })
  |> list.fold([], fn(last: List(#(Option(String), Node)), other) {
    case list.key_find(last, other.branch) {
      Ok(found) if found.position >= other.position -> last
      _ -> list.key_set(last, other.branch, other)
    }
  })
  |> list.sort(fn(a, b) {
    string.compare(option.unwrap(a.0, ""), option.unwrap(b.0, ""))
  })
  |> list.map(fn(entry) { { entry.1 }.id })
}
