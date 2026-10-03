-- The remote half of local schema v48: the synced `weekly_reports` table
-- (Phase 29, weekly report with a Herculex AI narrative).
--
-- One row per ISO week holds the frozen measured payload (`payload_json`), the
-- write-once AI narrative (`narrative_json`) and the write-once TDEE decision
-- (`tdee_decision`). Local drift v48 registers `weekly_reports` in
-- `syncTableSpecs`, so every local row is pushed. `SyncService.
-- _buildRemotePayload` does `SELECT *` on the local row and forwards every
-- column that is not a registered FK / localOnly / dateTime column; a local
-- column with no Postgres counterpart makes PostgREST answer PGRST204 (unknown
-- column), and the outbox quarantines the op after `maxPushAttempts = 8`. It
-- looks fine locally, which is what makes it worse.
-- The columns below are exactly the local drift columns snake_cased (drift
-- `WeeklyReports` in lib/data/local/tables.dart), plus `user_id` which the
-- sync layer stamps at push time. `sync_uuid` maps to the remote `id` and
-- `synced_at` is local-only bookkeeping, so neither exists here (same as
-- tdee_estimates and 0014). There is no `created_at` either: the local table
-- has none, and a remote row carrying one would fail the pull INSERT.
-- test/weekly_reports_supabase_migration_test.dart guards this parity.
--
-- ORDERING: apply this BEFORE any client carrying local schema v48 reaches a
-- user, and in filename order after the earlier outstanding or unverified
-- files: `0015_workout_circuits_and_session_columns.sql`, then
-- `0016_exercise_progression_double.sql` (both recorded as still outstanding
-- in CLAUDE.md), then the v45, v46 and v47 files
-- (`20260928000000_tdee_estimates_v45.sql`,
-- `20260929000000_herculex_ai_program_briefs_v46.sql`,
-- `20261002000000_physique_v47.sql`), and only then this file. This file is
-- WRITTEN, not applied; applying it is a human-gated step (plan 20 of
-- Phase 29). Target project ref is `ldzgyzigvbwofbswitrv` (Herculex).
-- `jioesomepkauponjrena` is a different product: not this one.
--
-- Deliberately NO unique constraint on (user_id, iso_year, iso_week). Pull
-- upserts conflict on the row id only, so a remote unique would turn a second
-- device's push of the same week into a 23505 that blocks its outbox. One row
-- per week is enforced locally, inside the repository's insert transaction,
-- and reads pick the earliest row by (generated_at, id) so a cross-device
-- duplicate can never make a past week change (RESEARCH Pitfall 5, plan 05).
--
-- Post-hoc synced table, so its RLS / trigger / tombstone / realtime wiring is
-- spelled out directly here rather than folded into the 0003-0005 loops,
-- which already ran. Same shape as 0009, 0011, 0014 and 0015.
--
-- `tdee_decision` is free text on purpose: its closed vocabulary ('updated' or
-- 'kept') and the kcal range are validated at the Dart repository boundary,
-- same stance as tdee_estimates. `payload_json` and `narrative_json` are
-- untrusted text on read and are decoded behind try/catch in Dart.

create table weekly_reports (
  id uuid primary key,
  user_id uuid not null references auth.users(id) on delete cascade,
  iso_year integer not null,
  iso_week integer not null,
  week_start_iso text not null,
  generated_at timestamptz not null default now(),
  payload_version integer not null default 1,
  payload_json text not null,
  narrative_json text,
  narrative_attempts integer not null default 0,
  knowledge_version text,
  model_version text,
  tdee_decision text,
  tdee_decision_kcal integer,
  viewed_at timestamptz,
  updated_at timestamptz not null default now(),
  deleted_at timestamptz
);

alter table weekly_reports enable row level security;

create policy weekly_reports_select_own
  on weekly_reports for select using (user_id = auth.uid());
create policy weekly_reports_insert_own
  on weekly_reports for insert with check (user_id = auth.uid());
create policy weekly_reports_update_own
  on weekly_reports for update
  using (user_id = auth.uid())
  with check (user_id = auth.uid());
create policy weekly_reports_delete_own
  on weekly_reports for delete using (user_id = auth.uid());

-- Reuses the two trigger functions 0004/0005 already defined.
create trigger t_set_updated_at_weekly_reports
  before insert or update on weekly_reports
  for each row execute function set_updated_at();

create trigger t_record_tombstone_weekly_reports
  after delete on weekly_reports
  for each row execute function public.record_sync_tombstone();

alter publication supabase_realtime add table public.weekly_reports;

-- 0017 added this composite index to every synced table that existed then.
-- `SupabaseSyncBackendService.pull()` filters
--   user_id = ? and updated_at > ? order by updated_at, id
-- and a table without it is a sequential scan on every pull.
create index if not exists weekly_reports_user_updated_idx
  on public.weekly_reports (user_id, updated_at, id);
