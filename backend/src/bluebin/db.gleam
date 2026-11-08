import gleam/dynamic/decode
import gleam/function
import gleam/int
import gleam/list
import gleam/result
import gleam/string
import simplifile
import sqlight

/// Each workspace has its own SQLite file in this directory, so no query can
/// read the data of another workspace. Must stay under `data/`, the mounted
/// volume, or the data is lost on redeploy.
pub const workspaces_directory = "data/workspaces"

/// The schema of a new database. Raise `schema_version` when it changes: a
/// database of another version is refused, never migrated.
const schema_version = 2

/// Parents before children. `foreign_keys` holds only on the connection that
/// runs this schema and the seed, and only outside a transaction: `ready`
/// runs it inside one, where SQLite ignores the pragma, and request
/// connections leave it off. So foreign keys are not enforced at runtime.
const schema =
  "
pragma foreign_keys = on;

create table demand (
  id           text primary key,
  label        text not null,
  client       text not null,
  started_on   text not null,
  due_on       text not null,
  pieces_asked integer not null,
  state        text not null default 'active'
);

create table team_member (
  id         text primary key,
  name       text not null,
  removed_at text
);

create table work_station (
  id          text primary key,
  name        text not null,
  position    integer not null,
  branch      text,
  blue_bins   integer not null,
  team_leader text references team_member(id)
);

create table station_team_member (
  station_id     text not null references work_station(id),
  team_member_id text not null references team_member(id),
  primary key (station_id, team_member_id)
);

create table piece (
  id          text primary key,
  demand_id   text not null references demand(id),
  reference   text not null,
  state       text not null,
  deployed_at text,
  released_at text,
  station_id  text references work_station(id),
  assignee    text references team_member(id),
  since       text,
  parent_id   text references piece(id),
  branch      text,
  urgent      integer,
  entered_at  text
);

create table flow_event (
  id       integer primary key autoincrement,
  at       text not null default (strftime('%Y-%m-%dT%H:%M:%SZ', 'now')),
  kind     text not null,
  piece_id text references piece(id),
  payload  text
);

create table kanban (
  id         text primary key,
  station_id text not null references work_station(id),
  created_at text not null default (strftime('%Y-%m-%dT%H:%M:%SZ', 'now'))
);

create table rework (
  id           text primary key,
  piece_id     text not null references piece(id),
  station_id   text not null references work_station(id),
  description  text not null,
  opened_at    text not null default (strftime('%Y-%m-%dT%H:%M:%SZ', 'now')),
  closed_at    text,
  raised_by    text references work_station(id),
  assignee     text references team_member(id),
  started_at   text,
  paused_piece text references piece(id)
);

create table deviation (
  id         integer primary key autoincrement,
  at         text not null default (strftime('%Y-%m-%dT%H:%M:%SZ', 'now')),
  rule       text not null,
  station_id text not null references work_station(id),
  piece_id   text references piece(id),
  reason     text not null
);

create table piece_pass (
  piece_id       text not null references piece(id),
  station_id     text not null references work_station(id),
  team_member_id text references team_member(id),
  at             text not null default (strftime('%Y-%m-%dT%H:%M:%SZ', 'now')),
  primary key (piece_id, station_id)
);

create table andon (
  id         integer primary key autoincrement,
  station_id text not null references work_station(id),
  raised_by  text references team_member(id),
  raised_at  text not null default (strftime('%Y-%m-%dT%H:%M:%SZ', 'now')),
  closed_by  text references team_member(id),
  closed_at  text
);
-- One open Andon per Work Station.
create unique index andon_open on andon(station_id) where closed_at is null;

create table working_calendar (
  id        integer primary key check (id = 1),
  days      text not null,
  day_start text not null,
  day_end   text not null
);
insert into working_calendar (id, days, day_start, day_end)
values (1, '12345', '09:00', '16:00');

create table holiday (
  day   text primary key,
  label text not null
);

create table line_step (
  position   integer primary key,
  name       text not null,
  renamed_at text
);

-- The Line's name and the names it gives its Demands and Pieces (F41).
create table line_label (
  id      integer primary key check (id = 1),
  name    text not null default 'Line',
  demand  text not null,
  demands text not null,
  piece   text not null,
  pieces  text not null
);
insert into line_label (id, demand, demands, piece, pieces)
values (1, 'Feature', 'Features', 'User Story', 'User Stories');
"

