-- Phase 10 sync — tables that reference another synced table. Ordered so
-- every `references` target already exists by the time it's needed.

-- ── Depends only on 0001 tables ─────────────────────────────────────────────

create table recipe_ingredients (
  id uuid primary key,
  user_id uuid not null references auth.users(id) on delete cascade,
  recipe_id uuid not null references recipes(id) on delete cascade,
  food_catalogue_id uuid references foods(id) on delete restrict,
  food_catalogue_ref text,
  grams double precision not null,
  updated_at timestamptz not null default now(),
  deleted_at timestamptz,
  check (
    (food_catalogue_id is not null and food_catalogue_ref is null) or
    (food_catalogue_id is null and food_catalogue_ref is not null)
  )
);

create table workout_templates (
  id uuid primary key,
  user_id uuid not null references auth.users(id) on delete cascade,
  name text not null,
  notes text,
  folder_id uuid references workout_folders(id) on delete set null,
  created_at timestamptz not null default now(),
  last_used_at timestamptz,
  updated_at timestamptz not null default now(),
  deleted_at timestamptz
);

create table workout_sessions (
  id uuid primary key,
  user_id uuid not null references auth.users(id) on delete cascade,
  name text,
  started_at timestamptz not null,
  ended_at timestamptz,
  notes text,
  session_rpe integer,
  gym_id uuid references gyms(id) on delete set null,
  micro_workout_id uuid references micro_workouts(id) on delete set null,
  updated_at timestamptz not null default now(),
  deleted_at timestamptz
);

create table programs (
  id uuid primary key,
  user_id uuid not null references auth.users(id) on delete cascade,
  name text not null,
  description text,
  weeks integer not null default 4,
  type text not null default 'block',
  progression_strategy text not null default 'volume',
  created_by_user boolean not null default true,
  archived boolean not null default false,
  periodization_model text not null default 'none',
  split_type text not null default 'custom',
  schedule_mode text not null default 'weekly',
  cycle_length integer,
  days_per_week integer,
  start_date_iso text,
  is_active boolean not null default false,
  updated_at timestamptz not null default now(),
  deleted_at timestamptz
);

create table exercise_progressions (
  id uuid primary key,
  user_id uuid not null references auth.users(id) on delete cascade,
  exercise_catalog_id uuid references exercise_catalog(id) on delete cascade,
  exercise_slug text,
  goal text not null default 'muscle_gain',
  weekly_increase_pct double precision not null default 5.0,
  enabled boolean not null default true,
  updated_at timestamptz not null default now(),
  deleted_at timestamptz,
  check (
    (exercise_catalog_id is not null and exercise_slug is null) or
    (exercise_catalog_id is null and exercise_slug is not null)
  )
);

-- Local `updatedAt` here is a "last recalled" UX timestamp, not the sync
-- clock — mapped to `recalled_at` remotely to avoid colliding with the
-- sync-standard `updated_at` column every table gets.
create table machine_settings (
  id uuid primary key,
  user_id uuid not null references auth.users(id) on delete cascade,
  exercise_catalog_id uuid references exercise_catalog(id) on delete cascade,
  exercise_slug text,
  gym_id uuid references gyms(id) on delete set null,
  label text,
  settings_json text not null,
  recalled_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  deleted_at timestamptz,
  check (
    (exercise_catalog_id is not null and exercise_slug is null) or
    (exercise_catalog_id is null and exercise_slug is not null)
  )
);

create table food_entries (
  id uuid primary key,
  user_id uuid not null references auth.users(id) on delete cascade,
  date_iso text not null,
  meal text not null,
  food_catalogue_id uuid references foods(id) on delete restrict,
  food_catalogue_ref text,
  recipe_id uuid references recipes(id) on delete restrict,
  servings double precision not null default 1,
  grams_override double precision,
  portion_amount double precision,
  portion_unit text,
  logged_at timestamptz not null default now(),
  snapshot_basis text,
  snapshot_name text,
  snapshot_brand text,
  snapshot_kcal double precision,
  snapshot_protein_g double precision,
  snapshot_carbs_g double precision,
  snapshot_fat_g double precision,
  snapshot_fiber_g double precision,
  snapshot_sodium_mg double precision,
  snapshot_potassium_mg double precision,
  snapshot_cholesterol_mg double precision,
  snapshot_serving_grams double precision,
  snapshot_serving_amount double precision,
  snapshot_serving_unit text,
  snapshot_micros_json text,
  updated_at timestamptz not null default now(),
  deleted_at timestamptz,
  check (
    (food_catalogue_id is not null or food_catalogue_ref is not null or recipe_id is not null)
  )
);

-- ── Depends on tables above (level 2) ───────────────────────────────────────

create table workout_exercises (
  id uuid primary key,
  user_id uuid not null references auth.users(id) on delete cascade,
  session_id uuid not null references workout_sessions(id) on delete cascade,
  exercise_catalog_id uuid references exercise_catalog(id) on delete restrict,
  exercise_slug text,
  order_index integer not null,
  superset_group integer,
  target_rest_seconds integer,
  equipment_variant text,
  machine_config_json text,
  updated_at timestamptz not null default now(),
  deleted_at timestamptz,
  check (
    (exercise_catalog_id is not null and exercise_slug is null) or
    (exercise_catalog_id is null and exercise_slug is not null)
  )
);

create table template_exercises (
  id uuid primary key,
  user_id uuid not null references auth.users(id) on delete cascade,
  template_id uuid not null references workout_templates(id) on delete cascade,
  exercise_catalog_id uuid references exercise_catalog(id) on delete restrict,
  exercise_slug text,
  order_index integer not null,
  target_sets integer not null default 3,
  target_reps_min integer,
  target_reps_max integer,
  target_rest_seconds integer,
  superset_group integer,
  updated_at timestamptz not null default now(),
  deleted_at timestamptz,
  check (
    (exercise_catalog_id is not null and exercise_slug is null) or
    (exercise_catalog_id is null and exercise_slug is not null)
  )
);

