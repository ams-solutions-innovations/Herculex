-- Phase 10 sync — core tables with no dependency on another synced table.
--
-- Every table's `id` is the client-generated `sync_uuid` from the matching
-- Drift table (schema v25) — NOT a server-generated default. Clients must
-- always supply it on insert.
--
-- `updated_at` is the authoritative LWW clock, set by a trigger in
-- 0004_sync_triggers.sql — never trust a client-supplied value for it.
-- `deleted_at` is a soft-delete tombstone (non-null = deleted).
--
-- Catalogue tables (exercise_catalog, foods) only ever receive rows the
-- client marks isCustom — seeded/bundled rows never reach Postgres at all.
-- Other synced tables that reference a catalogue entry carry BOTH a nullable
-- uuid FK (for custom rows) and a nullable stable natural-key text column
-- (for seeded rows, resolved locally by slug/catalogueId/kind on every
-- device from the same bundled assets). Exactly one of the pair is set.

create table gyms (
  id uuid primary key,
  user_id uuid not null references auth.users(id) on delete cascade,
  name text not null,
  is_default boolean not null default false,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  deleted_at timestamptz
);

create table workout_folders (
  id uuid primary key,
  user_id uuid not null references auth.users(id) on delete cascade,
  name text not null,
  emoji text not null default '💪',
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  deleted_at timestamptz
);

-- Custom (isCustom = true) exercises only. Seeded rows are never pushed here.
create table exercise_catalog (
  id uuid primary key,
  user_id uuid not null references auth.users(id) on delete cascade,
  name text not null,
  primary_muscle text not null,
  equipment text not null,
  mechanics text not null,
  force text not null,
  plane text not null,
  default_rest_seconds integer not null default 120,
  aka text,
  category text not null default 'strength',
  movement_pattern text,
  movement_pattern_raw text,
  modality text not null default 'barbell',
  cns_score integer not null default 3,
  recovery_impact integer not null default 3,
  logging_metric text not null default 'weight_reps',
  supports_weighted_bodyweight boolean not null default false,
  attachments text,
  is_reviewed boolean not null default false,
  movement_family text,
  movement_slug text,
  allowed_equipment text,
  updated_at timestamptz not null default now(),
  deleted_at timestamptz
);

-- Custom (isCustom = true) foods only.
create table foods (
  id uuid primary key,
  user_id uuid not null references auth.users(id) on delete cascade,
  name text not null,
  brand text,
  barcode text,
  kcal_per_100g double precision not null,
  protein_per_100g double precision not null default 0,
  carbs_per_100g double precision not null default 0,
  fat_per_100g double precision not null default 0,
  fiber_per_100g double precision,
  serving_grams double precision,
  serving_label text,
  source text not null default 'local',
  image_url text,
  created_at timestamptz not null default now(),
  sodium_mg_per_100g double precision,
  potassium_mg_per_100g double precision,
  cholesterol_mg_per_100g double precision,
  reference_basis text not null default '100 g',
  serving_amount double precision,
  serving_unit text,
  category text,
  country text,
  source_metadata_json text,
  updated_at timestamptz not null default now(),
  deleted_at timestamptz
);

create table recipes (
  id uuid primary key,
  user_id uuid not null references auth.users(id) on delete cascade,
  name text not null,
  servings integer not null default 1,
  notes text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  deleted_at timestamptz
);

-- Custom (isCustom = true) accessories only. Seeded rows resolve on-device
-- by `kind` (one seeded row per kind: belt, knee_sleeves, wrist_wraps,
-- straps, fat_grips, chains).
create table accessories (
  id uuid primary key,
  user_id uuid not null references auth.users(id) on delete cascade,
  name text not null,
  kind text not null,
  forearm_multiplier double precision not null default 1.0,
  updated_at timestamptz not null default now(),
  deleted_at timestamptz
);