/// The Pieces already past a Work Station get a pass, after the seed.
const seed_passes_sql =
  "
insert or ignore into piece_pass (piece_id, station_id, team_member_id, at)
select p.id, w.id,
       (select sp.team_member_id from station_team_member sp
         where sp.station_id = w.id order by sp.rowid limit 1),
       p.deployed_at
  from piece p, work_station w
 where p.state = 'deployed' and p.deployed_at is not null;

insert or ignore into piece_pass (piece_id, station_id, team_member_id, at)
select p.id, w.id,
       (select sp.team_member_id from station_team_member sp
         where sp.station_id = w.id order by sp.rowid limit 1),
       p.since
  from piece p
  join work_station here on here.id = p.station_id
  join work_station w on w.branch is p.branch and w.position < here.position
 where p.station_id is not null;

update rework
   set raised_by = coalesce(raised_by,
         (select p.station_id from piece p where p.id = rework.piece_id)),
       assignee = coalesce(assignee,
         (select pp.team_member_id from piece_pass pp
           where pp.station_id = rework.station_id
             and pp.piece_id = rework.piece_id)),
       started_at = coalesce(started_at, opened_at)
 where closed_at is null;
"

const seed_steps_sql =
  "
insert into line_step (position, name)
select w.position,
       case when w.position = (select min(position) from work_station)
            then 'From the Backlog'
            else 'Step ' || w.position end
from work_station w
group by w.position;
"

const seed_demands_sql =
  "
insert into demand (id, label, client, started_on, due_on, pieces_asked, state) values
  ('d-checkout', 'Checkout redesign', 'Retail',    date('now', '-10 day'), date('now', '+11 day'), 12, 'active'),
  ('d-offline',  'Offline mode',      'Field Ops', date('now', '-15 day'), date('now', '+5 day'),  10, 'active'),
  ('d-billing',  'Billing export',    'Finance',   date('now', '-3 day'),  date('now', '+25 day'),  8, 'active');

with recursive n(i) as (select 1 union all select i + 1 from n where i < 12)
insert into piece (id, demand_id, reference, state, deployed_at)
select 'p-checkout-' || i, 'd-checkout', 'US-' || i,
  case when i <= 7 then 'deployed' when i <= 9 then 'in_flow' else 'backlog' end,
  case when i <= 7 then strftime('%Y-%m-%dT%H:%M:%SZ', 'now', '-' || (8 - i) || ' day') end
from n;

with recursive n(i) as (select 1 union all select i + 1 from n where i < 10)
insert into piece (id, demand_id, reference, state, deployed_at)
select 'p-offline-' || i, 'd-offline', 'US-' || i,
  case when i <= 3 then 'deployed' when i <= 5 then 'in_flow' else 'backlog' end,
  case when i <= 3 then strftime('%Y-%m-%dT%H:%M:%SZ', 'now', '-' || (12 - 3 * i) || ' day') end
from n;

with recursive n(i) as (select 1 union all select i + 1 from n where i < 8)
insert into piece (id, demand_id, reference, state, deployed_at)
select 'p-billing-' || i, 'd-billing', 'US-' || i,
  case when i = 1 then 'deployed' when i = 2 then 'in_flow' else 'backlog' end,
  case when i = 1 then strftime('%Y-%m-%dT%H:%M:%SZ', 'now', '-1 day') end
from n;

update piece set released_at = deployed_at where state = 'deployed';

insert into flow_event (at, kind, piece_id, payload)
select at, kind, id, null
from (select deployed_at as at, 'piece_deployed' as kind, id, 0 as step
        from piece where state = 'deployed'
      union all
      select released_at, 'piece_released', id, 1
        from piece where state = 'deployed')
order by at, step;
"

const seed_line_sql =
  "
insert into team_member (id, name) values
  ('pe-ines', 'Inès'), ('pe-marc', 'Marc'), ('pe-sofia', 'Sofia'),
  ('pe-bob', 'Bob'), ('pe-lila', 'Lila'), ('pe-alice', 'Alice'),
  ('pe-karim', 'Karim'), ('pe-nina', 'Nina'), ('pe-tom', 'Tom'),
  ('pe-yasmine', 'Yasmine');

