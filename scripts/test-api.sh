#!/usr/bin/env sh
# Smoke-test a running Bluebin API.
#
#   scripts/test-api.sh                        against a local backend
#   scripts/test-api.sh http://localhost:8000  the same, explicit
#
# Each call acts as the workspace in $WORKSPACE (default "smoke"), the way
# Traefik forward auth sends the authentik user id when SSO is on.
#
# Needs curl and jq only, no Erlang.
set -eu

BASE="${1:-http://localhost:8000}"
WORKSPACE="${WORKSPACE:-smoke}"
failures=0

curl() {
  command curl -H "X-authentik-uid: $WORKSPACE" "$@"
}

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
check "a request without an identity uses the public workspace" test \
  "$(command curl -s -o /dev/null -w '%{http_code}' "$BASE/api/demands")" = 200
check "an identity that could leave the workspaces directory is refused" test \
  "$(command curl -s -o /dev/null -w '%{http_code}' -H 'X-authentik-uid: ../app' "$BASE/api/demands")" = 401

demands=$(curl -fsS "$BASE/api/demands")
check "demands is a non-empty array" assert_json 'type == "array" and length > 0' "$demands"
check "every Demand names a Client and a due date" assert_json \
  'all(.client != "" and .dueOn != "")' "$demands"
check "every Takt Time is a positive number of hours" assert_json \
  'all(.taktTimeHours > 0)' "$demands"
check "an Andon is raised exactly when the Takt Gap is a whole Piece behind" \
  assert_json 'all(.andon == (.taktGap <= -1))' "$demands"
check "no Demand reports more Pieces deployed than asked" assert_json \
  'all(.piecesDeployed <= .piecesAsked)' "$demands"

line=$(curl -fsS "$BASE/api/line")
check "the Value Stream has Work Stations" assert_json \
  '.stations | type == "array" and length > 0' "$line"
check "the Value Stream Takt Time is positive" assert_json \
  '.taktTimeHours > 0' "$line"
check "each Work Station has as many Blue Bins as it declares" assert_json \
  '.stations | all((.blueBins | length) == .blueBinCount)' "$line"
check "no Work Station holds more Kanbans than it has empty Blue Bins" \
  assert_json \
  '.stations | all(.kanbans <= ([.blueBins[] | select(.piece == null)] | length))' \
  "$line"
check "no Piece sits in two Blue Bins at once" assert_json \
  '[.stations[].blueBins[].piece | select(. != null)] | length == (unique | length)' \
  "$line"
check "every Team Member busy at a Work Station holds a Piece there" assert_json \
  '.stations | all(([.teamMembers[] | select(.busy)] | length) <= (.inProgress | length))' \
  "$line"
check "every Piece in a Blue Bin carries the id an action needs" assert_json \
  '.stations | all(.blueBins | all(.piece == null or (.id | length) > 0))' "$line"
check "every Piece in the hands of a Work Station carries its id" assert_json \
  '.stations | all(.inProgress | all((.id | length) > 0))' "$line"
check "a Blue Bin over its count shows as overflow" assert_json \
  '.stations | all(.overflow | type == "array")' "$line"
check "every Deviation names its rule and its reason" assert_json \
  '.stations | all(.deviations | all((.rule | length) > 0 and (.reason | length) > 0))' \
  "$line"
check "every open Rework says what it is, who found it and who repairs it" \
  assert_json \
  '.stations | all(.rework | all((.id | length) > 0 and (.piece | length) > 0
     and (.description | length) > 0 and (.foundBy | length) > 0
     and (.assignee == null or (.assignee | length) > 0)))' "$line"
check "the Work Station that found a defect holds the Piece of its Rework" \
  assert_json \
  '[.stations[].rework[].piece] - [.stations[].inProgress[].piece] | length == 0' \
  "$line"
check "every First Pass Yield is a share, or none until a Piece has left" \
  assert_json \
  '.stations | all(.firstPassYield == null
     or (.firstPassYield >= 0 and .firstPassYield <= 1))' "$line"
check "no Work Station reports a negative Rework Time" assert_json \
  '.stations | all(.reworkHours >= 0)' "$line"
check "a paused Piece waits for a Rework its Team Member repairs first" assert_json \
  '.stations | all(.inProgress | all(.paused | type == "boolean"))' "$line"
check "every Team Member carries the id an action needs" assert_json \
  '.stations | all(.teamMembers | all((.id | length) > 0))' "$line"