create table program_weeks (
  id uuid primary key,
  user_id uuid not null references auth.users(id) on delete cascade,
  program_id uuid not null references programs(id) on delete cascade,
  week_index integer not null,
  adjustment_factor double precision not null default 1.0,
  block_phase text,
  intensity_factor double precision not null default 1.0,
  updated_at timestamptz not null default now(),
  deleted_at timestamptz
);

create table rotation_members (
  id uuid primary key,
  user_id uuid not null references auth.users(id) on delete cascade,
  rotation_id uuid not null references exercise_rotations(id) on delete cascade,
  exercise_catalog_id uuid references exercise_catalog(id) on delete restrict,
  exercise_slug text,
  order_index integer not null,
  updated_at timestamptz not null default now(),
  deleted_at timestamptz,
  check (
    (exercise_catalog_id is not null and exercise_slug is null) or
    (exercise_catalog_id is null and exercise_slug is not null)
  )
);

-- ── Depends on level 2 (level 3) ────────────────────────────────────────────

create table set_entries (
  id uuid primary key,
  user_id uuid not null references auth.users(id) on delete cascade,
  workout_exercise_id uuid not null references workout_exercises(id) on delete cascade,
  set_index integer not null,
  weight_kg double precision not null,
  reps integer not null,
  rpe_x10 integer,
  is_warmup boolean not null default false,
  is_completed boolean not null default false,
  completed_at timestamptz,
  set_type text not null default 'standard',
  set_type_meta_json text,
  bodyweight_kg double precision,
  chains_kg double precision,
  updated_at timestamptz not null default now(),
  deleted_at timestamptz
);

create table template_sets (
  id uuid primary key,
  user_id uuid not null references auth.users(id) on delete cascade,
  template_exercise_id uuid not null references template_exercises(id) on delete cascade,
  set_order integer not null,
  set_type text not null default 'standard',
  set_type_meta_json text,
  target_reps integer,
  target_reps_min integer,
  target_reps_max integer,
  target_weight_kg double precision,
  is_warmup boolean not null default false,
  updated_at timestamptz not null default now(),
  deleted_at timestamptz
);

create table program_days (
  id uuid primary key,
  user_id uuid not null references auth.users(id) on delete cascade,
  program_week_id uuid not null references program_weeks(id) on delete cascade,
  day_of_week integer not null,
  name text not null,
  template_id uuid references workout_templates(id) on delete set null,
  order_index integer not null default 0,
  slot_label text,
  cycle_day_index integer,
  is_rest boolean not null default false,
  updated_at timestamptz not null default now(),
  deleted_at timestamptz
);

-- ── Depends on level 3 (level 4) ────────────────────────────────────────────

create table program_day_exercises (
  id uuid primary key,
  user_id uuid not null references auth.users(id) on delete cascade,
  program_day_id uuid not null references program_days(id) on delete cascade,
  exercise_catalog_id uuid references exercise_catalog(id) on delete restrict,
  exercise_slug text,
  target_sets integer not null default 3,
  target_reps_min integer,
  target_reps_max integer,
  target_rpe integer,
  order_index integer not null,
  rotation_id uuid references exercise_rotations(id) on delete set null,
  set_type text not null default 'standard',
  percent_of_1rm double precision,
  equipment_variant text,
  updated_at timestamptz not null default now(),
  deleted_at timestamptz,
  check (
    (exercise_catalog_id is not null and exercise_slug is null) or
    (exercise_catalog_id is null and exercise_slug is not null)
  )
);

create table scheduled_workouts (
  id uuid primary key,
  user_id uuid not null references auth.users(id) on delete cascade,
  date_iso text not null,
  program_day_id uuid not null references program_days(id) on delete cascade,
  completed_session_id uuid references workout_sessions(id) on delete set null,
  status text not null default 'planned',
  program_id uuid references programs(id) on delete cascade,
  order_index integer not null default 0,
  occurrence_index integer not null default 0,
  template_id_override uuid references workout_templates(id) on delete set null,
  updated_at timestamptz not null default now(),
  deleted_at timestamptz
);

-- ── Depends on level 3/4 (level 5) ──────────────────────────────────────────

-- accessory_id resolves custom accessories; accessory_kind resolves seeded
-- ones (one seeded row per kind — see 0001's note on `accessories`).
create table set_accessories (
  id uuid primary key,
  user_id uuid not null references auth.users(id) on delete cascade,
  set_entry_id uuid not null references set_entries(id) on delete cascade,
  accessory_id uuid references accessories(id) on delete restrict,
  accessory_kind text,
  updated_at timestamptz not null default now(),
  deleted_at timestamptz,
  check (
    (accessory_id is not null and accessory_kind is null) or
    (accessory_id is null and accessory_kind is not null)
  )
);

-- band_id resolves custom bands; (band_color, band_tension_kg) resolves
-- seeded ones — bands have no other stable natural key today.
create table set_bands (
  id uuid primary key,
  user_id uuid not null references auth.users(id) on delete cascade,
  set_entry_id uuid not null references set_entries(id) on delete cascade,
  band_id uuid references bands(id) on delete restrict,
  band_color text,
  band_tension_kg double precision,
  count integer not null default 1,
  mode text not null default 'resistance',
  updated_at timestamptz not null default now(),
  deleted_at timestamptz,
  check (
    (band_id is not null and band_color is null) or
    (band_id is null and band_color is not null and band_tension_kg is not null)
  )
);
