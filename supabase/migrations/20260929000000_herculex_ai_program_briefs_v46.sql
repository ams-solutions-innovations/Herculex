-- The remote half of local schema v46: the synced `herculex_ai_program_briefs`
-- table.
--
-- Herculex AI (Phase 27) persists the accepted program design brief (split,
-- periodization model, per-day roles with rationale, muscle priorities,
-- phase intent) so `ProgramReviewView` can render the AI's per-day rationale
-- and the brief survives reinstall (D-08). Local drift v46 registers
-- `herculex_ai_program_briefs` in `syncTableSpecs`, so every local row is
-- pushed. `SyncService._buildRemotePayload` does `SELECT *` on the local row
-- and forwards every column that is not a registered FK / localOnly / dateTime
-- column; a local column with no Postgres counterpart makes PostgREST answer
-- PGRST204 (unknown column), and the outbox quarantines the op after
-- `maxPushAttempts = 8`. It looks fine locally, which is what makes it worse.
-- The columns below are exactly the local drift columns snake_cased (drift
-- `HerculexAiProgramBriefs` in lib/data/local/tables.dart, recorded verbatim
-- in 27-04-SUMMARY.md), plus `user_id` which the sync layer stamps at push
-- time. `sync_uuid` maps to the remote `id` and `synced_at` is local-only
-- bookkeeping, so neither exists here (same as tdee_estimates/0014).
-- test/herculex_ai_program_briefs_supabase_migration_test.dart guards this
-- parity.
--
-- ORDERING: `herculex_ai_program_briefs` is a wholly new table introduced at
-- local schema v46 — it has no predecessor rows and no dependency on
-- 0015/0016's still-outstanding-per-RESEARCH.md status the way
-- 20260928000000_tdee_estimates_v45.sql did (that file's own header note
-- about Assumption A2 does not apply here; this table did not exist before
-- v46). This file is WRITTEN, not applied; applying it is a human-gated step
-- (plan 27-10's Task 2). Target project ref is `ldzgyzigvbwofbswitrv`
-- (Herculex). `jioesomepkauponjrena` is a different product: not this one.
--
-- Post-hoc synced table, so its RLS / trigger / tombstone / realtime wiring is
-- spelled out directly here rather than folded into the 0003-0005 loops,
-- which already ran. Same shape as 0009, 0011, 0014, 0015 and
-- 20260928000000_tdee_estimates_v45.sql.
--
-- `program_id` uses the standard non-auth.users FK shape already established
-- by 0002_sync_schema_children.sql and
-- 20260908200007_program_builder_v39.sql (`references public.programs(id) on
-- delete cascade`) — `SyncService` resolves the local integer program id to
-- the remote synced programs row's uuid at push time, per
-- sync_table_specs.dart's SimpleFk pattern registered in plan 27-04.

create table herculex_ai_program_briefs (
  id uuid primary key,
  user_id uuid not null references auth.users(id) on delete cascade,
  program_id uuid not null references public.programs(id) on delete cascade,
  brief_json text not null,
  source text not null default 'herculex_ai',
  knowledge_version text,
  model_version text,
  confirmed_at timestamptz not null default now(),
  active boolean not null default true,
  updated_at timestamptz not null default now(),
  deleted_at timestamptz
);

alter table herculex_ai_program_briefs enable row level security;

create policy herculex_ai_program_briefs_select_own
  on herculex_ai_program_briefs for select using (user_id = auth.uid());
create policy herculex_ai_program_briefs_insert_own
  on herculex_ai_program_briefs for insert with check (user_id = auth.uid());
create policy herculex_ai_program_briefs_update_own
  on herculex_ai_program_briefs for update
  using (user_id = auth.uid())
  with check (user_id = auth.uid());
create policy herculex_ai_program_briefs_delete_own
  on herculex_ai_program_briefs for delete using (user_id = auth.uid());

-- Reuses the two trigger functions 0004/0005 already defined.
create trigger t_set_updated_at_herculex_ai_program_briefs
  before insert or update on herculex_ai_program_briefs
  for each row execute function set_updated_at();

create trigger t_record_tombstone_herculex_ai_program_briefs
  after delete on herculex_ai_program_briefs
  for each row execute function public.record_sync_tombstone();

alter publication supabase_realtime add table public.herculex_ai_program_briefs;

-- 0017 added this composite index to every synced table that existed then.
-- `SupabaseSyncBackendService.pull()` filters
--   user_id = ? and updated_at > ? order by updated_at, id
-- and a table without it is a sequential scan on every pull.
create index if not exists herculex_ai_program_briefs_user_updated_idx
  on public.herculex_ai_program_briefs (user_id, updated_at, id);
