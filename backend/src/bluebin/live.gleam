import gleam/erlang/process.{type Monitor, type Subject}
import gleam/http/request.{type Request}
import gleam/http/response.{type Response}
import gleam/json
import gleam/list
import gleam/otp/actor
import gleam/result
import gleam/string_tree
import mist

/// `Heartbeat` never leaves the stream itself.
pub opaque type Signal {
  Changed(action: String)
  Heartbeat
}

pub opaque type Message {
  Subscribe(workspace: String, stream: Subject(Signal))
  Announce(workspace: String, action: String)
  Tick
  StreamDown(Monitor)
}

type Stream {
  Stream(monitor: Monitor, workspace: String, subject: Subject(Signal))
}

pub type Hub =
  Subject(Message)

/// Proxies close a silent connection, and a dead socket only shows when a
/// write fails, so each stream sends a `ping` event this often.
const heartbeat_ms = 25_000

/// Time alone raises some Andons (a Rework that waits, a Takt Gap that grows),
/// so every minute the open screens reload as if the state changed
/// (DESIGN.md R6).
const tick_ms = 60_000

pub fn start() -> Result(Hub, actor.StartError) {
  actor.new_with_initialiser(1000, fn(subject) {
    let selector =
      process.new_selector()
      |> process.select(subject)
      |> process.select_monitors(fn(down) { StreamDown(down.monitor) })

    actor.initialised([])
    |> actor.selecting(selector)
    |> actor.returning(subject)
    |> Ok
  })
  |> actor.on_message(handle)
  |> actor.start
  |> result.map(fn(started) {
    process.spawn(fn() { tick(started.data) })
    started.data
  })
}

fn tick(hub: Hub) -> Nil {
  process.sleep(tick_ms)
  process.send(hub, Tick)
  tick(hub)
}

fn handle(
  streams: List(Stream),
  message: Message,
) -> actor.Next(List(Stream), Message) {
  case message {
    Subscribe(workspace, subject) ->
      case process.subject_owner(subject) {
        Ok(pid) ->
          actor.continue([
            Stream(process.monitor(pid), workspace, subject),
            ..streams
          ])
        Error(Nil) -> actor.continue(streams)
      }
    Announce(workspace, action) -> {
      list.each(streams, fn(one) {
        case one.workspace == workspace {
          True -> process.send(one.subject, Changed(action))
          False -> Nil
        }
      })
      actor.continue(streams)
    }
    Tick -> {
      list.each(streams, fn(one) { process.send(one.subject, Changed("tick")) })
      actor.continue(streams)
    }
    StreamDown(monitor) ->
      actor.continue(list.filter(streams, fn(one) { one.monitor != monitor }))
  }
}

pub fn subscribe(hub: Hub, workspace: String, stream: Subject(Signal)) -> Nil {
  process.send(hub, Subscribe(workspace, stream))
}

/// `action` names what changed the state, for example `pull` or
/// `rework/repair`.
pub fn announce(hub: Hub, workspace: String, action: String) -> Nil {
  process.send(hub, Announce(workspace, action))
}

pub fn changed_action(signal: Signal) -> Result(String, Nil) {
  case signal {
    Changed(action) -> Ok(action)
    Heartbeat -> Error(Nil)
  }
}

/// `GET /api/events`. A screen that reconnects reloads the current state, so
/// no event is replayed.
pub fn stream(
  request: Request(mist.Connection),
  hub: Hub,
  workspace: String,
) -> Response(mist.ResponseData) {
  mist.server_sent_events(
    request: request,
    initial_response: response.new(200),
    init: fn(self) {
      subscribe(hub, workspace, self)
      let _ = process.send_after(self, heartbeat_ms, Heartbeat)
      self
    },
    loop: fn(self, signal, connection) {
      let event = case signal {
        Changed(action) ->
          json.object([#("action", json.string(action))])
          |> json.to_string_tree
          |> mist.event
          |> mist.event_name("change")
        Heartbeat -> {
          let _ = process.send_after(self, heartbeat_ms, Heartbeat)
          mist.event(string_tree.new()) |> mist.event_name("ping")
        }
      }
      case mist.send_event(connection, event) {
        Ok(Nil) -> actor.continue(self)
        Error(Nil) -> actor.stop()
      }
    },
  )
}
