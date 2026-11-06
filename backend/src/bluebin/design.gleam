//// Design and change a running Value Stream without code (F39–F41).
////
//// The designer sends the whole Value Stream it wants; `save` compares it with
//// the one that runs, refuses what would lose or move work (R1), and applies
//// the rest in one transaction with one dated `stream_changed` event per
//// change (F40).

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

/// The longest name the wall-TV column layout holds without breaking.
pub const max_name_length = 40

pub type Labels {
  Labels(demand: String, demands: String, piece: String, pieces: String)
}

pub type Person {
  Person(id: String, name: String)
}

/// `id` is None for a Work Station the designer adds.
pub type Station {
  Station(
    id: Option(String),
    name: String,
    branch: Option(String),
    blue_bins: Int,
    team_leader: String,
    people: List(String),
  )
}

pub type Step {
  Step(name: String, stations: List(Station))
}

pub type Design {
  Design(labels: Labels, people: List(Person), steps: List(Step))
}

/// What the running flow holds at one Work Station. A locked Work Station holds
/// a Piece, an open Rework or an open Andon.
pub type Held {
  Held(position: Int, locked: Bool, in_bins: Int, kanbans: Int)
}

pub type DesignError {
  Invalid(String)
  StoreFailed
}

// --- Read ------------------------------------------------------------------

pub fn load_labels(connection: sqlight.Connection) -> Result(Labels, Nil) {
  sqlight.query(
    "select demand, demands, piece, pieces from stream_label where id = 1",
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
  use people <- result.try(
    query(connection, "select id, name from person order by rowid", [], {
      use id <- decode.field(0, decode.string)
      use name <- decode.field(1, decode.string)
      decode.success(Person(id:, name:))
    }),
  )
  use members <- result.try(query(
    connection,
    "select station_id, person_id from station_person order by rowid",
    [],
    pair_decoder(),
  ))
  use names <- result.try(
    query(connection, "select position, name from stream_step", [], {
      use position <- decode.field(0, decode.int)
      use name <- decode.field(1, decode.string)
      decode.success(#(position, name))
    }),
  )
  use rows <- result.try(
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
            people: list.filter_map(members, fn(member) {
              case member.0 == id {
                True -> Ok(member.1)
                False -> Error(Nil)
              }
            }),
          ),
          Held(position:, locked:, in_bins:, kanbans:),
        ))
      },
    ),
  )

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

  Ok(#(Design(labels:, people:, steps:), held))
}

// --- Check -----------------------------------------------------------------

/// The shape of the steps alone: one trunk Work Station per step, or a Split
/// into two or more named Branches that run side by side until the Assembly.
/// Nested Splits are not supported.
pub fn check_structure(steps: List(Step)) -> Result(Nil, String) {
  use <- bool.guard(
    steps == [],
    Error("A Value Stream needs at least one Work Station."),
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
          branch == "" || string.length(branch) > max_name_length
        }),
        set.size(unique) == list.length(branches)
      {
        True, _ ->
          Error(
            label
            <> " has a Branch name that is empty or longer than "
            <> int.to_string(max_name_length)
            <> " characters.",
          )
        False, False -> Error(label <> " has two Branches with the same name.")
        False, True -> Ok(Some(unique))
      }
    }
  }
}

fn check_name(name: String, when_empty: String) -> Result(Nil, String) {
  let trimmed = string.trim(name)
  case trimmed == "", string.length(trimmed) > max_name_length {
    True, _ -> Error(when_empty)
    _, True ->
      Error(
        "\""
        <> trimmed
        <> "\" is longer than "
        <> int.to_string(max_name_length)
        <> " characters.",
      )
    False, False -> Ok(Nil)
  }
}

