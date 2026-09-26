-- Session-segment tagging (warmup/skill/strength/metcon/cooldown) plus a
-- program_day_exercises-level superset/metcon group id, mirrors local Drift v44.
alter table public.program_exercise_slots
  add column if not exists session_segment text;

alter table public.program_day_exercises
  add column if not exists session_segment text;

alter table public.program_day_exercises
  add column if not exists superset_group integer;

alter table public.workout_exercises
  add column if not exists planned_session_segment text;