insert into work_station (id, name, position, branch, blue_bins, team_leader) values
  ('ws-analysis',    'Analysis',         1, null,      2, 'pe-ines'),
  ('ws-conception',  'Tech Conception',  2, null,      2, 'pe-sofia'),
  ('ws-web',         'Web',              3, 'Web',     2, 'pe-bob'),
  ('ws-ios',         'iOS',              3, 'iOS',     2, 'pe-alice'),
  ('ws-android',     'Android',          3, 'Android', 2, 'pe-nina'),
  ('ws-qa-web',      'QA Web',           4, 'Web',     2, 'pe-tom'),
  ('ws-qa-ios',      'QA iOS',           4, 'iOS',     2, 'pe-yasmine'),
  ('ws-qa-android',  'QA Android',       4, 'Android', 2, 'pe-tom'),
  ('ws-uat',         'UAT',              5, null,      1, 'pe-ines');

insert into station_team_member (station_id, team_member_id) values
  ('ws-analysis', 'pe-ines'), ('ws-analysis', 'pe-marc'),
  ('ws-conception', 'pe-sofia'), ('ws-conception', 'pe-marc'),
  ('ws-web', 'pe-bob'), ('ws-web', 'pe-lila'),
  ('ws-ios', 'pe-alice'), ('ws-ios', 'pe-karim'),
  ('ws-android', 'pe-nina'),
  ('ws-qa-web', 'pe-tom'),
  ('ws-qa-ios', 'pe-yasmine'),
  ('ws-qa-android', 'pe-tom'),
  ('ws-uat', 'pe-ines'), ('ws-uat', 'pe-sofia');

-- Analysis transforms a whole Piece: the trunk carries Pieces whole.
update piece set station_id = 'ws-analysis', assignee = 'pe-marc',
                 since = strftime('%Y-%m-%dT%H:%M:%SZ', 'now', '-1 hour')
 where id = 'p-billing-2';

-- US-9 waits in Tech Conception's Blue Bin; no Branch has pulled its part yet.
update piece set state = 'in_bin', station_id = 'ws-conception',
                 since = strftime('%Y-%m-%dT%H:%M:%SZ', 'now', '-4 hour')
 where id = 'p-checkout-9';
update piece set state = 'backlog' where id = 'p-offline-5';

-- Past the Split a Piece flows as one Sub-Piece per Branch. The Piece itself
-- left the trunk once all three Branches pulled their part.
update piece set state = 'split', station_id = null,
                 since = strftime('%Y-%m-%dT%H:%M:%SZ', 'now', '-1 day')
 where id in ('p-checkout-8', 'p-offline-4');

insert into piece (id, demand_id, reference, state, station_id, assignee,
                   since, parent_id, branch) values
  ('p-checkout-8-web', 'd-checkout', 'US-8 · Web', 'in_flow', 'ws-web', 'pe-bob',
   strftime('%Y-%m-%dT%H:%M:%SZ', 'now', '-6 hour'), 'p-checkout-8', 'Web'),
  ('p-checkout-8-ios', 'd-checkout', 'US-8 · iOS', 'in_bin', 'ws-ios', null,
   strftime('%Y-%m-%dT%H:%M:%SZ', 'now', '-2 hour'), 'p-checkout-8', 'iOS'),
  ('p-checkout-8-android', 'd-checkout', 'US-8 · Android', 'in_flow', 'ws-android', 'pe-nina',
   strftime('%Y-%m-%dT%H:%M:%SZ', 'now', '-5 hour'), 'p-checkout-8', 'Android'),
  ('p-offline-4-web', 'd-offline', 'US-4 · Web', 'in_bin', 'ws-qa-web', null,
   strftime('%Y-%m-%dT%H:%M:%SZ', 'now', '-3 hour'), 'p-offline-4', 'Web'),
  ('p-offline-4-ios', 'd-offline', 'US-4 · iOS', 'in_flow', 'ws-qa-ios', 'pe-yasmine',
   strftime('%Y-%m-%dT%H:%M:%SZ', 'now', '-3 hour'), 'p-offline-4', 'iOS'),
  ('p-offline-4-android', 'd-offline', 'US-4 · Android', 'in_bin', 'ws-qa-android', null,
   strftime('%Y-%m-%dT%H:%M:%SZ', 'now', '-2 hour'), 'p-offline-4', 'Android');

