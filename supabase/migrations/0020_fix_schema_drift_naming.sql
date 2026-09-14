-- Systematic audit of every synced Drift table against its Postgres
-- counterpart (all 47 tables in `sync_table_specs.dart`'s `syncTableSpecs`,
-- cross-checked against `drift_schemas/drift_schema_v40.json`). Same failure
-- mode as `0019_fix_foods_per100g_column_names.sql`: `SyncService` forwards
-- Drift's column names verbatim, so any spelling mismatch or genuinely
-- missing column makes PostgREST answer PGRST204 and the outbox quarantines
-- the row after 8 attempts.
--
-- Two real defects found beyond the eight already fixed by 0019:

-- ── program_day_exercises.percent_of1_rm ───────────────────────────────────
--
-- drift's default naming strategy splits `percentOf1Rm` at the digit ->
-- uppercase-letter boundary into tokens `percent`, `of1`, `rm`, producing
-- `percent_of1_rm` (no underscore between `of` and `1`). 0002 hand-wrote the
-- Postgres side as `percent_of_1rm` (underscore before `1rm`) instead. Every
-- push of a `program_day_exercises` row with a set percentage has been
-- failing with PGRST204 ("Could not find the 'percent_of1_rm' column of
-- 'program_day_exercises' in the schema cache") since 0002.
alter table public.program_day_exercises
  rename column percent_of_1rm to percent_of1_rm;

-- ── nutrition_targets.fiber_g ───────────────────────────────────────────────
--
-- drift's local `NutritionTargets` table (`lib/data/local/tables.dart`) has
-- a nullable `fiberG` column (`fiber_g` locally) with no Postgres counterpart
-- at all — not a naming mismatch, a column 0001 never created. Every push of
-- a `nutrition_targets` row that has a fiber target set fails with PGRST204
-- ("Could not find the 'fiber_g' column of 'nutrition_targets' in the schema
-- cache"). Nullable integer with no default, matching the local column and
-- the sibling macro columns' shape (`kcal`, `protein_g`, `carbs_g`, `fat_g`).
alter table public.nutrition_targets
  add column if not exists fiber_g integer;
