import bluebin/flow
import gleam/dynamic/decode
import gleam/int
import gleam/json.{type Json}
import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/order
import gleam/result
import gleam/string
import sqlight

pub type Item {
  ReworkItem(
    id: String,
    piece: String,
    description: String,
    assignee: Option(String),
  )
  KanbanItem(id: String, since: String)
}

pub type Member {
  Member(id: String, name: String)
}

pub type PriorityList {
  PriorityList(
    station_id: String,
    station: String,
    people: List(Member),
    items: List(Item),
  )
}

pub type Assignment {
  Repair(
    id: String,
    piece: String,
    station_id: String,
    station: String,
    active: Bool,
    found_by: String,
    description: String,
  )
  Transform(
    id: String,
    piece: String,
    station_id: String,
    station: String,
    active: Bool,
  )
}

pub type Next {
  Continue(Assignment)
  TakeRework(id: String, piece: String, station_id: String, station: String)
  TakeKanban(station_id: String, station: String)
  HelpDownstream(station_id: String, station: String, because: String)
  Wait
}

pub type View {
  View(
    person_id: String,
    name: String,
    next: Next,
    assignments: List(Assignment),
    lists: List(PriorityList),
  )
}

pub type ReadError {
  UnknownPerson
  ReadFailed
}

pub type Person {
  Person(id: String, name: String, stations: List(String))
}

