#!/usr/bin/env sh
# Smoke-test a running Bluebin API: the endpoints answer, the payloads carry
# the Takt numbers, and the pull rules of the glossary hold in the data.
#
#   scripts/test-api.sh                      against https://bluebin.app
#   scripts/test-api.sh http://localhost:8000  against a local backend
#
# Needs curl and jq only, so it runs anywhere, including where no Erlang is.
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

# `jq -e` exits non-zero when the expression is false or null, which is the
# assertion: every check below is one jq expression over a real payload.
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
check "every step of the chain carries a name" assert_json \
  '(.steps | length) > 0 and (.steps | all(.name != ""))' "$stream"
check "every Work Station sits on a named step" assert_json \
  '[.stations[].position] - [.steps[].position] | length == 0' "$stream"

echo
if [ "$failures" -eq 0 ]; then
  echo "All checks passed."
else
  echo "$failures check(s) failed."
  exit 1
fi
