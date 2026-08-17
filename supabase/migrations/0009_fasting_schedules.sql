-- UI rework Phase 6: recurring fasting "notify to start" schedules.
-- Same shape as every other Phase 10 synced table (0001-0005) — a single
-- new table added after the fact, so its RLS/trigger/tombstone/realtime
-- wiring is spelled out directly here instead of folded into the original
-- per-table loops in 0003-0005, which already ran.

create table fasting_schedules (
  id uuid primary key,
  user_id uuid not null references auth.users(id) on delete cascade,
  plan_name text not null,
  custom_target_seconds integer,
  days_of_week integer not null,
  start_time_minutes integer not null,
  enabled boolean not null default true,
  auto_start boolean not null default false,
  updated_at timestamptz not null default now(),
  deleted_at timestamptz
);

alter table fasting_schedules enable row level security;

create policy fasting_schedules_select_own
  on fasting_schedules for select using (user_id = auth.uid());
create policy fasting_schedules_insert_own
  on fasting_schedules for insert with check (user_id = auth.uid());
create policy fasting_schedules_update_own
  on fasting_schedules for update using (user_id = auth.uid()) with check (user_id = auth.uid());
create policy fasting_schedules_delete_own
  on fasting_schedules for delete using (user_id = auth.uid());

-- Reuses the two trigger functions 0004/0005 already defined.
create trigger t_set_updated_at_fasting_schedules
  before insert or update on fasting_schedules
  for each row execute function set_updated_at();

create trigger t_record_tombstone_fasting_schedules
  after delete on fasting_schedules
  for each row execute function public.record_sync_tombstone();

alter publication supabase_realtime add table public.fasting_schedules;
