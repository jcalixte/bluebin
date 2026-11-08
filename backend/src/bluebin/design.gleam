//// Design and change a running Line without code (F39–F41).

import bluebin/accounts
import bluebin/db
import bluebin/line
import bluebin/measures
import bluebin/text
import gleam/bool
import gleam/dict.{type Dict}
import gleam/dynamic/decode
import gleam/int
import gleam/json.{type Json}
import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/result
import gleam/set
import gleam/string
import sqlight

pub type Labels {
  Labels(demand: String, demands: String, piece: String, pieces: String)
}

pub type TeamMember {
  TeamMember(id: String, name: String)
}

/// `id` is None for a Work Station the designer adds.
pub type Station {
  Station(
    id: Option(String),
    name: String,
    branch: Option(String),
    blue_bins: Int,
    team_leader: String,
    team_members: List(String),
  )
}

pub type Step {
  Step(name: String, stations: List(Station))
}

pub type Design {
  Design(labels: Labels, team_members: List(TeamMember), steps: List(Step))
}

/// A locked Work Station holds a Piece, an open Rework or an open Andon.
pub type Held {
  Held(position: Int, locked: Bool, in_bins: Int, kanbans: Int)
}

pub type DesignError {
  Invalid(String)
  StoreFailed
}

pub fn load_labels(connection: sqlight.Connection) -> Result(Labels, Nil) {
  sqlight.query(
    "select demand, demands, piece, pieces from line_label where id = 1",
    on: connection,
    with: [],
    expecting: {
      use demand <- decode.field(0, decode.string)
      use demands <- decode.field(1, decode.string)
      use piece <- decode.field(2, decode.string)
      use pieces <- decode.field(3, decode.string)
      decode.success(Labels(demand:, demands:, piece:, pieces:))
    },
  )
  |> result.replace_error(Nil)
  |> result.map(fn(rows) {
    case rows {
      [labels, ..] -> labels
      [] -> Labels("Demand", "Demands", "Piece", "Pieces")
    }
  })
}