pub fn people(
  connection: sqlight.Connection,
) -> Result(List(Person), sqlight.Error) {
  let decoder = {
    use id <- decode.field(0, decode.string)
    use name <- decode.field(1, decode.string)
    use station <- decode.field(2, decode.string)
    decode.success(#(id, name, station))
  }
  use rows <- result.try(sqlight.query(
    "select pe.id, pe.name, w.name
       from person pe
       join station_person sp on sp.person_id = pe.id
       join work_station w on w.id = sp.station_id
      order by pe.name, pe.id, w.position desc, w.branch",
    on: connection,
    with: [],
    expecting: decoder,
  ))
  rows
  |> list.chunk(fn(row) { row.0 })
  |> list.filter_map(fn(rows) {
    case rows {
      [#(id, name, _), ..] ->
        Ok(Person(id:, name:, stations: list.map(rows, fn(row) { row.2 })))
      [] -> Error(Nil)
    }
  })
  |> Ok
}

pub fn people_json(people: List(Person)) -> Json {
  json.array(people, fn(person) {
    json.object([
      #("id", json.string(person.id)),
      #("name", json.string(person.name)),
      #("stations", json.array(person.stations, json.string)),
    ])
  })
}

pub fn load(
  connection: sqlight.Connection,
  person_id: String,
) -> Result(View, ReadError) {
  use name <- result.try(person_name(connection, person_id))
  use stations <- result.try(stations(connection) |> read)
  let mine =
    stations
    |> list.filter(fn(one) { list.contains(one.people, person_id) })
    |> list.sort(fn(a, b) { nearest_first(a, b) })
  use assignments <- result.try(assignments(connection, person_id) |> read)
  use lists <- result.try(
    list.try_map(mine, fn(station) {
      use items <- result.try(priority_list(connection, station.id))
      use people <- result.try(members(connection, station.id))
      Ok(PriorityList(
        station_id: station.id,
        station: station.name,
        people:,
        items:,
      ))
    })
    |> read,
  )
  use next <- result.try(next_thing(
    connection,
    assignments,
    lists,
    mine,
    stations,
  ))
  Ok(View(person_id:, name:, next:, assignments:, lists:))
}

fn next_thing(
  connection: sqlight.Connection,
  assignments: List(Assignment),
  lists: List(PriorityList),
  mine: List(Station),
  stations: List(Station),
) -> Result(Next, ReadError) {
  let active = list.find(assignments, fn(one) { one.active })
  let free_rework =
    list.find_map(lists, fn(one) {
      list.find_map(one.items, fn(item) {
        case item {
          ReworkItem(id:, piece:, assignee: None, ..) ->
            Ok(TakeRework(
              id:,
              piece:,
              station_id: one.station_id,
              station: one.station,
            ))
          _ -> Error(Nil)
        }
      })
    })
  case active, free_rework {
    Ok(assignment), _ -> Ok(Continue(assignment))
    Error(_), Ok(take) -> Ok(take)
    Error(_), Error(_) -> {
      use kanban <- result.try(first_kanban_to_take(connection, lists))
      case kanban {
        Some(take) -> Ok(take)
        None ->
          Ok(
            help_downstream(mine, stations)
            |> option.unwrap(Wait),
          )
      }
    }
  }
}

fn first_kanban_to_take(
  connection: sqlight.Connection,
  lists: List(PriorityList),
) -> Result(Option(Next), ReadError) {
  case lists {
    [] -> Ok(None)
    [one, ..rest] -> {
      let has_kanban =
        list.any(one.items, fn(item) {
          case item {
            KanbanItem(..) -> True
            ReworkItem(..) -> False
          }
        })
      use takeable <- result.try(case has_kanban {
        False -> Ok(False)
        True ->
          flow.can_pull(connection, one.station_id)
          |> result.replace_error(ReadFailed)
      })
      case takeable {
        True ->
          Ok(Some(TakeKanban(station_id: one.station_id, station: one.station)))
        False -> first_kanban_to_take(connection, rest)
      }
    }
  }
}

pub type Station {
  Station(
    id: String,
    name: String,
    position: Int,
    branch: Option(String),
    people: List(String),
    free_bins: Int,
    stopped: Bool,
  )
}

pub fn help_downstream(
  mine: List(Station),
  all: List(Station),
) -> Option(Next) {
  all
  |> list.filter(fn(other) {
    !list.contains(mine, other)
    && list.any(mine, fn(own) { downstream_of(other, own) })
  })
  |> list.filter_map(fn(other) {
    case other.stopped, in_front_full(other, all) {
      True, _ -> Ok(#(other, "it found a defect and waits for its Rework"))
      False, True -> Ok(#(other, "the Blue Bins in front of it are full"))
      False, False -> Error(Nil)
    }
  })
  |> list.sort(fn(a, b) { nearest_upstream_first(a.0, b.0) })
  |> list.first
  |> option.from_result
  |> option.map(fn(found) {
    HelpDownstream(
      station_id: { found.0 }.id,
      station: { found.0 }.name,
      because: found.1,
    )
  })
}

fn downstream_of(other: Station, own: Station) -> Bool {
  other.position > own.position && same_chain(other, own)
}

fn same_chain(one: Station, other: Station) -> Bool {
  case one.branch, other.branch {
    Some(a), Some(b) -> a == b
    _, _ -> True
  }
}

/// The Blue Bins of the step just upstream are all full.
pub fn in_front_full(station: Station, all: List(Station)) -> Bool {
  let upstream =
    list.filter(all, fn(other) {
      other.position < station.position && same_chain(other, station)
    })
  let previous =
    list.fold(upstream, -1, fn(highest, other) {
      case other.position > highest {
        True -> other.position
        False -> highest
      }
    })
  list.any(upstream, fn(other) {
    other.position == previous && other.free_bins <= 0
  })
}

fn nearest_first(a: Station, b: Station) -> order.Order {
  int.compare(b.position, a.position)
  |> order.break_tie(string.compare(
    option.unwrap(a.branch, ""),
    option.unwrap(b.branch, ""),
  ))
}

fn nearest_upstream_first(a: Station, b: Station) -> order.Order {
  int.compare(a.position, b.position)
  |> order.break_tie(string.compare(
    option.unwrap(a.branch, ""),
    option.unwrap(b.branch, ""),
  ))
}

fn read(found: Result(a, sqlight.Error)) -> Result(a, ReadError) {
  result.replace_error(found, ReadFailed)
}

fn person_name(
  connection: sqlight.Connection,
  person_id: String,
) -> Result(String, ReadError) {
  let found =
    sqlight.query(
      "select name from person where id = ?1",
      on: connection,
      with: [sqlight.text(person_id)],
      expecting: decode.at([0], decode.string),
    )
  case found {
    Ok([name, ..]) -> Ok(name)
    Ok([]) -> Error(UnknownPerson)
    Error(_) -> Error(ReadFailed)
  }
}

pub fn stations(
  connection: sqlight.Connection,
) -> Result(List(Station), sqlight.Error) {
  let decoder = {
    use id <- decode.field(0, decode.string)
    use name <- decode.field(1, decode.string)
    use position <- decode.field(2, decode.int)
    use branch <- decode.field(3, decode.optional(decode.string))
    use people <- decode.field(4, decode.optional(decode.string))
    use free_bins <- decode.field(5, decode.int)
    use stopped <- decode.field(6, decode.int)
    decode.success(Station(
      id:,
      name:,
      position:,
      branch:,
      people: people |> option.map(string.split(_, ",")) |> option.unwrap([]),
      free_bins:,
      stopped: stopped > 0,
    ))
  }
  sqlight.query(
    "select w.id, w.name, w.position, w.branch,
            (select group_concat(sp.person_id) from station_person sp
              where sp.station_id = w.id),
            w.blue_bins - (select count(*) from piece p
                            where p.station_id = w.id and p.state = 'in_bin'),
            (select count(*) from rework r
              where r.raised_by = w.id and r.closed_at is null)
       from work_station w
      order by w.position, w.branch",
    on: connection,
    with: [],
    expecting: decoder,
  )
}

pub fn priority_list(
  connection: sqlight.Connection,
  station_id: String,
) -> Result(List(Item), sqlight.Error) {
  let rework_decoder = {
    use id <- decode.field(0, decode.string)
    use piece <- decode.field(1, decode.string)
    use description <- decode.field(2, decode.string)
    use assignee <- decode.field(3, decode.optional(decode.string))
    decode.success(ReworkItem(id:, piece:, description:, assignee:))
  }
  use reworks <- result.try(sqlight.query(
    "select r.id, p.reference, r.description,
            (select pe.name from person pe where pe.id = r.assignee)
       from rework r
       join piece p on p.id = r.piece_id
      where r.station_id = ?1 and r.closed_at is null
      order by r.opened_at, r.rowid",
    on: connection,
    with: [sqlight.text(station_id)],
    expecting: rework_decoder,
  ))
  let kanban_decoder = {
    use id <- decode.field(0, decode.string)
    use since <- decode.field(1, decode.string)
    decode.success(KanbanItem(id:, since:))
  }
  use kanbans <- result.try(sqlight.query(
    "select id, created_at from kanban where station_id = ?1
      order by created_at, rowid",
    on: connection,
    with: [sqlight.text(station_id)],
    expecting: kanban_decoder,
  ))
  Ok(list.append(reworks, kanbans))
}

fn members(
  connection: sqlight.Connection,
  station_id: String,
) -> Result(List(Member), sqlight.Error) {
  let decoder = {
    use id <- decode.field(0, decode.string)
    use name <- decode.field(1, decode.string)
    decode.success(Member(id:, name:))
  }
  sqlight.query(
    "select pe.id, pe.name from station_person sp
       join person pe on pe.id = sp.person_id
      where sp.station_id = ?1
      order by pe.name",
    on: connection,
    with: [sqlight.text(station_id)],
    expecting: decoder,
  )
}

fn assignments(
  connection: sqlight.Connection,
  person_id: String,
) -> Result(List(Assignment), sqlight.Error) {
  let repair_decoder = {
    use id <- decode.field(0, decode.string)
    use piece <- decode.field(1, decode.string)
    use station_id <- decode.field(2, decode.string)
    use station <- decode.field(3, decode.string)
    use found_by <- decode.field(4, decode.string)
    use description <- decode.field(5, decode.string)
    use started <- decode.field(6, decode.int)
    decode.success(Repair(
      id:,
      piece:,
      station_id:,
      station:,
      found_by:,
      description:,
      active: started > 0,
    ))
  }
  use repairs <- result.try(sqlight.query(
    "select r.id, p.reference, w.id, w.name,
            coalesce((select f.name from work_station f where f.id = r.raised_by),
                     'downstream'),
            r.description, r.started_at is not null
       from rework r
       join piece p on p.id = r.piece_id
       join work_station w on w.id = r.station_id
      where r.assignee = ?1 and r.closed_at is null
      order by r.started_at is null, r.started_at, r.opened_at, r.rowid",
    on: connection,
    with: [sqlight.text(person_id)],
    expecting: repair_decoder,
  ))
  let transform_decoder = {
    use id <- decode.field(0, decode.string)
    use piece <- decode.field(1, decode.string)
    use station_id <- decode.field(2, decode.string)
    use station <- decode.field(3, decode.string)
    use in_flow <- decode.field(4, decode.int)
    decode.success(Transform(
      id:,
      piece:,
      station_id:,
      station:,
      active: in_flow > 0,
    ))
  }
  use pieces <- result.try(sqlight.query(
    "select p.id, p.reference, w.id, w.name, p.state = 'in_flow'
       from piece p
       join work_station w on w.id = p.station_id
      where p.assignee = ?1 and p.state in ('in_flow', 'paused')
      order by p.state = 'in_flow' desc, w.position desc, p.since, p.rowid",
    on: connection,
    with: [sqlight.text(person_id)],
    expecting: transform_decoder,
  ))
  // Only one Rework runs at a time; the ones after it wait.
  let repairs =
    list.index_map(repairs, fn(one, index) {
      case one {
        Repair(..) -> Repair(..one, active: one.active && index == 0)
        Transform(..) -> one
      }
    })
  Ok(list.append(repairs, pieces))
}

/// `andons` are those of the Person's Work Stations (DESIGN.md R2).
pub fn to_json(view: View, andons: Json) -> Json {
  json.object([
    #("andons", andons),
    #(
      "person",
      json.object([
        #("id", json.string(view.person_id)),
        #("name", json.string(view.name)),
      ]),
    ),
    #("next", next_json(view.next)),
    #("assignments", json.array(view.assignments, assignment_json)),
    #(
      "priorityLists",
      json.array(view.lists, fn(one) {
        json.object([
          #("station", json.string(one.station_id)),
          #("name", json.string(one.station)),
          #(
            "people",
            json.array(one.people, fn(member) {
              json.object([
                #("id", json.string(member.id)),
                #("name", json.string(member.name)),
              ])
            }),
          ),
          #("items", json.array(one.items, item_json)),
        ])
      }),
    ),
  ])
}

fn next_json(next: Next) -> Json {
  case next {
    Continue(assignment) ->
      json.object([
        #("kind", json.string("continue")),
        #("assignment", assignment_json(assignment)),
      ])
    TakeRework(id:, piece:, station_id:, station:) ->
      json.object([
        #("kind", json.string("take_rework")),
        #("rework", json.string(id)),
        #("piece", json.string(piece)),
        #("station", json.string(station_id)),
        #("stationName", json.string(station)),
      ])
    TakeKanban(station_id:, station:) ->
      json.object([
        #("kind", json.string("take_kanban")),
        #("station", json.string(station_id)),
        #("stationName", json.string(station)),
      ])
    HelpDownstream(station_id:, station:, because:) ->
      json.object([
        #("kind", json.string("help_downstream")),
        #("station", json.string(station_id)),
        #("stationName", json.string(station)),
        #("because", json.string(because)),
      ])
    Wait -> json.object([#("kind", json.string("wait"))])
  }
}

fn assignment_json(assignment: Assignment) -> Json {
  case assignment {
    Repair(id:, piece:, station_id:, station:, found_by:, description:, active:) ->
      json.object([
        #("kind", json.string("rework")),
        #("id", json.string(id)),
        #("piece", json.string(piece)),
        #("station", json.string(station_id)),
        #("stationName", json.string(station)),
        #("foundBy", json.string(found_by)),
        #("description", json.string(description)),
        #("active", json.bool(active)),
      ])
    Transform(id:, piece:, station_id:, station:, active:) ->
      json.object([
        #("kind", json.string("piece")),
        #("id", json.string(id)),
        #("piece", json.string(piece)),
        #("station", json.string(station_id)),
        #("stationName", json.string(station)),
        #("active", json.bool(active)),
      ])
  }
}

fn item_json(item: Item) -> Json {
  case item {
    ReworkItem(id:, piece:, description:, assignee:) ->
      json.object([
        #("kind", json.string("rework")),
        #("id", json.string(id)),
        #("piece", json.string(piece)),
        #("description", json.string(description)),
        #("assignee", json.nullable(assignee, json.string)),
      ])
    KanbanItem(id:, since:) ->
      json.object([
        #("kind", json.string("kanban")),
        #("id", json.string(id)),
        #("since", json.string(since)),
      ])
  }
}
