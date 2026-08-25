-- Recovery page: joint-pain flags. One row per status change (event log,
-- same shape as cycle_logs) rather than one row per day — a joint's current
-- status is its most recent row. Same shape as every other post-hoc synced
-- table (0009 fasting_schedules, 0011 buddy_sessions) — a single new table
-- added after the fact, so its RLS/trigger/tombstone/realtime wiring is
-- spelled out directly here instead of folded into the original per-table
-- loops in 0003-0005, which already ran.

create table joint_pain_logs (
  id uuid primary key,
  user_id uuid not null references auth.users(id) on delete cascade,
  date_iso text not null,
  logged_at timestamptz not null default now(),
  joint text not null,
  severity integer not null default 1,
  note text,
  updated_at timestamptz not null default now(),
  deleted_at timestamptz
);

alter table joint_pain_logs enable row level security;

create policy joint_pain_logs_select_own
  on joint_pain_logs for select using (user_id = auth.uid());
create policy joint_pain_logs_insert_own
  on joint_pain_logs for insert with check (user_id = auth.uid());
create policy joint_pain_logs_update_own
  on joint_pain_logs for update using (user_id = auth.uid()) with check (user_id = auth.uid());
create policy joint_pain_logs_delete_own
  on joint_pain_logs for delete using (user_id = auth.uid());

-- Reuses the two trigger functions 0004/0005 already defined.
create trigger t_set_updated_at_joint_pain_logs
  before insert or update on joint_pain_logs
  for each row execute function set_updated_at();

create trigger t_record_tombstone_joint_pain_logs
  after delete on joint_pain_logs
  for each row execute function public.record_sync_tombstone();

alter publication supabase_realtime add table public.joint_pain_logs;
