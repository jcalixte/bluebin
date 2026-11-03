import gleam/dynamic/decode
import gleam/result
import sqlight

/// Path of the SQLite file. The Coolify volume mounts `data/` (see
/// docker-compose.yml), so the file survives redeploys.
pub const path = "data/app.db"

/// Flow event log plus the current-state tables, per ADR-0002.
const schema = "
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

/// One Value Stream's worth of Demands and Pieces, so a fresh instance shows
/// real numbers instead of an empty screen.
const seed_sql = "
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

pub fn with_connection(run: fn(sqlight.Connection) -> a) -> a {
  sqlight.with_connection(path, run)
}

/// Create the schema if it is missing. Safe to run on every boot.
pub fn migrate(connection: sqlight.Connection) -> Result(Nil, sqlight.Error) {
  sqlight.exec(schema, connection)
}

/// Seed only when `demand` is empty, so a running instance is never overwritten.
pub fn seed(connection: sqlight.Connection) -> Result(Nil, sqlight.Error) {
  let count_decoder = {
    use count <- decode.field(0, decode.int)
    decode.success(count)
  }
  use rows <- result.try(sqlight.query(
    "select count(*) from demand",
    on: connection,
    with: [],
    expecting: count_decoder,
  ))
  case rows {
    [0] -> sqlight.exec(seed_sql, connection)
    _ -> Ok(Nil)
  }
}
