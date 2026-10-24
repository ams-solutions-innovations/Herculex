-- Synced counterpart of local Drift schema v49.  A confirmed adaptation is a
-- user decision, so it must travel with the schedule rather than being
-- recalculated independently on another device.

create table adaptation_proposals (
  id uuid primary key,
  user_id uuid not null references auth.users(id) on delete cascade,
  program_id uuid not null references programs(id) on delete cascade,
  source_schedule_id uuid references scheduled_workouts(id) on delete set null,
  source_session_id uuid references workout_sessions(id) on delete set null,
  week_start_iso text not null,
  trigger text not null,
  decision text not null default 'proposed',
  reason text not null,
  input_fingerprint text not null,
  proposal_json text not null,
  decided_at timestamptz,
  updated_at timestamptz not null default now(),
  deleted_at timestamptz
);

create table adaptation_overrides (
  id uuid primary key,
  user_id uuid not null references auth.users(id) on delete cascade,
  proposal_id uuid not null references adaptation_proposals(id) on delete cascade,
  schedule_id uuid not null references scheduled_workouts(id) on delete cascade,
  plan_json text not null,
  updated_at timestamptz not null default now(),
  deleted_at timestamptz,
  unique (proposal_id, schedule_id)
);

alter table adaptation_proposals enable row level security;
alter table adaptation_overrides enable row level security;

create policy adaptation_proposals_select_own on adaptation_proposals
  for select using (user_id = auth.uid());
create policy adaptation_proposals_insert_own on adaptation_proposals
  for insert with check (user_id = auth.uid());
create policy adaptation_proposals_update_own on adaptation_proposals
  for update using (user_id = auth.uid()) with check (user_id = auth.uid());
create policy adaptation_proposals_delete_own on adaptation_proposals
  for delete using (user_id = auth.uid());

create policy adaptation_overrides_select_own on adaptation_overrides
  for select using (user_id = auth.uid());
create policy adaptation_overrides_insert_own on adaptation_overrides
  for insert with check (user_id = auth.uid());
create policy adaptation_overrides_update_own on adaptation_overrides
  for update using (user_id = auth.uid()) with check (user_id = auth.uid());
create policy adaptation_overrides_delete_own on adaptation_overrides
  for delete using (user_id = auth.uid());

create trigger t_set_updated_at_adaptation_proposals
  before insert or update on adaptation_proposals
  for each row execute function set_updated_at();
create trigger t_record_tombstone_adaptation_proposals
  after delete on adaptation_proposals
  for each row execute function public.record_sync_tombstone();
create trigger t_set_updated_at_adaptation_overrides
  before insert or update on adaptation_overrides
  for each row execute function set_updated_at();
create trigger t_record_tombstone_adaptation_overrides
  after delete on adaptation_overrides
  for each row execute function public.record_sync_tombstone();

alter publication supabase_realtime add table public.adaptation_proposals;
alter publication supabase_realtime add table public.adaptation_overrides;

create index adaptation_proposals_user_updated_idx
  on adaptation_proposals (user_id, updated_at, id);
create index adaptation_overrides_user_updated_idx
  on adaptation_overrides (user_id, updated_at, id);
