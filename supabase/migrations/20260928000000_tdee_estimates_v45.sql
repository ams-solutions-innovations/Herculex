-- The remote half of local schema v45: the synced `tdee_estimates` table.
--
-- Adaptive TDEE (Phase 28) persists one estimate row per cadence run so the
-- estimate history survives reinstall and Phase 29 can diff it. Local drift
-- v45 registers `tdee_estimates` in `syncTableSpecs`, so every local row is
-- pushed. `SyncService._buildRemotePayload` does `SELECT *` on the local row
-- and forwards every column that is not a registered FK / localOnly / dateTime
-- column; a local column with no Postgres counterpart makes PostgREST answer
-- PGRST204 (unknown column), and the outbox quarantines the op after
-- `maxPushAttempts = 8`. It looks fine locally, which is what makes it worse.
-- The columns below are exactly the local drift columns snake_cased (drift
-- `TdeeEstimates` in lib/data/local/tables.dart), plus `user_id` which the
-- sync layer stamps at push time. `sync_uuid` maps to the remote `id` and
-- `synced_at` is local-only bookkeeping, so neither exists here (same as
-- 0014). test/tdee_supabase_migration_test.dart guards this parity.
--
-- ORDERING: apply this BEFORE any client carrying local schema v45 reaches a
-- user. `0015_workout_circuits_and_session_columns.sql` and
-- `0016_exercise_progression_double.sql` are recorded as still outstanding
-- (CLAUDE.md), so they must be applied first, and in that order, ahead of
-- this file. This file is WRITTEN, not applied; applying it is a human-gated
-- step (Phase 28 plan 11). Target project ref is `ldzgyzigvbwofbswitrv`
-- (Herculex). `jioesomepkauponjrena` is a different product: not this one.
--
-- Post-hoc synced table, so its RLS / trigger / tombstone / realtime wiring is
-- spelled out directly here rather than folded into the 0003-0005 loops,
-- which already ran. Same shape as 0009, 0011, 0014 and 0015.
--
-- `method` and `confidence` are deliberately unconstrained: later phases may
-- extend the vocabulary, and validation lives at the Dart repository boundary.
-- `inputs_json` is a display-only snapshot and is never used for control flow.

create table tdee_estimates (
  id uuid primary key,
  user_id uuid not null references auth.users(id) on delete cascade,
  date_iso text not null,
  estimated_at timestamptz not null default now(),
  method text not null,
  confidence text not null,
  window_days integer not null,
  kcal integer not null,
  observed_qualified boolean not null default false,
  inputs_json text not null,
  updated_at timestamptz not null default now(),
  deleted_at timestamptz
);

alter table tdee_estimates enable row level security;

create policy tdee_estimates_select_own
  on tdee_estimates for select using (user_id = auth.uid());
create policy tdee_estimates_insert_own
  on tdee_estimates for insert with check (user_id = auth.uid());
create policy tdee_estimates_update_own
  on tdee_estimates for update
  using (user_id = auth.uid())
  with check (user_id = auth.uid());
create policy tdee_estimates_delete_own
  on tdee_estimates for delete using (user_id = auth.uid());

-- Reuses the two trigger functions 0004/0005 already defined.
create trigger t_set_updated_at_tdee_estimates
  before insert or update on tdee_estimates
  for each row execute function set_updated_at();

create trigger t_record_tombstone_tdee_estimates
  after delete on tdee_estimates
  for each row execute function public.record_sync_tombstone();

alter publication supabase_realtime add table public.tdee_estimates;

-- 0017 added this composite index to every synced table that existed then.
-- `SupabaseSyncBackendService.pull()` filters
--   user_id = ? and updated_at > ? order by updated_at, id
-- and a table without it is a sequential scan on every pull.
create index if not exists tdee_estimates_user_updated_idx
  on public.tdee_estimates (user_id, updated_at, id);
