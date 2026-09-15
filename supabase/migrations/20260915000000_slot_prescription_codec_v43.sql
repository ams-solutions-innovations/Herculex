-- SlotPrescriptionCodec storage + technique-gating snapshot mirrors local Drift v43.
alter table public.program_day_exercises
  add column if not exists prescription_codec_json text;

alter table public.programs
  add column if not exists allow_time_saving_set_techniques boolean not null default false;

alter table public.workout_exercises
  add column if not exists planned_allows_advanced_techniques boolean not null default false;
