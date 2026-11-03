import gleam/dynamic/decode
import gleam/int
import gleam/list
import gleam/result
import sqlight

/// Path of the SQLite file. The Coolify volume mounts `data/` (see
/// docker-compose.yml), so the file survives redeploys.
pub const path = "data/app.db"

/// Flow event log plus the current-state tables, per ADR-0002.
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

/// The Value Stream itself: Work Stations in order, their Blue Bins, their
/// People, their Kanbans and the open Rework.
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

/// One Value Stream's worth of Demands and Pieces, so a fresh instance shows
/// real numbers instead of an empty screen.
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

/// The software team's Value Stream: a trunk, a Split into three Branches, and
/// an Assembly at UAT. Every Work Station has two Blue Bins except UAT.
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

insert into blue_bin (id, station_id, slot, piece_id)
select w.id || '-bin-' || s.slot, w.id, s.slot, null
from work_station w
join (select 1 as slot union all select 2) s on s.slot <= w.blue_bins;

-- Pieces being transformed right now, each by one Person of that Work Station.
update piece set station_id = 'ws-web',    assignee = 'pe-bob'     where id = 'p-checkout-8';
update piece set station_id = 'ws-qa-ios', assignee = 'pe-yasmine' where id = 'p-offline-4';
update piece set station_id = 'ws-analysis', assignee = 'pe-marc'  where id = 'p-billing-2';

-- Pieces finished and waiting in a Blue Bin for the downstream pull.
update blue_bin set piece_id = 'p-checkout-9' where id = 'ws-conception-bin-1';
update blue_bin set piece_id = 'p-offline-5'  where id = 'ws-ios-bin-1';

-- A Kanban is never more than the empty Blue Bins of its Work Station.
insert into kanban (id, station_id) values
  ('kb-analysis-1', 'ws-analysis'),
  ('kb-conception-1', 'ws-conception'),
  ('kb-web-1', 'ws-web'),
  ('kb-android-1', 'ws-android'),
  ('kb-android-2', 'ws-android'),
  ('kb-qa-web-1', 'ws-qa-web'),
  ('kb-uat-1', 'ws-uat');

-- QA iOS found a defect; the Rework is against the Work Station that made it.
insert into rework (id, piece_id, station_id, description)
values ('rw-1', 'p-offline-4', 'ws-ios', 'Sync retries lose the last edit when the tunnel drops');
"

pub fn with_connection(run: fn(sqlight.Connection) -> a) -> a {
  with_connection_at(path, run)
}

/// Open any database file. Tests pass `":memory:"` to get a fresh, throwaway
/// database that still exercises the real schema and the real queries.
pub fn with_connection_at(
  database: String,
  run: fn(sqlight.Connection) -> a,
) -> a {
  sqlight.with_connection(database, run)
}

/// Migrate and seed one connection — what boot does, and what a test needs
/// before it can query anything.
pub fn prepare(connection: sqlight.Connection) -> Result(Nil, sqlight.Error) {
  use _ <- result.try(migrate(connection))
  seed(connection)
}

/// Apply the schema steps the database has not seen yet, tracked in
/// `pragma user_version`. Every step runs at most once, in order.
pub fn migrate(connection: sqlight.Connection) -> Result(Nil, sqlight.Error) {
  use version <- result.try(user_version(connection))
  [#(1, schema_v1), #(2, schema_v2)]
  |> list.try_fold(Nil, fn(_, step) {
    let #(step_version, sql) = step
    case version < step_version {
      False -> Ok(Nil)
      True ->
        sqlight.exec(
          sql <> "\npragma user_version = " <> int.to_string(step_version) <> ";",
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

/// Seed only what is still empty, so a running instance is never overwritten.
pub fn seed(connection: sqlight.Connection) -> Result(Nil, sqlight.Error) {
  use _ <- result.try(seed_when_empty(connection, "demand", seed_demands_sql))
  seed_when_empty(connection, "work_station", seed_value_stream_sql)
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
