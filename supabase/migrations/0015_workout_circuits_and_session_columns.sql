-- The remote half of local schema v33 and v34, which shipped without it.
--
-- Two independent regressions, same root cause as the one 0013 already warned
-- about: `SyncService._buildRemotePayload` does `SELECT *` on the local row and
-- forwards every column that is not a registered FK / localOnly / dateTime
-- column, and `syncTableSpecs` is what decides a table is synced at all.
-- Adding either a local column or a local synced table without its Postgres
-- counterpart breaks the push for that whole table.
--
-- 1. v33 added `workout_sessions.photo_path` and `.calories_burned`
--    (`database.dart` `if (from < 33)`). Neither is in that table's
--    `localOnlyColumns` (only `session_uuid` is), so a v33 client sends both
--    in *every* `workout_sessions` upsert — including the null ones. Against a
--    project without this migration PostgREST answers PGRST204 (unknown
--    column), `_pushOne` records the failure, retries with backoff, and
--    quarantines the op after `maxPushAttempts = 8`. Every finished workout
--    stops reaching the cloud, silently.
--
-- 2. v34 added the `workout_circuits` / `circuit_exercises` tables AND
--    registered both in `sync_table_specs.dart`. The remote tables do not
--    exist at all, so those pushes fail with 42P01 the same way.
--
-- ORDERING: apply this BEFORE any build carrying local schema v33 reaches a
-- user, for exactly the reason 0013 spells out. Anything already quarantined
-- from the two regressions above needs the outbox retried after this lands.
--
-- Both circuit tables are post-hoc synced tables, so their RLS / trigger /
-- tombstone / realtime wiring is spelled out directly here rather than folded
-- into the 0003-0005 loops, which already ran — same shape as 0009, 0011 and
-- 0014.

-- ── v33: two nullable columns on an already-synced table ──────────────────
-- No RLS/trigger/tombstone/publication work needed: `workout_sessions` has all
-- of it from 0002-0005. Same shape as 0010 and 0013.

alter table workout_sessions add column photo_path text;
alter table workout_sessions add column calories_burned integer;

-- ── v34: circuits ─────────────────────────────────────────────────────────

create table workout_circuits (
  id uuid primary key,
  user_id uuid not null references auth.users(id) on delete cascade,
  name text not null,
  notes text,
  rounds integer not null default 3,
  rest_seconds integer not null default 90,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  deleted_at timestamptz
);

-- `exercise_id` is a CatalogueFk locally (`_exerciseFk('exercise_id')`), which
-- resolves to a uuid for user-created catalogue rows and to a slug for seeded
-- ones — the same split every other exercise-referencing table uses (0002:
-- exercise_progressions, machine_settings, workout_exercises). The check
-- constraint enforces exactly one of the two, matching those tables.
create table circuit_exercises (
  id uuid primary key,
  user_id uuid not null references auth.users(id) on delete cascade,
  circuit_id uuid references workout_circuits(id) on delete cascade,
  exercise_catalog_id uuid references exercise_catalog(id) on delete cascade,
  exercise_slug text,
  order_index integer not null,
  target_reps integer,
  target_weight_kg double precision,
  updated_at timestamptz not null default now(),
  deleted_at timestamptz,
  check (
    (exercise_catalog_id is not null and exercise_slug is null) or
    (exercise_catalog_id is null and exercise_slug is not null)
  )
);

alter table workout_circuits enable row level security;
alter table circuit_exercises enable row level security;

create policy workout_circuits_select_own
  on workout_circuits for select using (user_id = auth.uid());
create policy workout_circuits_insert_own
  on workout_circuits for insert with check (user_id = auth.uid());
create policy workout_circuits_update_own
  on workout_circuits for update using (user_id = auth.uid()) with check (user_id = auth.uid());
create policy workout_circuits_delete_own
  on workout_circuits for delete using (user_id = auth.uid());

create policy circuit_exercises_select_own
  on circuit_exercises for select using (user_id = auth.uid());
create policy circuit_exercises_insert_own
  on circuit_exercises for insert with check (user_id = auth.uid());
create policy circuit_exercises_update_own
  on circuit_exercises for update using (user_id = auth.uid()) with check (user_id = auth.uid());
create policy circuit_exercises_delete_own
  on circuit_exercises for delete using (user_id = auth.uid());

-- Reuses the two trigger functions 0004/0005 already defined.
create trigger t_set_updated_at_workout_circuits
  before insert or update on workout_circuits
  for each row execute function set_updated_at();

create trigger t_set_updated_at_circuit_exercises
  before insert or update on circuit_exercises
  for each row execute function set_updated_at();

create trigger t_record_tombstone_workout_circuits
  after delete on workout_circuits
  for each row execute function public.record_sync_tombstone();

create trigger t_record_tombstone_circuit_exercises
  after delete on circuit_exercises
  for each row execute function public.record_sync_tombstone();

alter publication supabase_realtime add table public.workout_circuits;
alter publication supabase_realtime add table public.circuit_exercises;