check "every step of the chain carries a name" assert_json \
  '(.steps | length) > 0 and (.steps | all(.name != ""))' "$line"
check "every Work Station sits on a named step" assert_json \
  '[.stations[].position] - [.steps[].position] | length == 0' "$line"

check "every open Rework carries the id of who repairs it" assert_json \
  '.stations | all(.rework | all((.assignee == null) == (.assigneeId == null)))' "$line"
check "every Piece in hand carries the id of who holds it" assert_json \
  '.stations | all(.inProgress | all((.teamMember == null) == (.teamMemberId == null)))' "$line"

team_members=$(curl -fsS "$BASE/api/team-members")
check "/api/team-members is a non-empty array, each Team Member of a Work Station" assert_json \
  'type == "array" and length > 0 and all((.stations | length) > 0)' "$team_members"

first=$(printf '%s' "$team_members" | jq -r '.[0].id')
next=$(curl -fsS "$BASE/api/team-members/$first/next")
check "a Team Member's screen names one next thing" assert_json \
  '.next.kind | IN("continue", "take_rework", "take_kanban", "help_downstream", "wait")' \
  "$next"
check "a Team Member holds at most one active Assignment" assert_json \
  '[.assignments[] | select(.active)] | length <= 1' "$next"
check "every Priority List puts Rework before Kanbans" assert_json \
  '.priorityLists | all([.items[].kind] | . == sort_by(if . == "rework" then 0 else 1 end))' \
  "$next"
check "an unknown Team Member has no screen" test \
  "$(curl -s -o /dev/null -w '%{http_code}' "$BASE/api/team-members/pe-nobody/next")" = 404

measures=$(curl -fsS "$BASE/api/measures")
check "measures name the period they cover" assert_json \
  '(.from | test("^[0-9]{4}-[0-9]{2}-[0-9]{2}$")) and .from <= .to' "$measures"
check "Lead Time = Touch Time + Stagnation Time, in both views" assert_json \
  '.pieces | .leadTime == null or (
     ((.leadTime.calendar - .touchTime.calendar - .stagnationTime.calendar) | fabs) <= 0.02
     and ((.leadTime.working - .touchTime.working - .stagnationTime.working) | fabs) <= 0.02)' \
  "$measures"
check "every Work Station has a Touch share between 0 and 1" assert_json \
  '.stations | all(.touchShare == null or (.touchShare >= 0 and .touchShare <= 1))' "$measures"
check "every Work Station has an Andon Time no longer than its Calendar Time" assert_json \
  '.stations | all(.andons >= 0 and .andonTime.working <= .andonTime.calendar)' "$measures"
check "the Value Stream Andon Time is no longer than the sum of its Work Stations" assert_json \
  '.andonTime.calendar <= ([.stations[].andonTime.calendar] | add) + 0.01' "$measures"
check "every Deviation of the period carries its reason" assert_json \
  '.deviations.list | all(.reason != "")' "$measures"
check "a period ending before it starts is refused" test \
  "$(curl -s -o /dev/null -w '%{http_code}' "$BASE/api/measures?from=2026-11-05&to=2026-11-01")" = 400

calendar=$(curl -fsS "$BASE/api/calendar")
check "the Working Calendar has working days and a day that ends after it starts" \
  assert_json '(.days | length) > 0 and .start < .end' "$calendar"

andons=$(curl -fsS "$BASE/api/andons")
check "every Andon is a stop or a Rework that waits, on a named Work Station" assert_json \
  'all((.kind == "stop" or .kind == "rework_waits") and .stationName != "")' "$andons"
check "a Rework raises an Andon only after an hour of Working Time" assert_json \
  'map(select(.kind == "rework_waits")) | all(.waitingHours >= 1)' "$andons"
check "the Value Stream shows the same Andons" assert_json \
  "(.andons | length) == $(printf '%s' "$andons" | jq length)" "$line"
check "stale Assignments are a part of the active ones" assert_json \
  '(.stale | length) <= .activeAssignments' "$line"
check "every bottleneck is slower than the Takt Time or has full Blue Bins in front" \
  assert_json '.bottlenecks | all(.slower or .fullInFront)' "$line"
check "closing an Andon nobody raised is refused" test \
  "$(curl -s -o /dev/null -w '%{http_code}' -H 'content-type: application/json' \
     -d '{"station": "ws-nowhere", "teamMember": "pe-nobody"}' "$BASE/api/andon/close")" = 404

