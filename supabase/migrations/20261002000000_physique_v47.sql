-- The remote half of local schema v47: the four synced physique tables
-- (`physique_goals`, `physique_assessments`, `physique_roadmap_phases`,
-- `physique_photos`) behind the persistent Dream Physique (Phase 23, PHYS-01).
--
-- Local drift v47 registers all four in `syncTableSpecs`, so every local row
-- is pushed. `SyncService._buildRemotePayload` does `SELECT *` on the local
-- row and forwards every column that is not a registered FK / localOnly /
-- dateTime column; a local column with no Postgres counterpart makes PostgREST
-- answer PGRST204 (unknown column), and the outbox quarantines the op after
-- `maxPushAttempts = 8`. It looks fine locally, which is what makes it worse.
-- The columns below are exactly the local drift columns snake_cased (drift
-- classes `PhysiqueGoals`, `PhysiqueAssessments`, `PhysiqueRoadmapPhases` and
-- `PhysiquePhotos` in lib/data/local/tables.dart), plus `user_id` which the
-- sync layer stamps at push time. `sync_uuid` maps to the remote `id` and
-- `synced_at` is local-only bookkeeping, so neither exists here (same as
-- tdee_estimates and herculex_ai_program_briefs).
-- test/physique_supabase_migration_test.dart guards this parity.
--
-- METADATA ONLY (D-09): `physique_photos` rows carry a relative path, pose and
-- date. No image bytes are stored or synced; photos stay on the device (GDPR
-- Art. 9 memo, special-category data minimisation).
--
-- Nullability mirrors the drift columns exactly. `estimated_months` and
-- `target_bf_percent` are nullable because a `legacy_import` goal built from
-- legacy photos alone has no AI analysis and therefore no target ("no target,
-- maintain-only", D-08); `target_aesthetic_style` defaults to the empty
-- string for the same case. Text vocabularies (status, source, kind, role,
-- pose, ...) are free text: validation lives at the Dart repository boundary,
-- same stance as tdee_estimates.
--
-- ORDERING: all four tables are new at local schema v47 and depend on nothing
-- outstanding. Migrations 0015 and 0016 are already applied remotely, so
-- there is no ordering dependency on them. Tables are created parent-first
-- (goals, then assessments and roadmap phases, then photos).
--
-- This file is WRITTEN, not applied. Applying it is a human-gated step
-- (Plan 17) against project ref `ldzgyzigvbwofbswitrv` (Herculex);
-- `jioesomepkauponjrena` is a different product: not this one. Confirm the
-- linked project before any push.
--
-- Post-hoc synced tables, so their RLS / trigger / tombstone / realtime wiring
-- is spelled out directly here rather than folded into the 0003-0005 loops,
-- which already ran. Same shape as 0009, 0011, 0014, 0015,
-- 20260928000000_tdee_estimates_v45.sql and
-- 20260929000000_herculex_ai_program_briefs_v46.sql.
--
-- Child FKs use the standard non-auth.users shape (`references
-- public.<table>(id) on delete cascade`); `SyncService` resolves the local
-- integer ids to the remote synced rows' uuids at push time, per the
-- `SimpleFk` entries in sync_table_specs.dart.

create table physique_goals (
  id uuid primary key,
  user_id uuid not null references auth.users(id) on delete cascade,
  status text not null default 'active',
  source text not null default 'ai_analysis',
  target_aesthetic_style text not null default '',
  timeframe_range text not null default '',
  estimated_months integer,
  target_bf_percent double precision,
  start_weight_kg double precision,
  start_bf_percent double precision,
  started_at timestamptz not null default now(),
  archived_at timestamptz,
  roadmap_accepted_at timestamptz,
  advance_snoozed_until timestamptz,
  updated_at timestamptz not null default now(),
  deleted_at timestamptz
);

alter table physique_goals enable row level security;

create policy physique_goals_select_own
  on physique_goals for select using (user_id = auth.uid());
create policy physique_goals_insert_own
  on physique_goals for insert with check (user_id = auth.uid());
create policy physique_goals_update_own
  on physique_goals for update
  using (user_id = auth.uid())
  with check (user_id = auth.uid());
create policy physique_goals_delete_own
  on physique_goals for delete using (user_id = auth.uid());

-- Reuses the two trigger functions 0004/0005 already defined.
create trigger t_set_updated_at_physique_goals
  before insert or update on physique_goals
  for each row execute function set_updated_at();

create trigger t_record_tombstone_physique_goals
  after delete on physique_goals
  for each row execute function public.record_sync_tombstone();

alter publication supabase_realtime add table public.physique_goals;

-- Pull index: `SupabaseSyncBackendService.pull()` filters
--   user_id = ? and updated_at > ? order by updated_at, id
-- and a table without it is a sequential scan on every pull.
create index if not exists physique_goals_user_updated_idx
  on public.physique_goals (user_id, updated_at, id);

create table physique_assessments (
  id uuid primary key,
  user_id uuid not null references auth.users(id) on delete cascade,
  goal_id uuid not null references public.physique_goals(id) on delete cascade,
  kind text not null,
  assessed_at timestamptz not null default now(),
  date_iso text not null,
  weight_kg double precision,
  current_bf_percent double precision,
  bf_range_min double precision,
  bf_range_max double precision,
  confidence text not null default 'unknown',
  verdict text,
  direction_band_low double precision,
  direction_band_high double precision,
  reason text,
  limitations_json text,
  source text not null default 'ai',
  model_version text,
  knowledge_version text,
  summary_json text,
  updated_at timestamptz not null default now(),
  deleted_at timestamptz
);

alter table physique_assessments enable row level security;

create policy physique_assessments_select_own
  on physique_assessments for select using (user_id = auth.uid());
create policy physique_assessments_insert_own
  on physique_assessments for insert with check (user_id = auth.uid());
create policy physique_assessments_update_own
  on physique_assessments for update
  using (user_id = auth.uid())
  with check (user_id = auth.uid());
create policy physique_assessments_delete_own
  on physique_assessments for delete using (user_id = auth.uid());

-- Reuses the two trigger functions 0004/0005 already defined.
create trigger t_set_updated_at_physique_assessments
  before insert or update on physique_assessments
  for each row execute function set_updated_at();

create trigger t_record_tombstone_physique_assessments
  after delete on physique_assessments
  for each row execute function public.record_sync_tombstone();

alter publication supabase_realtime add table public.physique_assessments;

-- Pull index: `SupabaseSyncBackendService.pull()` filters
--   user_id = ? and updated_at > ? order by updated_at, id
-- and a table without it is a sequential scan on every pull.
create index if not exists physique_assessments_user_updated_idx
  on public.physique_assessments (user_id, updated_at, id);

create table physique_roadmap_phases (
  id uuid primary key,
  user_id uuid not null references auth.users(id) on delete cascade,
  goal_id uuid not null references public.physique_goals(id) on delete cascade,
  order_index integer not null,
  phase_type text not null,
  planned_weeks integer not null,
  target_weight_kg double precision,
  target_bf_percent double precision,
  weekly_rate_kg double precision,
  tempo_capped boolean not null default false,
  status text not null default 'upcoming',
  started_at timestamptz,
  completed_at timestamptz,
  updated_at timestamptz not null default now(),
  deleted_at timestamptz
);

alter table physique_roadmap_phases enable row level security;

create policy physique_roadmap_phases_select_own
  on physique_roadmap_phases for select using (user_id = auth.uid());
create policy physique_roadmap_phases_insert_own
  on physique_roadmap_phases for insert with check (user_id = auth.uid());
create policy physique_roadmap_phases_update_own
  on physique_roadmap_phases for update
  using (user_id = auth.uid())
  with check (user_id = auth.uid());
create policy physique_roadmap_phases_delete_own
  on physique_roadmap_phases for delete using (user_id = auth.uid());

-- Reuses the two trigger functions 0004/0005 already defined.
create trigger t_set_updated_at_physique_roadmap_phases
  before insert or update on physique_roadmap_phases
  for each row execute function set_updated_at();

create trigger t_record_tombstone_physique_roadmap_phases
  after delete on physique_roadmap_phases
  for each row execute function public.record_sync_tombstone();

alter publication supabase_realtime add table public.physique_roadmap_phases;

-- Pull index: `SupabaseSyncBackendService.pull()` filters
--   user_id = ? and updated_at > ? order by updated_at, id
-- and a table without it is a sequential scan on every pull.
create index if not exists physique_roadmap_phases_user_updated_idx
  on public.physique_roadmap_phases (user_id, updated_at, id);

create table physique_photos (
  id uuid primary key,
  user_id uuid not null references auth.users(id) on delete cascade,
  goal_id uuid not null references public.physique_goals(id) on delete cascade,
  assessment_id uuid references public.physique_assessments(id) on delete set null,
  role text not null,
  pose text not null,
  date_iso text not null,
  taken_at timestamptz not null default now(),
  relative_path text not null,
  blurred boolean not null default false,
  source text not null default 'capture',
  legacy_ref text,
  updated_at timestamptz not null default now(),
  deleted_at timestamptz
);

alter table physique_photos enable row level security;

create policy physique_photos_select_own
  on physique_photos for select using (user_id = auth.uid());
create policy physique_photos_insert_own
  on physique_photos for insert with check (user_id = auth.uid());
create policy physique_photos_update_own
  on physique_photos for update
  using (user_id = auth.uid())
  with check (user_id = auth.uid());
create policy physique_photos_delete_own
  on physique_photos for delete using (user_id = auth.uid());

-- Reuses the two trigger functions 0004/0005 already defined.
create trigger t_set_updated_at_physique_photos
  before insert or update on physique_photos
  for each row execute function set_updated_at();

create trigger t_record_tombstone_physique_photos
  after delete on physique_photos
  for each row execute function public.record_sync_tombstone();

alter publication supabase_realtime add table public.physique_photos;

-- Pull index: `SupabaseSyncBackendService.pull()` filters
--   user_id = ? and updated_at > ? order by updated_at, id
-- and a table without it is a sequential scan on every pull.
create index if not exists physique_photos_user_updated_idx
  on public.physique_photos (user_id, updated_at, id);
