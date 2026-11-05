import gleam/dynamic/decode
import gleam/int
import gleam/list
import gleam/result
import sqlight

/// Must stay under `data/`, the volume docker-compose.yml mounts, or the
/// database is lost on redeploy.
pub const path = "data/app.db"

const schema_v1 = "
pragma journal_mode = wal;
pragma foreign_keys = on;

create table if not exists demand (
  id           text primary key,
  label        text not null,
  client       text not null,
  started_on   text not null,
  due_on       text not null,
  pieces_asked integer not null,
  state        text not null default 'active'
);

create table if not exists piece (
  id          text primary key,
  demand_id   text not null references demand(id),
  reference   text not null,
  state       text not null,
  produced_at text
);

create table if not exists flow_event (
  id        integer primary key autoincrement,
  at        text not null default (strftime('%Y-%m-%dT%H:%M:%SZ', 'now')),
  kind      text not null,
  piece_id  text references piece(id),
  payload   text
);
"

const schema_v2 = "
create table if not exists person (
  id   text primary key,
  name text not null
);

create table if not exists work_station (
  id          text primary key,
  name        text not null,
  position    integer not null,
  branch      text,
  blue_bins   integer not null,
  team_leader text references person(id)
);

create table if not exists station_person (
  station_id text not null references work_station(id),
  person_id  text not null references person(id),
  primary key (station_id, person_id)
);

create table if not exists blue_bin (
  id         text primary key,
  station_id text not null references work_station(id),
  slot       integer not null,
  piece_id   text references piece(id)
);

create table if not exists kanban (
  id         text primary key,
  station_id text not null references work_station(id),
  created_at text not null default (strftime('%Y-%m-%dT%H:%M:%SZ', 'now'))
);

create table if not exists rework (
  id          text primary key,
  piece_id    text not null references piece(id),
  station_id  text not null references work_station(id),
  description text not null,
  opened_at   text not null default (strftime('%Y-%m-%dT%H:%M:%SZ', 'now')),
  closed_at   text
);

alter table piece add column station_id text references work_station(id);
alter table piece add column assignee text references person(id);
"

const schema_v4 = "
alter table piece add column since text;

update piece
   set state = 'in_bin',
       station_id = (select b.station_id from blue_bin b where b.piece_id = piece.id),
       since = strftime('%Y-%m-%dT%H:%M:%SZ', 'now')
 where id in (select piece_id from blue_bin where piece_id is not null);

drop table blue_bin;

create table if not exists deviation (
  id         integer primary key autoincrement,
  at         text not null default (strftime('%Y-%m-%dT%H:%M:%SZ', 'now')),
  rule       text not null,
  station_id text not null references work_station(id),
  piece_id   text references piece(id),
  reason     text not null
);
"

/// Pieces already in a Branch were whole, which the pull rules no longer
/// allow, so the demo data is emptied for `seed` to refill. `stream_step` is
/// kept so renamed steps survive.
const schema_v5 = "
alter table piece add column parent_id text references piece(id);
alter table piece add column branch text;

delete from deviation;
delete from rework;
delete from kanban;
delete from flow_event;
delete from station_person;
delete from piece;
delete from demand;
delete from work_station;
delete from person;
"

const schema_v6 = "
alter table rework add column raised_by text references work_station(id);
alter table rework add column assignee text references person(id);
alter table rework add column started_at text;
alter table rework add column paused_piece text references piece(id);

create table if not exists piece_pass (
  piece_id   text not null references piece(id),
  station_id text not null references work_station(id),
  person_id  text references person(id),
  at         text not null default (strftime('%Y-%m-%dT%H:%M:%SZ', 'now')),
  primary key (piece_id, station_id)
);
"

/// Runs both as migration 6 and after the seed, so it must stay idempotent
/// (`insert or ignore`, `coalesce`).
const seed_passes_sql = "
insert or ignore into piece_pass (piece_id, station_id, person_id, at)
select p.id, w.id,
       (select sp.person_id from station_person sp
         where sp.station_id = w.id order by sp.rowid limit 1),
       p.produced_at
  from piece p, work_station w
 where p.state = 'produced' and p.produced_at is not null;

insert or ignore into piece_pass (piece_id, station_id, person_id, at)
select p.id, w.id,
       (select sp.person_id from station_person sp
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
         (select pp.person_id from piece_pass pp
           where pp.station_id = rework.station_id
             and pp.piece_id = rework.piece_id)),
       started_at = coalesce(started_at, opened_at)
 where closed_at is null;
"

const schema_v3 = "
create table if not exists stream_step (
  position   integer primary key,
  name       text not null,
  renamed_at text
);
"

