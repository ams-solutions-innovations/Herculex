-- Indeksi za sync engine.
--
-- Do te migracije je celotna shema imela natanko EN indeks
-- (`sync_tombstones_user_deleted_at_idx` iz 0005). Vse ostalo se je zanašalo
-- na primarne kljuce, ki so `id uuid` — torej neuporabni za obe poizvedbi, ki
-- ju sync engine dejansko dela.
--
-- 1. `SupabaseSyncBackendService.pull()`:
--        select * from <t> where user_id = ? and updated_at > ? order by updated_at, id
--    Brez indeksa je to sequential scan cele tabele, na 40 tabelah, na vsakih
--    5 minut, za vsakega uporabnika. Composite (user_id, updated_at) pokrije
--    tako enakost kot range v enem obhodu; `id` je dodan kot tretji stolpec,
--    ker je po popravku paginacije del ORDER BY (keyset tie-break).
--
-- 2. Vsak `on delete cascade` FK brez indeksa na otroku pomeni, da mora
--    Postgres ob brisanju starsa (ali ob brisanju racuna, kjer kaskada tece
--    skozi vseh 40 tabel) narediti sequential scan otroka na FK edge. Brisanje
--    racuna je bilo do zdaj O(velikost cele baze).
--
-- Vsi indeksi so `if not exists`, torej je migracija idempotentna in varna za
-- ponoven zagon.
--
-- OPOMBA o zaklepanju: `create index` (brez CONCURRENTLY) vzame SHARE lock na
-- tabeli za cas gradnje. `supabase db push` vsako migracijo ovije v
-- transakcijo, CONCURRENTLY pa v transakciji ni dovoljen, zato tu ni
-- uporabljen. Pri trenutni kolicini podatkov je gradnja milisekunde. Ce se ta
-- datoteka kdaj aplicira na projekt z resnimi podatki, jo razbij v locene
-- `create index concurrently` stavke, pognane izven `db push`.

-- ── 1. Delta-pull indeksi ──────────────────────────────────────────────
do $$
declare
  t text;
  tables text[] := array[
    'gyms', 'workout_folders', 'exercise_catalog', 'foods',
    'recipes', 'accessories', 'bands', 'nutrition_targets',
    'diet_schedules', 'carb_cycle_plans', 'fasting_sessions', 'fasting_schedules',
    'body_measurements', 'cycle_logs', 'cycle_settings', 'joint_pain_logs',
    'exercise_rotations', 'daily_summaries', 'external_events', 'micro_workouts',
    'recipe_ingredients', 'workout_templates', 'workout_circuits', 'workout_sessions',
    'programs', 'exercise_progressions', 'machine_settings', 'food_entries',
    'workout_exercises', 'template_exercises', 'circuit_exercises', 'program_weeks',
    'rotation_members', 'set_entries', 'template_sets', 'program_days',
    'program_day_exercises', 'scheduled_workouts', 'set_accessories', 'set_bands'
  ];
begin
  foreach t in array tables loop
    execute format(
      'create index if not exists %I on public.%I (user_id, updated_at, id)',
      t || '_user_updated_idx', t
    );
  end loop;
end $$;

-- ── 2. FK indeksi (vsak non-user_id FK na sinhronizirani tabeli) ───────
create index if not exists micro_workouts_exercise_catalog_id_idx
  on public.micro_workouts (exercise_catalog_id);
create index if not exists recipe_ingredients_recipe_id_idx
  on public.recipe_ingredients (recipe_id);
create index if not exists recipe_ingredients_food_catalogue_id_idx
  on public.recipe_ingredients (food_catalogue_id);
create index if not exists workout_templates_folder_id_idx
  on public.workout_templates (folder_id);
create index if not exists workout_sessions_gym_id_idx
  on public.workout_sessions (gym_id);
create index if not exists workout_sessions_micro_workout_id_idx
  on public.workout_sessions (micro_workout_id);
create index if not exists exercise_progressions_exercise_catalog_id_idx
  on public.exercise_progressions (exercise_catalog_id);
