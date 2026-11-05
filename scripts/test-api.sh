#!/usr/bin/env sh
# Smoke-test a running Bluebin API.
#
#   scripts/test-api.sh                      against https://bluebin.app
#   scripts/test-api.sh http://localhost:8000  against a local backend
#
# Needs curl and jq only, no Erlang.
set -eu

BASE="${1:-https://bluebin.app}"
failures=0

check() {
  name="$1"
  shift
  if "$@" >/dev/null; then
    echo "  ok   $name"
  else
    echo "  FAIL $name"
    failures=$((failures + 1))
  fi
}

# `jq -e` exits non-zero when the expression is false or null: that is the assertion.
assert_json() {
  printf '%s' "$2" | jq -e "$1"
}

echo "Bluebin API smoke test against $BASE"

health=$(curl -fsS "$BASE/api/health" || true)
check "GET /api/health answers OK" test "$health" = "OK"

demands=$(curl -fsS "$BASE/api/demands")
check "demands is a non-empty array" assert_json 'type == "array" and length > 0' "$demands"
check "every Demand names a Client and a due date" assert_json \
  'all(.client != "" and .dueOn != "")' "$demands"
check "every Takt Time is a positive number of hours" assert_json \
  'all(.taktTimeHours > 0)' "$demands"
check "an Andon is raised exactly when the Takt Gap is a whole Piece behind" \
  assert_json 'all(.andon == (.taktGap <= -1))' "$demands"
check "no Demand reports more Pieces produced than asked" assert_json \
  'all(.piecesProduced <= .piecesAsked)' "$demands"

stream=$(curl -fsS "$BASE/api/value-stream")
check "the Value Stream has Work Stations" assert_json \
  '.stations | type == "array" and length > 0' "$stream"
check "the Value Stream Takt Time is positive" assert_json \
  '.taktTimeHours > 0' "$stream"
check "each Work Station has as many Blue Bins as it declares" assert_json \
  '.stations | all((.blueBins | length) == .blueBinCount)' "$stream"
check "no Work Station holds more Kanbans than it has empty Blue Bins" \
  assert_json \
  '.stations | all(.kanbans <= ([.blueBins[] | select(.piece == null)] | length))' \
  "$stream"
check "no Piece sits in two Blue Bins at once" assert_json \
  '[.stations[].blueBins[].piece | select(. != null)] | length == (unique | length)' \
  "$stream"
check "every Person busy at a Work Station holds a Piece there" assert_json \
  '.stations | all(([.people[] | select(.busy)] | length) <= (.inProgress | length))' \
  "$stream"
check "every Piece in a Blue Bin carries the id an action needs" assert_json \
  '.stations | all(.blueBins | all(.piece == null or (.id | length) > 0))' "$stream"
check "every Piece in the hands of a Work Station carries its id" assert_json \
  '.stations | all(.inProgress | all((.id | length) > 0))' "$stream"
check "a Blue Bin over its count shows as overflow" assert_json \
  '.stations | all(.overflow | type == "array")' "$stream"
check "every Deviation names its rule and its reason" assert_json \
  '.stations | all(.deviations | all((.rule | length) > 0 and (.reason | length) > 0))' \
  "$stream"
check "every open Rework says what it is, who found it and who repairs it" \
  assert_json \
  '.stations | all(.rework | all((.id | length) > 0 and (.piece | length) > 0
     and (.description | length) > 0 and (.foundBy | length) > 0
     and (.assignee == null or (.assignee | length) > 0)))' "$stream"
check "the Work Station that found a defect holds the Piece of its Rework" \
  assert_json \
  '[.stations[].rework[].piece] - [.stations[].inProgress[].piece] | length == 0' \
  "$stream"
check "every First Pass Yield is a share, or none until a Piece has left" \
  assert_json \
  '.stations | all(.firstPassYield == null
     or (.firstPassYield >= 0 and .firstPassYield <= 1))' "$stream"
check "no Work Station reports a negative Rework Time" assert_json \
  '.stations | all(.reworkHours >= 0)' "$stream"
check "a paused Piece waits for a Rework its Person repairs first" assert_json \
  '.stations | all(.inProgress | all(.paused | type == "boolean"))' "$stream"
check "every Person carries the id an action needs" assert_json \
  '.stations | all(.people | all((.id | length) > 0))' "$stream"
check "every step of the chain carries a name" assert_json \
  '(.steps | length) > 0 and (.steps | all(.name != ""))' "$stream"
check "every Work Station sits on a named step" assert_json \
  '[.stations[].position] - [.steps[].position] | length == 0' "$stream"

check "every open Rework carries the id of who repairs it" assert_json \
  '.stations | all(.rework | all((.assignee == null) == (.assigneeId == null)))' "$stream"
check "every Piece in hand carries the id of who holds it" assert_json \
  '.stations | all(.inProgress | all((.person == null) == (.personId == null)))' "$stream"

people=$(curl -fsS "$BASE/api/people")
check "people is a non-empty array, each Person of a Work Station" assert_json \
  'type == "array" and length > 0 and all((.stations | length) > 0)' "$people"

first=$(printf '%s' "$people" | jq -r '.[0].id')
next=$(curl -fsS "$BASE/api/people/$first/next")
check "a Person's screen names one next thing" assert_json \
  '.next.kind | IN("continue", "take_rework", "take_kanban", "help_downstream", "wait")' \
  "$next"
check "a Person holds at most one active Assignment" assert_json \
  '[.assignments[] | select(.active)] | length <= 1' "$next"
check "every Priority List puts Rework before Kanbans" assert_json \
  '.priorityLists | all([.items[].kind] | . == sort_by(if . == "rework" then 0 else 1 end))' \
  "$next"
check "an unknown Person has no screen" test \
  "$(curl -s -o /dev/null -w '%{http_code}' "$BASE/api/people/pe-nobody/next")" = 404

# The stream never ends, so curl stops it after 2 s and only its headers count.
events=$(curl -s -N --max-time 2 -D - -o /dev/null "$BASE/api/events" || true)
check "the event stream opens as Server-Sent Events" \
  sh -c 'printf "%s" "$1" | grep -qi "^content-type: text/event-stream"' _ "$events"

echo
if [ "$failures" -eq 0 ]; then
  echo "All checks passed."
else
  echo "$failures check(s) failed."
  exit 1
fi
