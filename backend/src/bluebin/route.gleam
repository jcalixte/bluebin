//// The route of a Piece: the Work Stations it skips. A Piece goes through
//// every Work Station by default; its route changes only in the Backlog.

import bluebin/shape
import gleam/dynamic/decode
import gleam/json
import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/result
import sqlight

pub type RouteError {
  Invalid(String)
  NotInBacklog
  StoreFailed
}

/// The route as stored, None for every Work Station, if the Line allows it.
pub fn check(
  connection: sqlight.Connection,
  skips: List(String),
) -> Result(Option(String), RouteError) {
  use stations <- result.try(
    sqlight.query(
      "select id, position, branch, parent_branch, name from work_station
        order by position, branch",
      on: connection,
      with: [],
      expecting: {
        use id <- decode.field(0, decode.string)
        use position <- decode.field(1, decode.int)
        use branch <- decode.field(2, decode.optional(decode.string))
        use parent <- decode.field(3, decode.optional(decode.string))
        use name <- decode.field(4, decode.string)
        decode.success(#(shape.Node(id:, position:, branch:, parent:), name))
      },
    )
    |> result.replace_error(StoreFailed),
  )
  let nodes = list.map(stations, fn(one) { one.0 })
  let names = list.map(stations, fn(one) { #({ one.0 }.id, one.1) })
  let name_of = fn(id) { list.key_find(names, id) |> result.unwrap(id) }
  case shape.check_route(nodes, skips) {
    Ok([]) -> Ok(None)
    Ok(skips) -> Ok(Some(json.to_string(json.array(skips, json.string))))
    Error(shape.UnknownStation(id)) ->
      Error(Invalid("The Line has no Work Station " <> id <> "."))
    Error(shape.SkipsEveryStation) ->
      Error(Invalid("A Piece goes through one Work Station at least."))
    Error(shape.SkipsAnAssembly(id)) ->
      Error(Invalid(
        name_of(id)
        <> " assembles the Branches this Piece goes through: it cannot be skipped.",
      ))
    Error(shape.Stranded(id)) ->
      Error(Invalid(
        name_of(id)
        <> " has no Work Station left to pull this Piece from: keep the Work Station before its Split.",
      ))
  }
}

/// Gives a Piece waiting in the Backlog a new route.
pub fn change(
  connection: sqlight.Connection,
  piece_id: String,
  skips: List(String),
) -> Result(Nil, RouteError) {
  use route <- result.try(check(connection, skips))
  use changed <- result.try(
    sqlight.query(
      "update piece set skips = ?2
        where id = ?1 and state = 'backlog' and parent_id is null
       returning id",
      on: connection,
      with: [sqlight.text(piece_id), sqlight.nullable(sqlight.text, route)],
      expecting: decode.at([0], decode.string),
    )
    |> result.replace_error(StoreFailed),
  )
  case changed {
    [] -> Error(NotInBacklog)
    _ -> Ok(Nil)
  }
}