pub fn load(
  connection: sqlight.Connection,
) -> Result(#(Design, Dict(String, Held)), Nil) {
  use labels <- result.try(load_labels(connection))
  use team_members <- result.try(
    query(
      connection,
      "select id, name from team_member where removed_at is null order by rowid",
      [],
      {
        use id <- decode.field(0, decode.string)
        use name <- decode.field(1, decode.string)
        decode.success(TeamMember(id:, name:))
      },
    ),
  )
  use members <- result.try(query(
    connection,
    "select station_id, team_member_id from station_team_member order by rowid",
    [],
    pair_decoder(),
  ))
  use names <- result.try(
    query(connection, "select position, name from line_step", [], {
      use position <- decode.field(0, decode.int)
      use name <- decode.field(1, decode.string)
      decode.success(#(position, name))
    }),
  )
  use rows <- result.try(load_stations(connection, members))
  let steps =
    rows
    |> list.chunk(fn(row) { row.0 })
    |> list.map(fn(chunk) {
      let position = case chunk {
        [#(position, _, _), ..] -> position
        [] -> 0
      }
      Step(
        name: list.key_find(names, position)
          |> result.unwrap("Step " <> int.to_string(position)),
        stations: list.map(chunk, fn(row) { row.1 }),
      )
    })
  let held =
    rows
    |> list.filter_map(fn(row) {
      option.to_result(row.1.id, Nil) |> result.map(fn(id) { #(id, row.2) })
    })
    |> dict.from_list

  Ok(#(Design(labels:, team_members:, steps:), held))
}

/// Each Work Station in Line order, with its step position and what it holds.
/// `members` pairs a Work Station id with a Team Member id.
fn load_stations(
  connection: sqlight.Connection,
  members: List(#(String, String)),
) -> Result(List(#(Int, Station, Held)), Nil) {
  query(
    connection,
    "select w.id, w.name, w.position, w.branch, w.blue_bins,
            coalesce(w.team_leader, ''),
            exists (select 1 from piece p where p.station_id = w.id)
              or exists (select 1 from rework r
                          where r.closed_at is null
                            and (r.station_id = w.id or r.raised_by = w.id))
              or exists (select 1 from andon a
                          where a.closed_at is null and a.station_id = w.id),
            (select count(*) from piece p
              where p.station_id = w.id and p.state = 'in_bin'),
            (select count(*) from kanban k where k.station_id = w.id)
       from work_station w
      order by w.position, w.rowid",
    [],
    {
      use id <- decode.field(0, decode.string)
      use name <- decode.field(1, decode.string)
      use position <- decode.field(2, decode.int)
      use branch <- decode.field(3, decode.optional(decode.string))
      use blue_bins <- decode.field(4, decode.int)
      use team_leader <- decode.field(5, decode.string)
      use locked <- decode.field(6, sqlight.decode_bool())
      use in_bins <- decode.field(7, decode.int)
      use kanbans <- decode.field(8, decode.int)
      decode.success(#(
        position,
        Station(
          id: Some(id),
          name:,
          branch:,
          blue_bins:,
          team_leader:,
          team_members: list.filter_map(members, fn(member) {
            case member.0 == id {
              True -> Ok(member.1)
              False -> Error(Nil)
            }
          }),
        ),
        Held(position:, locked:, in_bins:, kanbans:),
      ))
    },
  )
}

/// The shape of the steps alone: one trunk Work Station per step, or a Split
/// into two or more named Branches that run side by side until the Assembly.
/// Nested Splits are not supported.
pub fn check_structure(steps: List(Step)) -> Result(Nil, String) {
  use <- bool.guard(
    steps == [],
    Error("A Line needs at least one Work Station."),
  )
  use shapes <- result.try(
    list.index_map(steps, fn(step, index) { step_shape(step, index + 1) })
    |> result.all,
  )
  use <- bool.guard(
    list.first(shapes) != Ok(None),
    Error(
      "The first step pulls from the Backlog: it needs one Work Station without a Branch.",
    ),
  )
  use <- bool.guard(
    list.last(shapes) != Ok(None),
    Error(
      "The last step must be one Work Station without a Branch: it assembles the Branches.",
    ),
  )
  list.window_by_2(shapes)
  |> list.index_map(fn(pair, index) { #(pair, index + 1) })
  |> list.try_each(fn(entry) {
    case entry {
      #(#(Some(before), Some(after)), position) if before != after ->
        Error(
          "Steps "
          <> int.to_string(position)
          <> " and "
          <> int.to_string(position + 1)
          <> " must have the same Branches. Nested Splits are not supported.",
        )
      _ -> Ok(Nil)
    }
  })
}

/// None for a trunk step, else its set of Branch names.
fn step_shape(
  step: Step,
  position: Int,
) -> Result(Option(set.Set(String)), String) {
  let label = "Step " <> int.to_string(position)
  use _ <- result.try(check_name(step.name, label <> " needs a name."))
  case step.stations {
    [] -> Error(label <> " has no Work Station.")
    [Station(branch: None, ..)] -> Ok(None)
    [_] ->
      Error(
        label
        <> " has one Branch only. A Split needs two Branches or more; remove the Branch name to keep one Work Station.",
      )
    stations -> {
      use branches <- result.try(
        list.try_map(stations, fn(station) {
          case station.branch {
            Some(branch) -> Ok(string.trim(branch))
            None ->
              Error(
                label
                <> " has more than one Work Station: give each one a Branch name.",
              )
          }
        }),
      )
      let unique = set.from_list(branches)
      case
        list.any(branches, fn(branch) {
          result.is_error(text.check(branch, line.max_name_length))
        }),
        set.size(unique) == list.length(branches)
      {
        True, _ ->
          Error(
            label
            <> " has a Branch name that is empty or longer than "
            <> int.to_string(line.max_name_length)
            <> " characters.",
          )
        False, False -> Error(label <> " has two Branches with the same name.")
        False, True -> Ok(Some(unique))
      }
    }
  }
}

fn check_name(name: String, when_empty: String) -> Result(Nil, String) {
  text.check(name, line.max_name_length)
  |> result.replace(Nil)
  |> result.map_error(fn(error) {
    case error {
      text.Empty -> when_empty
      text.TooLong ->
        "\""
        <> string.trim(name)
        <> "\" is longer than "
        <> int.to_string(line.max_name_length)
        <> " characters."
    }
  })
}

/// Everything the running flow forbids: work must not be lost or move back.
fn check_change(
  wanted: Design,
  current: Design,
  held: Dict(String, Held),
  busy: List(#(String, String)),
  partial_split: Bool,
) -> Result(Nil, String) {
  let placed = placed(wanted.steps)
  let current_stations = stations_by_id(current.steps)
  let wanted_ids = list.filter_map(placed, fn(entry) { id_of(entry.1) })
  let kept_team_members =
    list.map(wanted.team_members, fn(team_member) { team_member.id })
  use _ <- result.try(check_structure(wanted.steps))
  use _ <- result.try(check_labels(wanted.labels))
  use _ <- result.try(check_team_members(
    wanted.team_members,
    current.team_members,
  ))
  use _ <- result.try(
    case list.length(wanted_ids) == set.size(set.from_list(wanted_ids)) {
      True -> Ok(Nil)
      False -> Error("A Work Station shows two times in the design.")
    },
  )
  use _ <- result.try(
    list.try_each(placed, fn(entry) {
      let #(position, station) = entry
      check_station(
        station,
        position,
        current_stations,
        held,
        kept_team_members,
      )
    }),
  )
  use _ <- result.try(check_removed_stations(current_stations, wanted_ids, held))
  use _ <- result.try(check_locked_order(placed, held))
  use _ <- result.try(check_busy(
    busy,
    placed,
    current.team_members,
    current_stations,
  ))
  case
    partial_split
    && !set.is_subset(branch_names(current.steps), branch_names(wanted.steps))
  {
    True ->
      Error(
        "A Piece waits at the Split for some Branches to pull it. Keep every Branch until they all have pulled it.",
      )
    False -> Ok(Nil)
  }
}

/// A Team Member is added on its own before the design names it.
fn check_team_members(
  wanted: List(TeamMember),
  current: List(TeamMember),
) -> Result(Nil, String) {
  // A linked Team Member carries its Account's name, which can be longer.
  // Only a name the owner types must fit.
  use _ <- result.try(
    list.try_each(wanted, fn(team_member) {
      case list.contains(current, team_member) {
        True -> Ok(Nil)
        False -> check_name(team_member.name, "Each Team Member needs a name.")
      }
    }),
  )
  let known = list.map(current, fn(team_member) { team_member.id })
  list.try_each(wanted, fn(team_member) {
    case list.contains(known, team_member.id) {
      True -> Ok(Nil)
      False -> Error("Add a new Team Member before you use them.")
    }
  })
}

/// A Work Station that holds work cannot go.
fn check_removed_stations(
  current: Dict(String, Station),
  wanted_ids: List(String),
  held: Dict(String, Held),
) -> Result(Nil, String) {
  dict.to_list(current)
  |> list.try_each(fn(entry) {
    let #(id, station) = entry
    case list.contains(wanted_ids, id), dict.get(held, id) {
      False, Ok(Held(locked: True, ..)) ->
        Error(
          station.name
          <> " holds work (a Piece, a Rework or an Andon). It cannot go until that work moves on.",
        )
      _, _ -> Ok(Nil)
    }
  })
}

/// A Team Member with work in hand stays in its Work Station. `busy` pairs
/// a Work Station id with a Team Member id.
fn check_busy(
  busy: List(#(String, String)),
  placed: List(#(Int, Station)),
  team_members: List(TeamMember),
  current: Dict(String, Station),
) -> Result(Nil, String) {
  list.try_each(busy, fn(pair) {
    let #(station_id, team_member_id) = pair
    let stays =
      list.find(placed, fn(entry) { id_of(entry.1) == Ok(station_id) })
      |> result.map(fn(entry) {
        list.contains({ entry.1 }.team_members, team_member_id)
      })
    case stays {
      Ok(False) ->
        Error(
          name_of(team_members, team_member_id)
          <> " has work in hand at "
          <> name_of_station(current, station_id)
          <> " and must stay in it.",
        )
      _ -> Ok(Nil)
    }
  })
}

fn check_labels(labels: Labels) -> Result(Nil, String) {
  [labels.demand, labels.demands, labels.piece, labels.pieces]
  |> list.try_each(fn(label) {
    check_name(label, "Each label needs a word, for example \"Feature\".")
  })
}

fn check_station(
  station: Station,
  position: Int,
  current: Dict(String, Station),
  held: Dict(String, Held),
  known_team_members: List(String),
) -> Result(Nil, String) {
  let label = case string.trim(station.name) {
    "" -> "A Work Station of step " <> int.to_string(position)
    name -> name
  }
  use _ <- result.try(check_name(
    station.name,
    "Each Work Station needs a name.",
  ))
  use _ <- result.try(case station.blue_bins >= 1 {
    True -> Ok(Nil)
    False -> Error(label <> " needs at least one Blue Bin.")
  })
  use _ <- result.try(case station.team_members {
    [] -> Error(label <> " needs at least one Team Member.")
    _ -> Ok(Nil)
  })
  use _ <- result.try(
    list.try_each(station.team_members, fn(team_member) {
      case list.contains(known_team_members, team_member) {
        True -> Ok(Nil)
        False ->
          Error(
            label <> " names a Team Member who is not in the Line any more.",
          )
      }
    }),
  )
  use _ <- result.try(
    case list.contains(station.team_members, station.team_leader) {
      True -> Ok(Nil)
      False -> Error(label <> " needs a Team Leader among its Team Members.")
    },
  )
  case station.id {
    None -> Ok(Nil)
    Some(id) ->
      case dict.get(current, id), dict.get(held, id) {
        Error(Nil), _ | _, Error(Nil) ->
          Error(label <> " is not in this Line any more. Reload.")
        Ok(before), Ok(held) -> {
          use _ <- result.try(case station.blue_bins >= held.in_bins {
            True -> Ok(Nil)
            False ->
              Error(
                label
                <> " has "
                <> int.to_string(held.in_bins)
                <> " Pieces in its Blue Bins. Only an empty Blue Bin can go.",
              )
          })
          case held.locked && clean(station.branch) != clean(before.branch) {
            True ->
              Error(
                label
                <> " holds work, so its Branch cannot change until that work moves on.",
              )
            False -> Ok(Nil)
          }
        }
      }
  }
}

/// Work Stations that hold work keep their order: a Piece never moves backward
/// (ADR-0001), and Pieces side by side in Branches stay side by side.
fn check_locked_order(
  placed: List(#(Int, Station)),
  held: Dict(String, Held),
) -> Result(Nil, String) {
  let locked =
    list.filter_map(placed, fn(entry) {
      use id <- result.try(id_of(entry.1))
      use found <- result.try(dict.get(held, id))
      case found.locked {
        True -> Ok(#(found.position, entry.0, entry.1.name))
        False -> Error(Nil)
      }
    })
  let moved =
    list.combination_pairs(locked)
    |> list.find(fn(pair) {
      let #(#(old_a, new_a, _), #(old_b, new_b, _)) = pair
      int.compare(old_a, old_b) != int.compare(new_a, new_b)
    })
  case moved {
    Ok(#(#(_, _, a), #(_, _, b))) ->
      Error(
        a <> " and " <> b <> " hold work, so they keep their order in the Line.",
      )
    Error(Nil) -> Ok(Nil)
  }
}

pub fn add_team_member(
  connection: sqlight.Connection,
  name: String,
) -> Result(TeamMember, DesignError) {
  let trimmed = string.trim(name)
  use _ <- result.try(
    check_name(trimmed, "A Team Member needs a name.")
    |> result.map_error(Invalid),
  )
  use rows <- result.try(
    query(
      connection,
      "insert into team_member (id, name)
       values ('pe-' || lower(hex(randomblob(6))), ?1)
       returning id, name",
      [sqlight.text(trimmed)],
      {
        use id <- decode.field(0, decode.string)
        use name <- decode.field(1, decode.string)
        decode.success(TeamMember(id:, name:))
      },
    )
    |> result.replace_error(StoreFailed),
  )
  use team_member <- result.try(
    list.first(rows) |> result.replace_error(StoreFailed),
  )
  use _ <- result.try(
    changed(connection, [
      #("change", json.string("team_member_added")),
      #("teamMember", json.string(team_member.id)),
      #("name", json.string(team_member.name)),
    ]),
  )
  Ok(team_member)
}

pub fn save(
  connection: sqlight.Connection,
  wanted: Design,
) -> Result(Design, DesignError) {
  // A removed Work Station leaves its id in past rows (passes, Deviations,
  // closed Rework) so the history stays (F40): the delete must pass even on a
  // connection that enforces foreign keys, as the tests' connections do.
  // Outside the transaction, where SQLite ignores the pragma.
  use _ <- result.try(
    sqlight.exec("pragma foreign_keys = off;", connection)
    |> result.replace_error(StoreFailed),
  )
  use <- db.transaction(connection, fn(_) { StoreFailed })
  save_inside(connection, wanted)
}

fn save_inside(
  connection: sqlight.Connection,
  wanted: Design,
) -> Result(Design, DesignError) {
  use #(current, held) <- result.try(
    load(connection) |> result.replace_error(StoreFailed),
  )
  use busy <- result.try(
    query(
      connection,
      "select station_id, assignee from piece
        where assignee is not null and station_id is not null
       union
       select station_id, assignee from rework
        where closed_at is null and assignee is not null",
      [],
      pair_decoder(),
    )
    |> result.replace_error(StoreFailed),
  )
  use partial_split <- result.try(
    query(
      connection,
      "select exists (select 1 from piece p
                       where p.state = 'in_bin'
                         and exists (select 1 from piece s
                                      where s.parent_id = p.id))",
      [],
      decode.at([0], sqlight.decode_bool()),
    )
    |> result.map(fn(rows) { rows == [True] })
    |> result.replace_error(StoreFailed),
  )
  use _ <- result.try(
    check_change(wanted, current, held, busy, partial_split)
    |> result.map_error(Invalid),
  )

  use _ <- result.try(save_labels(connection, current.labels, wanted.labels))
  use _ <- result.try(save_team_members(
    connection,
    current.team_members,
    wanted.team_members,
  ))
  let current_stations = stations_by_id(current.steps)
  use _ <- result.try(
    list.try_each(placed(wanted.steps), fn(entry) {
      let #(position, station) = entry
      case station.id {
        None -> add_station(connection, position, station)
        Some(id) ->
          case dict.get(current_stations, id), dict.get(held, id) {
            Ok(before), Ok(found) ->
              change_station(connection, id, position, before, found, station)
            _, _ -> Error(StoreFailed)
          }
      }
    }),
  )
  let wanted_ids =
    placed(wanted.steps) |> list.filter_map(fn(entry) { id_of(entry.1) })
  use _ <- result.try(
    dict.to_list(current_stations)
    |> list.filter(fn(entry) { !list.contains(wanted_ids, entry.0) })
    |> list.try_each(fn(entry) { remove_station(connection, entry.0, entry.1) }),
  )
  use _ <- result.try(save_steps(connection, current.steps, wanted.steps))

  load(connection)
  |> result.map(fn(loaded) { loaded.0 })
  |> result.replace_error(StoreFailed)
}

fn save_labels(
  connection: sqlight.Connection,
  before: Labels,
  wanted: Labels,
) -> Result(Nil, DesignError) {
  let wanted =
    Labels(
      demand: string.trim(wanted.demand),
      demands: string.trim(wanted.demands),
      piece: string.trim(wanted.piece),
      pieces: string.trim(wanted.pieces),
    )
  use <- bool.guard(wanted == before, Ok(Nil))
  use _ <- result.try(
    run(
      connection,
      "update line_label set demand = ?1, demands = ?2, piece = ?3, pieces = ?4
      where id = 1",
      [
        sqlight.text(wanted.demand),
        sqlight.text(wanted.demands),
        sqlight.text(wanted.piece),
        sqlight.text(wanted.pieces),
      ],
    ),
  )
  changed(connection, [
    #("change", json.string("labels_changed")),
    #("demand", json.string(wanted.demand)),
    #("demands", json.string(wanted.demands)),
    #("piece", json.string(wanted.piece)),
    #("pieces", json.string(wanted.pieces)),
  ])
}

fn save_team_members(
  connection: sqlight.Connection,
  before: List(TeamMember),
  wanted: List(TeamMember),
) -> Result(Nil, DesignError) {
  use _ <- result.try(
    list.filter(before, fn(team_member) {
      !list.any(wanted, fn(one) { one.id == team_member.id })
    })
    |> list.try_each(remove_team_member(connection, _)),
  )
  list.try_each(wanted, fn(team_member) {
    let name = string.trim(team_member.name)
    case list.find(before, fn(one) { one.id == team_member.id }) {
      Ok(found) if found.name != name -> {
        use _ <- result.try(
          run(connection, "update team_member set name = ?2 where id = ?1", [
            sqlight.text(team_member.id),
            sqlight.text(name),
          ]),
        )
        changed(connection, [
          #("change", json.string("team_member_renamed")),
          #("teamMember", json.string(team_member.id)),
          #("name", json.string(name)),
        ])
      }
      _ -> Ok(Nil)
    }
  })
}

/// A linked Team Member shows its Account's name (F47): `names` pairs a
/// Team Member id with that name. True when a name changed.
pub fn name_linked(
  connection: sqlight.Connection,
  names: List(#(String, String)),
) -> Result(Bool, DesignError) {
  use <- db.transaction(connection, fn(_) { StoreFailed })
  list.try_fold(names, False, fn(any, pair) {
    let #(id, name) = pair
    use found <- result.try(
      query(
        connection,
        "update team_member set name = ?2
            where id = ?1 and removed_at is null and name <> ?2
           returning id",
        [sqlight.text(id), sqlight.text(name)],
        decode.at([0], decode.string),
      )
      |> result.replace_error(StoreFailed),
    )
    case found {
      [] -> Ok(any)
      _ -> {
        use _ <- result.try(
          changed(connection, [
            #("change", json.string("team_member_renamed")),
            #("teamMember", json.string(id)),
            #("name", json.string(name)),
          ]),
        )
        Ok(True)
      }
    }
  })
}

/// The row stays, so the history keeps the name (F40).
fn remove_team_member(
  connection: sqlight.Connection,
  team_member: TeamMember,
) -> Result(Nil, DesignError) {
  use _ <- result.try(
    run(
      connection,
      "delete from station_team_member where team_member_id = ?1",
      [
        sqlight.text(team_member.id),
      ],
    ),
  )
  use _ <- result.try(
    run(connection, "delete from helper where team_member_id = ?1", [
      sqlight.text(team_member.id),
    ]),
  )
  use _ <- result.try(
    run(
      connection,
      "update team_member set removed_at = strftime('%Y-%m-%dT%H:%M:%SZ', 'now')
      where id = ?1",
      [sqlight.text(team_member.id)],
    ),
  )
  changed(connection, [
    #("change", json.string("team_member_removed")),
    #("teamMember", json.string(team_member.id)),
    #("name", json.string(team_member.name)),
  ])
}

fn add_station(
  connection: sqlight.Connection,
  position: Int,
  station: Station,
) -> Result(Nil, DesignError) {
  use rows <- result.try(
    query(
      connection,
      "insert into work_station
         (id, name, position, branch, blue_bins, team_leader)
       values ('ws-' || lower(hex(randomblob(6))), ?1, ?2, ?3, ?4, ?5)
       returning id",
      [
        sqlight.text(string.trim(station.name)),
        sqlight.int(position),
        sqlight.nullable(sqlight.text, clean(station.branch)),
        sqlight.int(station.blue_bins),
        sqlight.text(station.team_leader),
      ],
      decode.at([0], decode.string),
    )
    |> result.replace_error(StoreFailed),
  )
  use id <- result.try(list.first(rows) |> result.replace_error(StoreFailed))
  use _ <- result.try(set_team_members(connection, id, station.team_members))
  // Every Blue Bin of a new Work Station is empty: one Kanban for each (F7).
  use _ <- result.try(send_kanbans(connection, id, station.blue_bins))
  changed(connection, station_payload("station_added", id, position, station))
}

fn change_station(
  connection: sqlight.Connection,
  id: String,
  position: Int,
  before: Station,
  held: Held,
  wanted: Station,
) -> Result(Nil, DesignError) {
  let wanted =
    Station(
      ..wanted,
      name: string.trim(wanted.name),
      branch: clean(wanted.branch),
    )
  let same_team_members =
    list.sort(wanted.team_members, string.compare)
    == list.sort(before.team_members, string.compare)
  let same =
    wanted.name == before.name
    && wanted.branch == clean(before.branch)
    && wanted.blue_bins == before.blue_bins
    && wanted.team_leader == before.team_leader
    && same_team_members
    && position == held.position
  use <- bool.guard(same, Ok(Nil))

  use _ <- result.try(
    run(
      connection,
      "update work_station
        set name = ?2, position = ?3, branch = ?4, blue_bins = ?5,
            team_leader = ?6
      where id = ?1",
      [
        sqlight.text(id),
        sqlight.text(wanted.name),
        sqlight.int(position),
        sqlight.nullable(sqlight.text, wanted.branch),
        sqlight.int(wanted.blue_bins),
        sqlight.text(wanted.team_leader),
      ],
    ),
  )
  use _ <- result.try(case same_team_members {
    True -> Ok(Nil)
    False -> set_team_members(connection, id, wanted.team_members)
  })
  // Kanbans ≤ empty Blue Bins (F7): a new bin brings a Kanban, a removed empty
  // bin takes the newest one back.
  let free = wanted.blue_bins - held.in_bins
  let added = wanted.blue_bins - before.blue_bins
  use _ <- result.try(case added > 0 {
    True -> send_kanbans(connection, id, int.min(added, free - held.kanbans))
    False -> withdraw_kanbans(connection, id, held.kanbans - free)
  })
  changed(connection, station_payload("station_changed", id, position, wanted))
}

fn remove_station(
  connection: sqlight.Connection,
  id: String,
  station: Station,
) -> Result(Nil, DesignError) {
  use kanbans <- result.try(
    query(
      connection,
      "select count(*) from kanban where station_id = ?1",
      [sqlight.text(id)],
      decode.at([0], decode.int),
    )
    |> result.replace_error(StoreFailed),
  )
  use _ <- result.try(withdraw_kanbans(
    connection,
    id,
    list.first(kanbans) |> result.unwrap(0),
  ))
  use _ <- result.try(
    run(connection, "delete from station_team_member where station_id = ?1", [
      sqlight.text(id),
    ]),
  )
  use _ <- result.try(
    run(connection, "delete from work_station where id = ?1", [
      sqlight.text(id),
    ]),
  )
  changed(connection, [
    #("change", json.string("station_removed")),
    #("station", json.string(id)),
    #("name", json.string(station.name)),
  ])
}

fn set_team_members(
  connection: sqlight.Connection,
  station_id: String,
  team_members: List(String),
) -> Result(Nil, DesignError) {
  use _ <- result.try(
    run(connection, "delete from station_team_member where station_id = ?1", [
      sqlight.text(station_id),
    ]),
  )
  list.unique(team_members)
  |> list.try_each(fn(team_member) {
    run(
      connection,
      "insert into station_team_member (station_id, team_member_id) values (?1, ?2)",
      [sqlight.text(station_id), sqlight.text(team_member)],
    )
  })
}

/// `kanban_sent` and `kanban_spent` date the Kanbans held, for the Starvation
/// Time, so each Kanban that comes or goes is in the log.
fn send_kanbans(
  connection: sqlight.Connection,
  station_id: String,
  count: Int,
) -> Result(Nil, DesignError) {
  use <- bool.guard(count <= 0, Ok(Nil))
  list.repeat(Nil, count)
  |> list.try_each(fn(_) {
    use _ <- result.try(
      run(
        connection,
        "insert into kanban (id, station_id)
       values ('kb-' || lower(hex(randomblob(6))), ?1)",
        [sqlight.text(station_id)],
      ),
    )
    kanban_event(connection, "kanban_sent", station_id)
  })
}

fn withdraw_kanbans(
  connection: sqlight.Connection,
  station_id: String,
  count: Int,
) -> Result(Nil, DesignError) {
  use <- bool.guard(count <= 0, Ok(Nil))
  use _ <- result.try(
    run(
      connection,
      "delete from kanban where id in (
       select id from kanban where station_id = ?1
        order by created_at desc, rowid desc limit ?2)",
      [sqlight.text(station_id), sqlight.int(count)],
    ),
  )
  list.repeat(Nil, count)
  |> list.try_each(fn(_) {
    kanban_event(connection, "kanban_spent", station_id)
  })
}

fn kanban_event(
  connection: sqlight.Connection,
  kind: String,
  station_id: String,
) -> Result(Nil, DesignError) {
  run(
    connection,
    "insert into flow_event (kind, payload)
     values (?1, json_object('station', ?2))",
    [sqlight.text(kind), sqlight.text(station_id)],
  )
}

fn save_steps(
  connection: sqlight.Connection,
  before: List(Step),
  wanted: List(Step),
) -> Result(Nil, DesignError) {
  use _ <- result.try(run(connection, "delete from line_step", []))
  list.index_map(wanted, fn(step, index) {
    #(index + 1, string.trim(step.name))
  })
  |> list.try_each(fn(entry) {
    let #(position, name) = entry
    use _ <- result.try(
      run(connection, "insert into line_step (position, name) values (?1, ?2)", [
        sqlight.int(position),
        sqlight.text(name),
      ]),
    )
    let old =
      list.drop(before, position - 1)
      |> list.first
      |> result.map(fn(step) { step.name })
    case old == Ok(name) {
      True -> Ok(Nil)
      False ->
        changed(connection, [
          #("change", json.string("step_renamed")),
          #("position", json.int(position)),
          #("name", json.string(name)),
        ])
    }
  })
}

fn changed(
  connection: sqlight.Connection,
  payload: List(#(String, Json)),
) -> Result(Nil, DesignError) {
  run(
    connection,
    "insert into flow_event (kind, payload) values ('line_changed', ?1)",
    [sqlight.text(json.to_string(json.object(payload)))],
  )
}

fn station_payload(
  change: String,
  id: String,
  position: Int,
  station: Station,
) -> List(#(String, Json)) {
  [
    #("change", json.string(change)),
    #("station", json.string(id)),
    #("name", json.string(string.trim(station.name))),
    #("position", json.int(position)),
    #("branch", json.nullable(clean(station.branch), json.string)),
    #("blueBins", json.int(station.blue_bins)),
    #("teamLeader", json.string(station.team_leader)),
    #("teamMembers", json.array(station.team_members, json.string)),
  ]
}

pub fn labels_json(labels: Labels) -> Json {
  json.object([
    #("demand", json.string(labels.demand)),
    #("demands", json.string(labels.demands)),
    #("piece", json.string(labels.piece)),
    #("pieces", json.string(labels.pieces)),
  ])
}

pub fn to_json(
  design: Design,
  held: Dict(String, Held),
  links: List(accounts.Link),
  takt_hours: Float,
  suggestions: Dict(String, measures.Suggestion),
) -> Json {
  json.object([
    #("labels", labels_json(design.labels)),
    #("taktTimeHours", json.float(takt_hours)),
    #(
      "teamMembers",
      json.array(design.team_members, team_member_json(_, links)),
    ),
    #(
      "steps",
      json.array(design.steps, fn(step) {
        json.object([
          #("name", json.string(step.name)),
          #(
            "stations",
            json.array(step.stations, station_json(
              _,
              held,
              takt_hours,
              suggestions,
            )),
          ),
        ])
      }),
    ),
  ])
}

fn team_member_json(
  team_member: TeamMember,
  links: List(accounts.Link),
) -> Json {
  let link = list.find(links, fn(link) { link.team_member == team_member.id })
  json.object([
    #("id", json.string(team_member.id)),
    #("name", json.string(team_member.name)),
    #(
      "email",
      json.string(
        result.map(link, fn(link) { link.email }) |> result.unwrap(""),
      ),
    ),
    #(
      "account",
      json.nullable(
        result.try(link, fn(link) { option.to_result(link.account, Nil) })
          |> option.from_result,
        fn(account) {
          json.object([
            #("firstName", json.string(account.first_name)),
            #("lastName", json.string(account.last_name)),
          ])
        },
      ),
    ),
  ])
}

fn station_json(
  station: Station,
  held: Dict(String, Held),
  takt_hours: Float,
  suggestions: Dict(String, measures.Suggestion),
) -> Json {
  let found = id_of(station) |> result.try(dict.get(held, _))
  json.object([
    #("id", json.nullable(station.id, json.string)),
    #("name", json.string(station.name)),
    #("branch", json.nullable(station.branch, json.string)),
    #("blueBins", json.int(station.blue_bins)),
    #("teamLeader", json.string(station.team_leader)),
    #("teamMembers", json.array(station.team_members, json.string)),
    #("locked", json.bool(result.map(found, fn(h) { h.locked }) == Ok(True))),
    #(
      "minBlueBins",
      json.int(int.max(
        1,
        result.map(found, fn(h) { h.in_bins }) |> result.unwrap(0),
      )),
    ),
    #(
      "suggestion",
      suggestion_json(
        id_of(station)
        |> result.try(dict.get(suggestions, _))
        |> result.unwrap(measures.suggest([], takt_hours)),
      ),
    ),
  ])
}

fn suggestion_json(suggestion: measures.Suggestion) -> Json {
  json.object([
    #("passes", json.int(suggestion.passes)),
    #(
      "replenishmentHours",
      json.nullable(suggestion.replenishment, fn(seconds) {
        json.float(int.to_float({ seconds * 10 + 1800 } / 3600) /. 10.0)
      }),
    ),
    #("blueBins", json.nullable(suggestion.blue_bins, json.int)),
  ])
}

pub fn decoder() -> decode.Decoder(Design) {
  let labels = {
    use demand <- decode.field("demand", decode.string)
    use demands <- decode.field("demands", decode.string)
    use piece <- decode.field("piece", decode.string)
    use pieces <- decode.field("pieces", decode.string)
    decode.success(Labels(demand:, demands:, piece:, pieces:))
  }
  let team_member = {
    use id <- decode.field("id", decode.string)
    use name <- decode.field("name", decode.string)
    decode.success(TeamMember(id:, name:))
  }
  let station = {
    use id <- decode.optional_field("id", None, decode.optional(decode.string))
    use name <- decode.field("name", decode.string)
    use branch <- decode.optional_field(
      "branch",
      None,
      decode.optional(decode.string),
    )
    use blue_bins <- decode.field("blueBins", decode.int)
    use team_leader <- decode.field("teamLeader", decode.string)
    use team_members <- decode.field("teamMembers", decode.list(decode.string))
    decode.success(Station(
      id:,
      name:,
      branch:,
      blue_bins:,
      team_leader:,
      team_members:,
    ))
  }
  let step = {
    use name <- decode.field("name", decode.string)
    use stations <- decode.field("stations", decode.list(station))
    decode.success(Step(name:, stations:))
  }
  use labels <- decode.field("labels", labels)
  use team_members <- decode.field("teamMembers", decode.list(team_member))
  use steps <- decode.field("steps", decode.list(step))
  decode.success(Design(labels:, team_members:, steps:))
}

fn placed(steps: List(Step)) -> List(#(Int, Station)) {
  list.index_map(steps, fn(step, index) {
    list.map(step.stations, fn(station) { #(index + 1, station) })
  })
  |> list.flatten
}

fn stations_by_id(steps: List(Step)) -> Dict(String, Station) {
  placed(steps)
  |> list.filter_map(fn(entry) {
    id_of(entry.1) |> result.map(fn(id) { #(id, entry.1) })
  })
  |> dict.from_list
}

fn branch_names(steps: List(Step)) -> set.Set(String) {
  placed(steps)
  |> list.filter_map(fn(entry) {
    clean({ entry.1 }.branch) |> option.to_result(Nil)
  })
  |> set.from_list
}

fn id_of(station: Station) -> Result(String, Nil) {
  option.to_result(station.id, Nil)
}

fn clean(branch: Option(String)) -> Option(String) {
  case option.map(branch, string.trim) {
    Some("") -> None
    other -> other
  }
}

fn name_of(team_members: List(TeamMember), id: String) -> String {
  list.find(team_members, fn(team_member) { team_member.id == id })
  |> result.map(fn(team_member) { team_member.name })
  |> result.unwrap("A Team Member")
}

fn name_of_station(stations: Dict(String, Station), id: String) -> String {
  dict.get(stations, id)
  |> result.map(fn(station) { station.name })
  |> result.unwrap("their Work Station")
}

fn pair_decoder() -> decode.Decoder(#(String, String)) {
  use a <- decode.field(0, decode.string)
  use b <- decode.field(1, decode.string)
  decode.success(#(a, b))
}

fn query(
  connection: sqlight.Connection,
  sql: String,
  values: List(sqlight.Value),
  decoder: decode.Decoder(a),
) -> Result(List(a), Nil) {
  sqlight.query(sql, on: connection, with: values, expecting: decoder)
  |> result.replace_error(Nil)
}

fn run(
  connection: sqlight.Connection,
  sql: String,
  values: List(sqlight.Value),
) -> Result(Nil, DesignError) {
  sqlight.query(
    sql,
    on: connection,
    with: values,
    expecting: decode.success(Nil),
  )
  |> result.replace(Nil)
  |> result.replace_error(StoreFailed)
}