const seed_steps_sql = "
insert into stream_step (position, name)
select w.position,
       case when w.position = (select min(position) from work_station)
            then 'From the Backlog'
            else 'Step ' || w.position end
from work_station w
group by w.position;
"

const seed_demands_sql = "
insert into demand (id, label, client, started_on, due_on, pieces_asked, state) values
  ('d-checkout', 'Checkout redesign', 'Retail',    date('now', '-10 day'), date('now', '+11 day'), 12, 'active'),
  ('d-offline',  'Offline mode',      'Field Ops', date('now', '-15 day'), date('now', '+5 day'),  10, 'active'),
  ('d-billing',  'Billing export',    'Finance',   date('now', '-3 day'),  date('now', '+25 day'),  8, 'active');

with recursive n(i) as (select 1 union all select i + 1 from n where i < 12)
insert into piece (id, demand_id, reference, state, produced_at)
select 'p-checkout-' || i, 'd-checkout', 'US-' || i,
  case when i <= 7 then 'produced' when i <= 9 then 'in_flow' else 'backlog' end,
  case when i <= 7 then strftime('%Y-%m-%dT%H:%M:%SZ', 'now', '-' || (8 - i) || ' day') end
from n;

with recursive n(i) as (select 1 union all select i + 1 from n where i < 10)
insert into piece (id, demand_id, reference, state, produced_at)
select 'p-offline-' || i, 'd-offline', 'US-' || i,
  case when i <= 3 then 'produced' when i <= 5 then 'in_flow' else 'backlog' end,
  case when i <= 3 then strftime('%Y-%m-%dT%H:%M:%SZ', 'now', '-' || (12 - 3 * i) || ' day') end
from n;

with recursive n(i) as (select 1 union all select i + 1 from n where i < 8)
insert into piece (id, demand_id, reference, state, produced_at)
select 'p-billing-' || i, 'd-billing', 'US-' || i,
  case when i = 1 then 'produced' when i = 2 then 'in_flow' else 'backlog' end,
  case when i = 1 then strftime('%Y-%m-%dT%H:%M:%SZ', 'now', '-1 day') end
from n;

insert into flow_event (at, kind, piece_id, payload)
select produced_at, 'piece_reached_production', id, null
from piece where state = 'produced' order by produced_at;
"

const seed_value_stream_sql = "
insert into person (id, name) values
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

insert into station_person (station_id, person_id) values
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

-- QA iOS found a defect in the iOS part of US-4; the Rework is against the
-- Work Station that made it.
insert into rework (id, piece_id, station_id, description, opened_at)
values ('rw-1', 'p-offline-4-ios', 'ws-ios',
        'Sync retries lose the last edit when the tunnel drops',
        strftime('%Y-%m-%dT%H:%M:%SZ', 'now', '-3 hour'));
"

pub fn with_connection(run: fn(sqlight.Connection) -> a) -> a {
  with_connection_at(path, run)
}

pub fn with_connection_at(
  database: String,
  run: fn(sqlight.Connection) -> a,
) -> a {
  sqlight.with_connection(database, run)
}

pub fn prepare(connection: sqlight.Connection) -> Result(Nil, sqlight.Error) {
  use _ <- result.try(migrate(connection))
  seed(connection)
}

/// Each step runs at most once per database, tracked in `pragma user_version`:
/// never edit an applied step, append a new one and raise this target.
pub fn migrate(connection: sqlight.Connection) -> Result(Nil, sqlight.Error) {
  migrate_to(connection, 6)
}

pub fn migrate_to(
  connection: sqlight.Connection,
  target: Int,
) -> Result(Nil, sqlight.Error) {
  use version <- result.try(user_version(connection))
  [
    #(1, schema_v1),
    #(2, schema_v2),
    #(3, schema_v3),
    #(4, schema_v4),
    #(5, schema_v5),
    #(6, schema_v6 <> seed_passes_sql),
  ]
  |> list.try_fold(Nil, fn(_, step) {
    let #(step_version, sql) = step
    case version < step_version && step_version <= target {
      False -> Ok(Nil)
      True ->
        sqlight.exec(
          sql
            <> "\npragma user_version = "
            <> int.to_string(step_version)
            <> ";",
          connection,
        )
    }
  })
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

pub fn seed(connection: sqlight.Connection) -> Result(Nil, sqlight.Error) {
  use _ <- result.try(seed_when_empty(connection, "demand", seed_demands_sql))
  use _ <- result.try(seed_when_empty(
    connection,
    "work_station",
    seed_value_stream_sql <> seed_passes_sql,
  ))
  seed_when_empty(connection, "stream_step", seed_steps_sql)
}

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
