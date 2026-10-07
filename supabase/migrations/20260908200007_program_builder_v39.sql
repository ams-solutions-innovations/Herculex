-- Unified program builder, deterministic exercise rotation and immutable
-- workout prescriptions (local Drift schema v39).

alter table public.gyms
  add column if not exists all_equipment boolean not null default true;

alter table public.exercise_catalog
  add column if not exists required_equipment_keys text,
  add column if not exists max_effort_eligibility text;

alter table public.programs
  add column if not exists build_mode text not null default 'manual',
  add column if not exists training_goal text not null default 'hypertrophy',
  add column if not exists experience_level text not null default 'intermediate',
  add column if not exists adaptation_mode text not null default 'review_structural';

alter table public.program_days
  add column if not exists stress_role text not null default 'mixed';

create table public.prescription_templates (
  id uuid primary key,
  user_id uuid not null references auth.users(id) on delete cascade,
  name text not null,
  method text not null,
  prescription_json text not null,
  is_built_in boolean not null default false,
  updated_at timestamptz not null default now(),
  deleted_at timestamptz
);

create table public.physique_programming_profiles (
  id uuid primary key,
  user_id uuid not null references auth.users(id) on delete cascade,
  priorities_json text not null,
  source text not null default 'manual',
  model_version text,
  confirmed_at timestamptz not null default now(),
  active boolean not null default true,
  updated_at timestamptz not null default now(),
  deleted_at timestamptz
);

create table public.program_exercise_slots (
  id uuid primary key,
  user_id uuid not null references auth.users(id) on delete cascade,
  program_id uuid not null references public.programs(id) on delete cascade,
  slot_key text not null,
  day_slot_label text not null,
  order_index integer not null,
  role text not null default 'accessory',
  movement_pattern text,
  primary_muscle text,
  training_method text not null default 'auto',
  prescription_json text,
  rotation_policy_json text,
  fatigue_budget integer not null default 3,
  user_locked boolean not null default false,
  wave_override_weeks integer,
  updated_at timestamptz not null default now(),
  deleted_at timestamptz,
  unique (program_id, slot_key)
);

create table public.program_slot_pool_members (
  id uuid primary key,
  user_id uuid not null references auth.users(id) on delete cascade,
  slot_id uuid not null references public.program_exercise_slots(id) on delete cascade,
  exercise_catalog_id uuid references public.exercise_catalog(id) on delete restrict,
  exercise_slug text,
  order_index integer not null default 0,
  pinned boolean not null default false,
  updated_at timestamptz not null default now(),
  deleted_at timestamptz,
  unique (slot_id, exercise_catalog_id),
  unique (slot_id, exercise_slug),
  check (
    (exercise_catalog_id is not null and exercise_slug is null) or
    (exercise_catalog_id is null and exercise_slug is not null)
  )
);

create table public.rotation_assignments (
  id uuid primary key,
  user_id uuid not null references auth.users(id) on delete cascade,
  slot_id uuid not null references public.program_exercise_slots(id) on delete cascade,
  exercise_catalog_id uuid references public.exercise_catalog(id) on delete restrict,
  exercise_slug text,
  week_index integer not null,
  source text not null default 'planned',
  reason text not null,
  variant_config_json text,
  updated_at timestamptz not null default now(),
  deleted_at timestamptz,
  unique (slot_id, week_index),
  check (
    (exercise_catalog_id is not null and exercise_slug is null) or
    (exercise_catalog_id is null and exercise_slug is not null)
  )
);

create table public.exercise_preferences (
  id uuid primary key,
  user_id uuid not null references auth.users(id) on delete cascade,
  exercise_catalog_id uuid references public.exercise_catalog(id) on delete cascade,
  exercise_slug text,
  program_id uuid references public.programs(id) on delete cascade,
  affinity text not null default 'okay',
  allowed_roles_json text,
  note text,
  updated_at timestamptz not null default now(),
  deleted_at timestamptz,
  check (
    (exercise_catalog_id is not null and exercise_slug is null) or
    (exercise_catalog_id is null and exercise_slug is not null)
  )
);

create table public.gym_equipment (
  id uuid primary key,
  user_id uuid not null references auth.users(id) on delete cascade,
  gym_id uuid not null references public.gyms(id) on delete cascade,
  equipment_key text not null,
  available boolean not null default true,
  updated_at timestamptz not null default now(),
  deleted_at timestamptz,
  unique (gym_id, equipment_key)
);