-- Custom (isCustom = true) bands only. Seeded rows resolve on-device by
-- (color, tension_kg) — no stable id exists for them today.
create table bands (
  id uuid primary key,
  user_id uuid not null references auth.users(id) on delete cascade,
  name text not null,
  color text not null,
  tension_kg double precision not null,
  updated_at timestamptz not null default now(),
  deleted_at timestamptz
);

create table nutrition_targets (
  id uuid primary key,
  user_id uuid not null references auth.users(id) on delete cascade,
  label text not null,
  kcal integer not null,
  protein_g integer not null,
  carbs_g integer not null,
  fat_g integer,
  applies_to text not null default 'global',
  updated_at timestamptz not null default now(),
  deleted_at timestamptz,
  unique (user_id, applies_to)
);

create table diet_schedules (
  id uuid primary key,
  user_id uuid not null references auth.users(id) on delete cascade,
  start_date_iso text not null,
  reduce_pct double precision not null,
  interval_days integer not null,
  active boolean not null default true,
  updated_at timestamptz not null default now(),
  deleted_at timestamptz
);

create table carb_cycle_plans (
  id uuid primary key,
  user_id uuid not null references auth.users(id) on delete cascade,
  week_start_iso text not null,
  day_levels_json text not null,
  auto boolean not null default true,
  updated_at timestamptz not null default now(),
  deleted_at timestamptz,
  unique (user_id, week_start_iso)
);

create table fasting_sessions (
  id uuid primary key,
  user_id uuid not null references auth.users(id) on delete cascade,
  started_at timestamptz not null,
  ended_at timestamptz,
  target_seconds integer not null,
  completed boolean not null default false,
  updated_at timestamptz not null default now(),
  deleted_at timestamptz
);

create table body_measurements (
  id uuid primary key,
  user_id uuid not null references auth.users(id) on delete cascade,
  date_iso text not null,
  metric text not null,
  value double precision not null,
  updated_at timestamptz not null default now(),
  deleted_at timestamptz
);

create table cycle_logs (
  id uuid primary key,
  user_id uuid not null references auth.users(id) on delete cascade,
  date_iso text not null,
  phase text not null,
  intensity integer not null default 3,
  manual_override boolean not null default false,
  updated_at timestamptz not null default now(),
  deleted_at timestamptz
);

create table cycle_settings (
  id uuid primary key,
  user_id uuid not null references auth.users(id) on delete cascade,
  avg_cycle_days integer not null default 28,
  avg_period_days integer not null default 5,
  last_period_start timestamptz not null,
  updated_at timestamptz not null default now(),
  deleted_at timestamptz
);

create table exercise_rotations (
  id uuid primary key,
  user_id uuid not null references auth.users(id) on delete cascade,
  name text not null,
  movement_pattern text,
  rotate_every_weeks integer not null default 2,
  updated_at timestamptz not null default now(),
  deleted_at timestamptz
);

create table daily_summaries (
  id uuid primary key,
  user_id uuid not null references auth.users(id) on delete cascade,
  date_iso text not null,
  water_ml integer not null default 0,
  weigh_in_kg double precision,
  notes text,
  updated_at timestamptz not null default now(),
  deleted_at timestamptz,
  unique (user_id, date_iso)
);

create table external_events (
  id uuid primary key,
  user_id uuid not null references auth.users(id) on delete cascade,
  date_from_iso text not null,
  date_to_iso text not null,
  type text not null,
  notes text,
  updated_at timestamptz not null default now(),
  deleted_at timestamptz
);

-- micro_workouts references exercise_catalog (dual-column: custom uuid or
-- seeded slug), so it lives here even though it has no other synced-table
-- dependency — exercise_catalog is created above in this same file.
create table micro_workouts (
  id uuid primary key,
  user_id uuid not null references auth.users(id) on delete cascade,
  name text not null,
  exercise_catalog_id uuid references exercise_catalog(id) on delete restrict,
  exercise_slug text,
  target_reps integer not null,
  times_per_day integer not null default 1,
  active boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  deleted_at timestamptz,
  check (
    (exercise_catalog_id is not null and exercise_slug is null) or
    (exercise_catalog_id is null and exercise_slug is not null)
  )
);
