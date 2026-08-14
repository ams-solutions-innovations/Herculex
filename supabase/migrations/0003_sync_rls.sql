-- Phase 10 sync — RLS. Every synced table is gated by the same rule:
-- a row is only visible/writable by the user_id that owns it.
--
-- Generated via a loop over the full table list rather than 35 x 4 hand
-- written statements — same policies either way, just less copy-paste risk.
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
    execute format('alter table %I enable row level security', t);

    execute format(
      'create policy %I on %I for select using (user_id = auth.uid())',
      t || '_select_own', t
    );
    execute format(
      'create policy %I on %I for insert with check (user_id = auth.uid())',
      t || '_insert_own', t
    );
    execute format(
      'create policy %I on %I for update using (user_id = auth.uid()) with check (user_id = auth.uid())',
      t || '_update_own', t
    );
    execute format(
      'create policy %I on %I for delete using (user_id = auth.uid())',
      t || '_delete_own', t
    );
  end loop;
end $$;