create index if not exists machine_settings_exercise_catalog_id_idx
  on public.machine_settings (exercise_catalog_id);
create index if not exists machine_settings_gym_id_idx
  on public.machine_settings (gym_id);
create index if not exists food_entries_food_catalogue_id_idx
  on public.food_entries (food_catalogue_id);
create index if not exists food_entries_recipe_id_idx
  on public.food_entries (recipe_id);
create index if not exists workout_exercises_session_id_idx
  on public.workout_exercises (session_id);
create index if not exists workout_exercises_exercise_catalog_id_idx
  on public.workout_exercises (exercise_catalog_id);
create index if not exists template_exercises_template_id_idx
  on public.template_exercises (template_id);
create index if not exists template_exercises_exercise_catalog_id_idx
  on public.template_exercises (exercise_catalog_id);
create index if not exists program_weeks_program_id_idx
  on public.program_weeks (program_id);
create index if not exists rotation_members_rotation_id_idx
  on public.rotation_members (rotation_id);
create index if not exists rotation_members_exercise_catalog_id_idx
  on public.rotation_members (exercise_catalog_id);
create index if not exists set_entries_workout_exercise_id_idx
  on public.set_entries (workout_exercise_id);
create index if not exists template_sets_template_exercise_id_idx
  on public.template_sets (template_exercise_id);
create index if not exists program_days_program_week_id_idx
  on public.program_days (program_week_id);
create index if not exists program_days_template_id_idx
  on public.program_days (template_id);
create index if not exists program_day_exercises_program_day_id_idx
  on public.program_day_exercises (program_day_id);
create index if not exists program_day_exercises_exercise_catalog_id_idx
  on public.program_day_exercises (exercise_catalog_id);
create index if not exists program_day_exercises_rotation_id_idx
  on public.program_day_exercises (rotation_id);
create index if not exists scheduled_workouts_program_day_id_idx
  on public.scheduled_workouts (program_day_id);
create index if not exists scheduled_workouts_completed_session_id_idx
  on public.scheduled_workouts (completed_session_id);
create index if not exists scheduled_workouts_program_id_idx
  on public.scheduled_workouts (program_id);
create index if not exists scheduled_workouts_template_id_override_idx
  on public.scheduled_workouts (template_id_override);
create index if not exists set_accessories_set_entry_id_idx
  on public.set_accessories (set_entry_id);
create index if not exists set_accessories_accessory_id_idx
  on public.set_accessories (accessory_id);
create index if not exists set_bands_set_entry_id_idx
  on public.set_bands (set_entry_id);
create index if not exists set_bands_band_id_idx
  on public.set_bands (band_id);
create index if not exists circuit_exercises_circuit_id_idx
  on public.circuit_exercises (circuit_id);
create index if not exists circuit_exercises_exercise_catalog_id_idx
  on public.circuit_exercises (exercise_catalog_id);

-- ── 3. Skupni katalog izdelkov ─────────────────────────────────────────
--
-- `contributed_by` je uporabljen samo pri rate-limit preverjanju (glej
-- 0018), `name` pri iskanju izdelka po imenu namesto po barcode.
create index if not exists product_catalogue_contributed_by_idx
  on public.product_catalogue (contributed_by, created_at desc);

create extension if not exists pg_trgm;

create index if not exists product_catalogue_name_trgm_idx
  on public.product_catalogue using gin (name gin_trgm_ops);

create index if not exists product_catalogue_brand_idx
  on public.product_catalogue (brand)
  where brand is not null;

-- ── 4. Buddy ───────────────────────────────────────────────────────────
--
-- `buddy_session_events` je ze pokrit s svojim composite PK
-- (buddy_session_id, seq) — glej opombo v 0011. Manjkata pa poti, ki ju
-- `is_buddy_participant()` in cleanup job dejansko delata.
create index if not exists buddy_participants_user_idx
  on public.buddy_participants (user_id) where left_at is null;

create index if not exists buddy_join_tokens_expires_idx
  on public.buddy_join_tokens (expires_at);