alter table public.program_day_exercises
  add column if not exists program_exercise_slot_id uuid
    references public.program_exercise_slots(id) on delete set null,
  add column if not exists slot_role text not null default 'accessory',
  add column if not exists training_method text not null default 'auto',
  add column if not exists target_rir integer,
  add column if not exists rest_seconds integer,
  add column if not exists prescription_why text,
  add column if not exists prescription_json text,
  add column if not exists variant_config_json text;

alter table public.workout_exercises
  add column if not exists program_exercise_slot_id uuid
    references public.program_exercise_slots(id) on delete set null,
  add column if not exists rotation_assignment_id uuid
    references public.rotation_assignments(id) on delete set null,
  add column if not exists planned_slot_role text,
  add column if not exists planned_training_method text,
  add column if not exists planned_prescription_why text,
  add column if not exists planned_wave_index integer,
  add column if not exists planned_wave_count integer;

alter table public.set_entries
  add column if not exists planned_reps_min integer,
  add column if not exists planned_reps_max integer,
  add column if not exists planned_weight_kg double precision,
  add column if not exists planned_rpe_x10 integer,
  add column if not exists planned_rir integer,
  add column if not exists planned_percent_of1_rm double precision,
  add column if not exists planned_intent text;

-- Pull and FK paths used by the offline-first sync engine.
do $$
declare
  t text;
  tables text[] := array[
    'prescription_templates', 'physique_programming_profiles',
    'program_exercise_slots', 'program_slot_pool_members',
    'rotation_assignments', 'exercise_preferences', 'gym_equipment'
  ];
begin
  foreach t in array tables loop
    execute format(
      'create index %I on public.%I (user_id, updated_at, id)',
      t || '_user_updated_idx', t
    );
  end loop;
end $$;

create index program_exercise_slots_program_id_idx
  on public.program_exercise_slots (program_id);
create index program_slot_pool_members_slot_id_idx
  on public.program_slot_pool_members (slot_id);
create index program_slot_pool_members_exercise_catalog_id_idx
  on public.program_slot_pool_members (exercise_catalog_id);
create index rotation_assignments_slot_id_idx
  on public.rotation_assignments (slot_id);
create index rotation_assignments_exercise_catalog_id_idx
  on public.rotation_assignments (exercise_catalog_id);
create index exercise_preferences_exercise_catalog_id_idx
  on public.exercise_preferences (exercise_catalog_id);
create index exercise_preferences_program_id_idx
  on public.exercise_preferences (program_id);
create index gym_equipment_gym_id_idx on public.gym_equipment (gym_id);
create index program_day_exercises_program_exercise_slot_id_idx
  on public.program_day_exercises (program_exercise_slot_id);
create index workout_exercises_program_exercise_slot_id_idx
  on public.workout_exercises (program_exercise_slot_id);
create index workout_exercises_rotation_assignment_id_idx
  on public.workout_exercises (rotation_assignment_id);

-- New tables are private by default and writable only by their owner.
do $$
declare
  t text;
  tables text[] := array[
    'prescription_templates', 'physique_programming_profiles',
    'program_exercise_slots', 'program_slot_pool_members',
    'rotation_assignments', 'exercise_preferences', 'gym_equipment'
  ];
begin
  foreach t in array tables loop
    execute format('alter table public.%I enable row level security', t);
    execute format(
      'create policy %I on public.%I for select to authenticated using ((select auth.uid()) = user_id)',
      t || '_select_own', t
    );
    execute format(
      'create policy %I on public.%I for insert to authenticated with check ((select auth.uid()) = user_id)',
      t || '_insert_own', t
    );
    execute format(
      'create policy %I on public.%I for update to authenticated using ((select auth.uid()) = user_id) with check ((select auth.uid()) = user_id)',
      t || '_update_own', t
    );
    execute format(
      'create policy %I on public.%I for delete to authenticated using ((select auth.uid()) = user_id)',
      t || '_delete_own', t
    );
    execute format('grant select, insert, update, delete on public.%I to authenticated', t);
    execute format(
      'create trigger %I before insert or update on public.%I for each row execute function public.set_updated_at()',
      't_set_updated_at_' || t, t
    );
  end loop;
end $$;