-- A Work Station never holds more Kanbans than it has Blue Bins left once its
-- Pieces in hand and in its Blue Bins are counted.
insert into kanban (id, station_id) values
  ('kb-analysis-1', 'ws-analysis'),
  ('kb-conception-1', 'ws-conception'),
  ('kb-web-1', 'ws-web'),
  ('kb-ios-1', 'ws-ios'),
  ('kb-android-1', 'ws-android'),
  ('kb-qa-web-1', 'ws-qa-web'),
  ('kb-uat-1', 'ws-uat');

-- Each Piece in the flow left the Backlog on a pull of Analysis, so the
-- Product Mix has history.
insert into flow_event (at, kind, piece_id, payload)
select strftime('%Y-%m-%dT%H:%M:%SZ', since, '-1 day'),
       'piece_pulled', id, '{\"station\":\"ws-analysis\",\"from\":null}'
  from piece
 where parent_id is null and state not in ('backlog', 'deployed')
 order by 1;

-- Each deployed Piece crossed the whole Line: the trunk, one Sub-Piece
-- per Branch, the Assembly and UAT. Hours count back from its Deployment and
-- stretch a little from one Piece to the next, so the measures vary.
insert into piece (id, demand_id, reference, state, parent_id, branch)
select p.id || '-' || lower(b.branch), p.demand_id,
       p.reference || ' · ' || b.branch, 'assembled', p.id, b.branch
  from piece p,
       (select 'Web' as branch union all select 'iOS' union all select 'Android') b
 where p.state = 'deployed';

with
  step(hours, kind, station, from_station) as (values
    (78, 'piece_pulled', 'ws-analysis', null),
    (74, 'piece_put_in_blue_bin', 'ws-analysis', null),
    (70, 'piece_pulled', 'ws-conception', 'ws-analysis'),
    (66, 'piece_put_in_blue_bin', 'ws-conception', null),
    (46, 'piece_split', 'ws-conception', null),
    (22, 'piece_assembled', 'ws-uat', null),
    (20, 'piece_put_in_blue_bin', 'ws-uat', null)),
  branch_step(branch, hours, kind, station, from_station) as (values
    ('Web', 64, 'piece_pulled', 'ws-web', 'ws-conception'),
    ('Web', 52, 'piece_put_in_blue_bin', 'ws-web', null),
    ('Web', 44, 'piece_pulled', 'ws-qa-web', 'ws-web'),
    ('Web', 38, 'piece_put_in_blue_bin', 'ws-qa-web', null),
    ('iOS', 60, 'piece_pulled', 'ws-ios', 'ws-conception'),
    ('iOS', 45, 'piece_put_in_blue_bin', 'ws-ios', null),
    ('iOS', 34, 'piece_pulled', 'ws-qa-ios', 'ws-ios'),
    ('iOS', 28, 'piece_put_in_blue_bin', 'ws-qa-ios', null),
    ('Android', 46, 'piece_pulled', 'ws-android', 'ws-conception'),
    ('Android', 36, 'piece_put_in_blue_bin', 'ws-android', null),
    ('Android', 31, 'piece_pulled', 'ws-qa-android', 'ws-android'),
    ('Android', 25, 'piece_put_in_blue_bin', 'ws-qa-android', null)),
  history(at_hours, kind, piece_id, station, from_station, deployed_at) as (
    select s.hours * (1 + (p.rowid % 3) * 0.3), s.kind, p.id, s.station,
           s.from_station, p.deployed_at
      from piece p, step s
     where p.state = 'deployed'
    union all
    select s.hours * (1 + (p.rowid % 3) * 0.3), s.kind, sub.id, s.station,
           s.from_station, p.deployed_at
      from piece p
      join piece sub on sub.parent_id = p.id
      join branch_step s on s.branch = sub.branch
     where p.state = 'deployed')
insert into flow_event (at, kind, piece_id, payload)
select strftime('%Y-%m-%dT%H:%M:%SZ', deployed_at, '-' || at_hours || ' hours'),
       kind, piece_id,
       case when kind = 'piece_pulled'
            then json_object('station', station, 'from', from_station)
            else json_object('station', station) end
  from history
 order by 1;

-- A Piece entered the Backlog when its Demand started, or at its first event
-- if that came earlier.
update piece
   set entered_at = min(
         (select d.started_on || 'T00:00:00Z' from demand d where d.id = piece.demand_id),
         coalesce((select min(e.at) from flow_event e where e.piece_id = piece.id),
                  '9999'))
 where parent_id is null;