/// Everything the running flow forbids: work must not be lost or move back.
pub fn check_change(
  wanted: Design,
  current: Design,
  held: Dict(String, Held),
  busy: List(#(String, String)),
  partial_split: Bool,
) -> Result(Nil, String) {
  use _ <- result.try(check_structure(wanted.steps))
  use _ <- result.try(check_labels(wanted.labels))
  use _ <- result.try(
    list.try_each(wanted.people, fn(person) {
      check_name(person.name, "Each Person needs a name.")
    }),
  )

  let known_people = list.map(current.people, fn(person) { person.id })
  let placed = placed(wanted.steps)
  let current_stations = stations_by_id(current.steps)
  let wanted_ids = list.filter_map(placed, fn(entry) { entry.1 |> id_of })

  use _ <- result.try(
    list.try_each(wanted.people, fn(person) {
      case list.contains(known_people, person.id) {
        True -> Ok(Nil)
        False -> Error("Add a new Person before you use them.")
      }
    }),
  )
  use _ <- result.try(
    case list.length(wanted_ids) == set.size(set.from_list(wanted_ids)) {
      True -> Ok(Nil)
      False -> Error("A Work Station shows two times in the design.")
    },
  )
  use _ <- result.try(
    list.try_each(placed, fn(entry) {
      let #(position, station) = entry
      check_station(station, position, current_stations, held, known_people)
    }),
  )

  // Removed Work Stations: only the ones that hold no work.
  use _ <- result.try(
    dict.to_list(current_stations)
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
    }),
  )

  use _ <- result.try(check_locked_order(placed, held))

  // A Person with work in hand at a Work Station stays in it.
  use _ <- result.try(
    list.try_each(busy, fn(pair) {
      let #(station_id, person_id) = pair
      let stays =
        list.find(placed, fn(entry) { id_of(entry.1) == Ok(station_id) })
        |> result.map(fn(entry) { list.contains({ entry.1 }.people, person_id) })
      case stays {
        Ok(False) ->
          Error(
            name_of(current.people, person_id)
            <> " has work in hand at "
            <> name_of_station(current_stations, station_id)
            <> " and must stay in it.",
          )
        _ -> Ok(Nil)
      }
    }),
  )

  // A Piece waiting at a Split for some Branches still needs them all.
  let branches_now = branch_names(current.steps)
  let branches_wanted = branch_names(wanted.steps)
  case partial_split && !set.is_subset(branches_now, branches_wanted) {
    True ->
      Error(
        "A Piece waits at the Split for some Branches to pull it. Keep every Branch until they all have pulled it.",
      )
    False -> Ok(Nil)
  }
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
  known_people: List(String),
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
  use _ <- result.try(case station.people {
    [] -> Error(label <> " needs at least one Person.")
    _ -> Ok(Nil)
  })
  use _ <- result.try(
    list.try_each(station.people, fn(person) {
      case list.contains(known_people, person) {
        True -> Ok(Nil)
        False -> Error(label <> " names a Person that does not exist.")
      }
    }),
  )
  use _ <- result.try(case list.contains(station.people, station.team_leader) {
    True -> Ok(Nil)
    False -> Error(label <> " needs a Team Leader among its People.")
  })
  case station.id {
    None -> Ok(Nil)
    Some(id) ->
      case dict.get(current, id), dict.get(held, id) {
        Error(Nil), _ | _, Error(Nil) ->
          Error(label <> " is not in this Value Stream any more. Reload.")
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
        a
        <> " and "
        <> b
        <> " hold work, so they keep their order in the Value Stream.",
      )
    Error(Nil) -> Ok(Nil)
  }
}

// --- Write -----------------------------------------------------------------

pub fn add_person(
  connection: sqlight.Connection,
  name: String,
) -> Result(Person, DesignError) {
  let trimmed = string.trim(name)
  use _ <- result.try(
    check_name(trimmed, "A Person needs a name.") |> result.map_error(Invalid),
  )
  use rows <- result.try(
    query(
      connection,
      "insert into person (id, name)
       values ('pe-' || lower(hex(randomblob(6))), ?1)
       returning id, name",
      [sqlight.text(trimmed)],
      {
        use id <- decode.field(0, decode.string)
        use name <- decode.field(1, decode.string)
        decode.success(Person(id:, name:))
      },
    )
    |> result.replace_error(StoreFailed),
  )
  use person <- result.try(
    list.first(rows) |> result.replace_error(StoreFailed),
  )
  use _ <- result.try(
    changed(connection, [
      #("change", json.string("person_added")),
      #("person", json.string(person.id)),
      #("name", json.string(person.name)),
    ]),
  )
  Ok(person)
}

