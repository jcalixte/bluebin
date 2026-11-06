import bluebin/live
import gleam/erlang/process

pub fn every_open_stream_hears_each_change_test() {
  let assert Ok(hub) = live.start()
  let wall = process.new_subject()
  let desk = process.new_subject()
  live.subscribe(hub, "acme", wall)
  live.subscribe(hub, "acme", desk)

  live.announce(hub, "acme", "pull")
  live.announce(hub, "acme", "rework/repair")

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
      live.subscribe(hub, "acme", stream)
      process.send(gone, Nil)
    })
  let assert Ok(Nil) = process.receive(gone, 1000)
  process.sleep(20)
  assert !process.is_alive(closed)

  let desk = process.new_subject()
  live.subscribe(hub, "acme", desk)
  live.announce(hub, "acme", "finish")
  let assert Ok(signal) = process.receive(desk, 1000)
  assert live.changed_action(signal) == Ok("finish")
}

pub fn a_change_stays_in_its_workspace_test() {
  let assert Ok(hub) = live.start()
  let ours = process.new_subject()
  let theirs = process.new_subject()
  live.subscribe(hub, "acme", ours)
  live.subscribe(hub, "globex", theirs)

  live.announce(hub, "acme", "pull")

  let assert Ok(signal) = process.receive(ours, 1000)
  assert live.changed_action(signal) == Ok("pull")
  assert process.receive(theirs, 100) == Error(Nil)
}
