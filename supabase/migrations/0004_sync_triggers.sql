-- Phase 10 sync — `updated_at` is the authoritative LWW clock; it must only
-- ever be set here, server-side, never trusted from a client payload (an
-- `upsert(...)` from the client should never include this column).
create or replace function set_updated_at()
returns trigger
language plpgsql
as $$
begin
  new.updated_at := now();
  return new;
end;
$$;

do $$
declare
  t text;
  tables text[] := array[
    'gyms', 'workout_folders', 'exercise_catalog', 'foods', 'recipes',
    'accessories', 'bands', 'nutrition_targets', 'diet_schedules',
    'carb_cycle_plans', 'fasting_sessions', 'body_measurements',
    'cycle_logs', 'cycle_settings', 'exercise_rotations', 'daily_summaries',
    'external_events', 'micro_workouts', 'recipe_ingredients',
    'workout_templates', 'workout_sessions', 'programs',
    'exercise_progressions', 'machine_settings', 'food_entries',
    'workout_exercises', 'template_exercises', 'program_weeks',
    'rotation_members', 'set_entries', 'template_sets', 'program_days',
    'program_day_exercises', 'scheduled_workouts', 'set_accessories',
    'set_bands'
  ];
begin
  foreach t in array tables loop
    execute format(
      'create trigger %I before insert or update on %I for each row execute function set_updated_at()',
      't_set_updated_at_' || t, t
    );
  end loop;
end $$;