insert into flow_event (at, kind, payload)
select created_at, 'kanban_sent', json_object('station', station_id)
  from kanban;

-- QA iOS found a defect in the iOS part of US-4; the Rework is against the
-- Work Station that made it.
insert into rework (id, piece_id, station_id, description, opened_at)
values ('rw-1', 'p-offline-4-ios', 'ws-ios',
        'Sync retries lose the last edit when the tunnel drops',
        strftime('%Y-%m-%dT%H:%M:%SZ', 'now', '-3 hour'));
"

/// `workspace` must be a checked identity (see `bluebin/workspace`): it
/// becomes part of a file path.
pub fn workspace_path(workspace: String) -> String {
  workspaces_directory <> "/" <> workspace <> ".db"
}

/// What a new Line holds: the demo data, only in the Public Workspace, or one
/// Work Station and one Team Member to rename in Design.
pub type Start {
  Demo
  Empty
}

/// Makes the database from `start` when it is new. The SPA sends several
/// requests at once on its first load, so the slow path holds the write lock:
/// the other requests wait, then see the current version.
pub fn ready(database: String, start: Start) -> Result(Nil, sqlight.Error) {
  open(database, start, function.identity, fn(_) { Ok(Nil) })
}

/// `ready`, then `run` on the same connection. A store failure of `ready`
/// goes through `on_store_error`.
pub fn open(
  database: String,
  start: Start,
  on_store_error store_error: fn(sqlight.Error) -> e,
  run run: fn(sqlight.Connection) -> Result(a, e),
) -> Result(a, e) {
  // The data can be wiped while the server runs: SQLite makes the file, not
  // its directory.
  let _ = simplifile.create_directory_all(directory_of(database))
  use connection <- with_connection_at(database)
  use version <- result.try(
    user_version(connection) |> result.map_error(store_error),
  )
  use _ <- result.try(
    case version == schema_version {
      True -> Ok(Nil)
      False ->
        transaction(connection, function.identity, fn() {
          prepare(connection, start)
        })
    }
    |> result.map_error(store_error),
  )
  run(connection)
}

pub fn directory_of(path: String) -> String {
  case string.split(path, "/") |> list.reverse {
    [_, _, ..] as parts ->
      parts |> list.drop(1) |> list.reverse |> string.join("/")
    _ -> "."
  }
}

pub fn with_connection_at(
  database: String,
  run: fn(sqlight.Connection) -> a,
) -> a {
  use connection <- sqlight.with_connection(database)
  // During a rolling deploy the old and the new container write to the same
  // file for a few seconds: wait for the lock instead of failing with BUSY.
  let _ = sqlight.exec("pragma busy_timeout = 5000;", connection)
  // Outside any transaction, where SQLite ignores it. Switching a new file
  // fails with BUSY when another connection does it at the same moment, and
  // skips the busy wait: one of them succeeds, the next connections see WAL.
  let _ = sqlight.exec("pragma journal_mode = wal;", connection)
  run(connection)
}

/// Makes the schema and the `start` data on a new database, and does nothing
/// on a current one. A database of another schema version is refused, not read.
pub fn prepare(
  connection: sqlight.Connection,
  start: Start,
) -> Result(Nil, sqlight.Error) {
  use version <- result.try(user_version(connection))
  case version {
    0 -> {
      use _ <- result.try(sqlight.exec(
        schema
          <> "\npragma user_version = "
          <> int.to_string(schema_version)
          <> ";",
        connection,
      ))
      case start {
        Demo -> seed(connection)
        Empty -> sqlight.exec(start_empty_sql, connection)
      }
    }
    _ if version == schema_version -> Ok(Nil)
    _ ->
      Error(sqlight.SqlightError(
        code: sqlight.GenericError,
        message: "schema version "
          <> int.to_string(version)
          <> ", expected "
          <> int.to_string(schema_version),
        offset: -1,
      ))
  }
}

fn user_version(connection: sqlight.Connection) -> Result(Int, sqlight.Error) {
  let decoder = {
    use version <- decode.field(0, decode.int)
    decode.success(version)
  }
  use rows <- result.try(sqlight.query(
    "pragma user_version",
    on: connection,
    with: [],
    expecting: decoder,
  ))
  case rows {
    [version, ..] -> Ok(version)
    [] -> Ok(0)
  }
}

