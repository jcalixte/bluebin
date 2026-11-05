import bluebin/live
import gleam/erlang/process

pub fn every_open_stream_hears_each_change_test() {
  let assert Ok(hub) = live.start()
  let wall = process.new_subject()
  let desk = process.new_subject()
  live.subscribe(hub, wall)
  live.subscribe(hub, desk)

  live.announce(hub, "pull")
  live.announce(hub, "rework/repair")

  let assert Ok(first) = process.receive(wall, 1000)
  let assert Ok(second) = process.receive(wall, 1000)
  assert live.changed_action(first) == Ok("pull")
  assert live.changed_action(second) == Ok("rework/repair")
  let assert Ok(other) = process.receive(desk, 1000)
  assert live.changed_action(other) == Ok("pull")
}

pub fn a_closed_stream_leaves_the_others_listening_test() {
  let assert Ok(hub) = live.start()
  let gone = process.new_subject()
  let closed =
    process.spawn(fn() {
      let stream = process.new_subject()
      live.subscribe(hub, stream)
      process.send(gone, Nil)
    })
  let assert Ok(Nil) = process.receive(gone, 1000)
  process.sleep(20)
  assert !process.is_alive(closed)

  let desk = process.new_subject()
  live.subscribe(hub, desk)
  live.announce(hub, "finish")
  let assert Ok(signal) = process.receive(desk, 1000)
  assert live.changed_action(signal) == Ok("finish")
}