/// Applies `wanted` in one transaction, or nothing at all.
pub fn save(
  connection: sqlight.Connection,
  wanted: Design,
) -> Result(Design, DesignError) {
  // A removed Work Station leaves its id in past rows (passes, Deviations,
  // closed Rework): the history stays (F40), so it must not block the delete.
  use _ <- result.try(exec(connection, "pragma foreign_keys = off;"))
  use _ <- result.try(exec(connection, "begin immediate;"))
  case save_inside(connection, wanted) {
    Ok(saved) -> {
      use _ <- result.try(exec(connection, "commit;"))
      Ok(saved)
    }
    Error(error) -> {
      let _ = exec(connection, "rollback;")
      Error(error)
    }
  }
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
  use _ <- result.try(save_people(connection, current.people, wanted.people))
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
      "update stream_label set demand = ?1, demands = ?2, piece = ?3, pieces = ?4
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

fn save_people(
  connection: sqlight.Connection,
  before: List(Person),
  wanted: List(Person),
) -> Result(Nil, DesignError) {
  list.try_each(wanted, fn(person) {
    let name = string.trim(person.name)
    case list.find(before, fn(one) { one.id == person.id }) {
      Ok(found) if found.name != name -> {
        use _ <- result.try(
          run(connection, "update person set name = ?2 where id = ?1", [
            sqlight.text(person.id),
            sqlight.text(name),
          ]),
        )
        changed(connection, [
          #("change", json.string("person_renamed")),
          #("person", json.string(person.id)),
          #("name", json.string(name)),
        ])
      }
      _ -> Ok(Nil)
    }
  })
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
  use _ <- result.try(set_people(connection, id, station.people))
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
  let same_people =
    list.sort(wanted.people, string.compare)
    == list.sort(before.people, string.compare)
  let same =
    wanted.name == before.name
    && wanted.branch == clean(before.branch)
    && wanted.blue_bins == before.blue_bins
    && wanted.team_leader == before.team_leader
    && same_people
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
  use _ <- result.try(case same_people {
    True -> Ok(Nil)
    False -> set_people(connection, id, wanted.people)
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
    run(connection, "delete from station_person where station_id = ?1", [
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

fn set_people(
  connection: sqlight.Connection,
  station_id: String,
  people: List(String),
) -> Result(Nil, DesignError) {
  use _ <- result.try(
    run(connection, "delete from station_person where station_id = ?1", [
      sqlight.text(station_id),
    ]),
  )
  list.unique(people)
  |> list.try_each(fn(person) {
    run(
      connection,
      "insert into station_person (station_id, person_id) values (?1, ?2)",
      [sqlight.text(station_id), sqlight.text(person)],
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
  use _ <- result.try(run(connection, "delete from stream_step", []))
  list.index_map(wanted, fn(step, index) {
    #(index + 1, string.trim(step.name))
  })
  |> list.try_each(fn(entry) {
    let #(position, name) = entry
    use _ <- result.try(
      run(
        connection,
        "insert into stream_step (position, name) values (?1, ?2)",
        [sqlight.int(position), sqlight.text(name)],
      ),
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

/// One dated event per change to the Value Stream (F40).
fn changed(
  connection: sqlight.Connection,
  payload: List(#(String, Json)),
) -> Result(Nil, DesignError) {
  run(
    connection,
    "insert into flow_event (kind, payload) values ('stream_changed', ?1)",
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
    #("people", json.array(station.people, json.string)),
  ]
}

// --- JSON ------------------------------------------------------------------

pub fn labels_json(labels: Labels) -> Json {
  json.object([
    #("demand", json.string(labels.demand)),
    #("demands", json.string(labels.demands)),
    #("piece", json.string(labels.piece)),
    #("pieces", json.string(labels.pieces)),
  ])
}

pub fn to_json(design: Design, held: Dict(String, Held)) -> Json {
  json.object([
    #("labels", labels_json(design.labels)),
    #(
      "people",
      json.array(design.people, fn(person) {
        json.object([
          #("id", json.string(person.id)),
          #("name", json.string(person.name)),
        ])
      }),
    ),
    #(
      "steps",
      json.array(design.steps, fn(step) {
        json.object([
          #("name", json.string(step.name)),
          #(
            "stations",
            json.array(step.stations, fn(station) {
              let found =
                option.to_result(station.id, Nil)
                |> result.try(dict.get(held, _))
              json.object([
                #("id", json.nullable(station.id, json.string)),
                #("name", json.string(station.name)),
                #("branch", json.nullable(station.branch, json.string)),
                #("blueBins", json.int(station.blue_bins)),
                #("teamLeader", json.string(station.team_leader)),
                #("people", json.array(station.people, json.string)),
                #(
                  "locked",
                  json.bool(result.map(found, fn(h) { h.locked }) == Ok(True)),
                ),
                #(
                  "minBlueBins",
                  json.int(int.max(
                    1,
                    result.map(found, fn(h) { h.in_bins }) |> result.unwrap(0),
                  )),
                ),
              ])
            }),
          ),
        ])
      }),
    ),
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
  let person = {
    use id <- decode.field("id", decode.string)
    use name <- decode.field("name", decode.string)
    decode.success(Person(id:, name:))
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
    use people <- decode.field("people", decode.list(decode.string))
    decode.success(Station(
      id:,
      name:,
      branch:,
      blue_bins:,
      team_leader:,
      people:,
    ))
  }
  let step = {
    use name <- decode.field("name", decode.string)
    use stations <- decode.field("stations", decode.list(station))
    decode.success(Step(name:, stations:))
  }
  use labels <- decode.field("labels", labels)
  use people <- decode.field("people", decode.list(person))
  use steps <- decode.field("steps", decode.list(step))
  decode.success(Design(labels:, people:, steps:))
}

// --- Helpers ---------------------------------------------------------------

/// Each Work Station with its 1-based step position.
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

/// A blank Branch name means no Branch.
fn clean(branch: Option(String)) -> Option(String) {
  case option.map(branch, string.trim) {
    Some("") -> None
    other -> other
  }
}

fn name_of(people: List(Person), id: String) -> String {
  list.find(people, fn(person) { person.id == id })
  |> result.map(fn(person) { person.name })
  |> result.unwrap("A Person")
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

fn exec(
  connection: sqlight.Connection,
  sql: String,
) -> Result(Nil, DesignError) {
  sqlight.exec(sql, connection) |> result.replace_error(StoreFailed)
}