fn seed(connection: sqlight.Connection) -> Result(Nil, sqlight.Error) {
  use _ <- result.try(seed_when_empty(connection, "demand", seed_demands_sql))
  use _ <- result.try(seed_when_empty(
    connection,
    "work_station",
    seed_line_sql <> seed_passes_sql,
  ))
  seed_when_empty(connection, "line_step", seed_steps_sql)
}

pub fn reset(connection: sqlight.Connection) -> Result(Nil, sqlight.Error) {
  use <- transaction(connection, function.identity)
  use _ <- result.try(sqlight.exec(
    empty_sql <> default_calendar_and_labels_sql,
    connection,
  ))
  seed(connection)
}

/// Starts a Line from scratch: no Demand, Piece or history, one Team Member
/// in one Work Station. The Working Calendar and the labels stay.
pub fn reset_empty(
  connection: sqlight.Connection,
) -> Result(Nil, sqlight.Error) {
  use <- transaction(connection, function.identity)
  sqlight.exec(empty_sql <> start_empty_sql, connection)
}

/// Runs `run` in one write transaction: commits on Ok, rolls back on Error.
/// `begin immediate` takes the write lock at once, so a busy database waits
/// at the start instead of failing at the first write. A failed begin or
/// commit goes through `on_store_error`.
pub fn transaction(
  connection: sqlight.Connection,
  on_store_error store_error: fn(sqlight.Error) -> e,
  run run: fn() -> Result(a, e),
) -> Result(a, e) {
  use _ <- result.try(
    sqlight.exec("begin immediate;", connection)
    |> result.map_error(store_error),
  )
  case run() {
    Ok(value) ->
      case sqlight.exec("commit;", connection) {
        Ok(Nil) -> Ok(value)
        Error(error) -> {
          let _ = sqlight.exec("rollback;", connection)
          Error(store_error(error))
        }
      }
    Error(failure) -> {
      let _ = sqlight.exec("rollback;", connection)
      Error(failure)
    }
  }
}

/// The current time, in seconds since the Unix epoch, from SQLite's clock.
pub fn now(connection: sqlight.Connection) -> Result(Int, sqlight.Error) {
  sqlight.query(
    "select cast(strftime('%s', 'now') as integer)",
    on: connection,
    with: [],
    expecting: decode.at([0], decode.int),
  )
  |> result.map(fn(rows) { list.first(rows) |> result.unwrap(0) })
}

/// Children before parents, so it also runs where `foreign_keys` is on.
const empty_sql =
  "
delete from andon;
delete from deviation;
delete from rework;
delete from kanban;
delete from piece_pass;
delete from flow_event;
delete from station_team_member;
delete from piece;
delete from demand;
delete from work_station;
delete from team_member;
delete from line_step;
delete from sqlite_sequence;
"

const default_calendar_and_labels_sql =
  "
delete from holiday;
update working_calendar set days = '12345', day_start = '09:00', day_end = '16:00';
update line_label
   set demand = 'Feature', demands = 'Features',
       piece = 'User Story', pieces = 'User Stories';
"

/// The one Blue Bin is empty, so the Work Station holds its one Kanban.
const start_empty_sql =
  "
insert into team_member (id, name)
values ('pe-' || lower(hex(randomblob(6))), 'Team Member 1');

insert into work_station (id, name, position, branch, blue_bins, team_leader)
select 'ws-' || lower(hex(randomblob(6))), 'Work Station 1', 1, null, 1, id
  from team_member;

insert into station_team_member (station_id, team_member_id)
select w.id, p.id from work_station w, team_member p;

insert into kanban (id, station_id)
select 'kb-' || lower(hex(randomblob(6))), id from work_station;

insert into flow_event (at, kind, payload)
select created_at, 'kanban_sent', json_object('station', station_id) from kanban;

insert into line_step (position, name) values (1, 'From the Backlog');
"

fn seed_when_empty(
  connection: sqlight.Connection,
  table: String,
  sql: String,
) -> Result(Nil, sqlight.Error) {
  let count_decoder = {
    use count <- decode.field(0, decode.int)
    decode.success(count)
  }
  use rows <- result.try(sqlight.query(
    "select count(*) from " <> table,
    on: connection,
    with: [],
    expecting: count_decoder,
  ))
  case rows {
    [0] -> sqlight.exec(sql, connection)
    _ -> Ok(Nil)
  }
}