backlog=$(curl -fsS "$BASE/api/backlog")
check "the Backlog lists its Heijunka Sequence" assert_json \
  '.sequence | type == "array"' "$backlog"
check "urgent Pieces lead the Heijunka Sequence" assert_json \
  '[.sequence[].urgent] | . == (sort | reverse)' "$backlog"
check "only Pieces not yet urgent can be made urgent" assert_json \
  '.sequence | all(if .urgent then .canBeUrgent == false else true end)' "$backlog"
check "the Product Mix has one row per active Demand" assert_json \
  "(.mix | length) == $(printf '%s' "$demands" | jq length)" "$backlog"
check "a Product Mix cell is on plan within one Piece" assert_json \
  '[.mix[].cells[]] | all(.onPlan == (((.real - .planned) | fabs) <= 1))' "$backlog"

design=$(curl -fsS "$BASE/api/design")
check "the design lists the steps of the Value Stream" assert_json \
  '.steps | length > 0 and all(.stations | length > 0)' "$design"
check "each Work Station of the design has its Team Leader among its Team Members" assert_json \
  '[.steps[].stations[]] | all(.teamLeader as $t | .teamMembers | index($t) != null)' "$design"
check "saving the same design answers 200" test \
  "$(curl -s -o /dev/null -w '%{http_code}' -X PUT -H 'content-type: application/json' \
    -d "$design" "$BASE/api/design")" = 200
check "a design without steps is refused" test \
  "$(curl -s -o /dev/null -w '%{http_code}' -X PUT -H 'content-type: application/json' \
    -d "$(printf '%s' "$design" | jq -c '.steps = []')" "$BASE/api/design")" = 400
labels=$(curl -fsS "$BASE/api/labels")
check "the labels name the Demands and the Pieces" assert_json \
  'all(.demand, .demands, .piece, .pieces; length > 0)' "$labels"

# The stream never ends, so curl stops it after 2 s and only its headers count.
events=$(curl -s -N --max-time 2 -D - -o /dev/null "$BASE/api/events" || true)
check "the event stream opens as Server-Sent Events" \
  sh -c 'printf "%s" "$1" | grep -qi "^content-type: text/event-stream"' _ "$events"

check "every forecast is a day with its late days, or none of both" assert_json \
  'all((.forecastOn == null) == (.forecastLateDays == null))' "$demands"

# The checks below change the data, so they come last and end on the demo data.
due=$(date -u -d '+30 day' +%Y-%m-%d)
created=$(curl -s -w '\n%{http_code}' -H 'content-type: application/json' \
  -d "{\"label\": \"Smoke\", \"client\": \"Smoke test\", \"dueOn\": \"$due\", \"pieces\": 2}" \
  "$BASE/api/demands")
check "a new Demand answers 201" test "$(printf '%s' "$created" | tail -n 1)" = 201
created_id=$(printf '%s' "$created" | head -n 1 | jq -r '.id')
check "a new Demand that asks for no Piece is refused" test \
  "$(curl -s -o /dev/null -w '%{http_code}' -H 'content-type: application/json' \
     -d "{\"label\": \"Smoke\", \"client\": \"Smoke test\", \"dueOn\": \"$due\", \"pieces\": 0}" \
     "$BASE/api/demands")" = 400
check "the new Demand waits in the Backlog" assert_json \
  "[.sequence[] | select(.demand == \"$created_id\")] | length == 2" \
  "$(curl -fsS "$BASE/api/backlog")"

check "an empty start answers 204" test \
  "$(curl -s -o /dev/null -w '%{http_code}' -X POST -H 'content-type: application/json' \
     -d '{"mode": "empty"}' "$BASE/api/reset")" = 204
check "an empty start has no Demand" assert_json 'length == 0' \
  "$(curl -fsS "$BASE/api/demands")"
check "an empty start has one Work Station holding one Kanban" assert_json \
  '.stations | length == 1 and .[0].kanbans == 1' \
  "$(curl -fsS "$BASE/api/line")"
check "a reset without a body puts back the demo data" test \
  "$(curl -s -o /dev/null -w '%{http_code}' -X POST "$BASE/api/reset")" = 204
check "the demo data has Demands again" assert_json 'length > 0' \
  "$(curl -fsS "$BASE/api/demands")"

echo
if [ "$failures" -eq 0 ]; then
  echo "All checks passed."
else
  echo "$failures check(s) failed."
  exit 1
fi
