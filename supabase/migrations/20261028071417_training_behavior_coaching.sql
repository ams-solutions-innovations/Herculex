-- Portable workout corrections and opt-in behavioural coaching, Drift v54.
alter table public.scheduled_workouts alter column program_day_id drop not null;
alter table public.scheduled_workouts add column if not exists one_off_plan_json text;
alter table public.scheduled_workouts add constraint scheduled_workouts_has_plan
  check (program_day_id is not null or one_off_plan_json is not null);

create table public.exercise_history_transfers (
  id uuid primary key, user_id uuid not null references auth.users(id) on delete cascade,
  payload_json text not null, created_at timestamptz not null, undone_at timestamptz,
  updated_at timestamptz not null default now(), deleted_at timestamptz
);
create table public.workout_behavior_snapshots (
  id uuid primary key, user_id uuid not null references auth.users(id) on delete cascade,
  session_id uuid not null references public.workout_sessions(id) on delete cascade,
  snapshot_json text not null, captured_at timestamptz not null,
  updated_at timestamptz not null default now(), deleted_at timestamptz,
  unique (session_id)
);
create table public.training_coaching_proposals (
  id uuid primary key, user_id uuid not null references auth.users(id) on delete cascade,
  program_id uuid references public.programs(id) on delete cascade,
  source_session_id uuid references public.workout_sessions(id) on delete cascade,
  kind text not null, proposal_key text not null, status text not null default 'proposed',
  payload_json text not null, created_at timestamptz not null,
  decided_at timestamptz, expires_at timestamptz, snoozed_until timestamptz,
  updated_at timestamptz not null default now(), deleted_at timestamptz,
  unique (user_id, proposal_key)
);
create table public.training_coaching_overrides (
  id uuid primary key, user_id uuid not null references auth.users(id) on delete cascade,
  proposal_id uuid not null references public.training_coaching_proposals(id) on delete cascade,
  schedule_id uuid not null references public.scheduled_workouts(id) on delete cascade,
  plan_json text not null, original_plan_json text not null,
  updated_at timestamptz not null default now(), deleted_at timestamptz,
  unique (proposal_id, schedule_id)
);

-- Foreign-key lookups used by parent deletion and plan resolution.
create index training_coaching_proposals_program_idx
  on public.training_coaching_proposals(program_id);
create index training_coaching_proposals_source_session_idx
  on public.training_coaching_proposals(source_session_id);
create index training_coaching_overrides_schedule_idx
  on public.training_coaching_overrides(schedule_id);

alter table public.exercise_history_transfers enable row level security;
grant select, insert, update, delete on public.exercise_history_transfers to authenticated;
create policy exercise_history_transfers_select_own on public.exercise_history_transfers for select to authenticated using (user_id = (select auth.uid()));
create policy exercise_history_transfers_insert_own on public.exercise_history_transfers for insert to authenticated with check (user_id = (select auth.uid()));
create policy exercise_history_transfers_update_own on public.exercise_history_transfers for update to authenticated using (user_id = (select auth.uid())) with check (user_id = (select auth.uid()));
create policy exercise_history_transfers_delete_own on public.exercise_history_transfers for delete to authenticated using (user_id = (select auth.uid()));
create index exercise_history_transfers_user_updated_idx on public.exercise_history_transfers(user_id, updated_at, id);
create trigger t_set_updated_at_exercise_history_transfers before insert or update on public.exercise_history_transfers
  for each row execute function public.set_updated_at();
create trigger t_record_tombstone_exercise_history_transfers after delete on public.exercise_history_transfers
  for each row execute function public.record_sync_tombstone();
alter publication supabase_realtime add table public.exercise_history_transfers;

alter table public.workout_behavior_snapshots enable row level security;
grant select, insert, update, delete on public.workout_behavior_snapshots to authenticated;
create policy workout_behavior_snapshots_select_own on public.workout_behavior_snapshots for select to authenticated using (user_id = (select auth.uid()));
create policy workout_behavior_snapshots_insert_own on public.workout_behavior_snapshots for insert to authenticated with check (user_id = (select auth.uid()) and exists (select 1 from public.workout_sessions s where s.id = session_id and s.user_id = (select auth.uid())));
create policy workout_behavior_snapshots_update_own on public.workout_behavior_snapshots for update to authenticated using (user_id = (select auth.uid())) with check (user_id = (select auth.uid()) and exists (select 1 from public.workout_sessions s where s.id = session_id and s.user_id = (select auth.uid())));
create policy workout_behavior_snapshots_delete_own on public.workout_behavior_snapshots for delete to authenticated using (user_id = (select auth.uid()));
create index workout_behavior_snapshots_user_updated_idx on public.workout_behavior_snapshots(user_id, updated_at, id);
create trigger t_set_updated_at_workout_behavior_snapshots before insert or update on public.workout_behavior_snapshots
  for each row execute function public.set_updated_at();
create trigger t_record_tombstone_workout_behavior_snapshots after delete on public.workout_behavior_snapshots
  for each row execute function public.record_sync_tombstone();
alter publication supabase_realtime add table public.workout_behavior_snapshots;

alter table public.training_coaching_proposals enable row level security;
grant select, insert, update, delete on public.training_coaching_proposals to authenticated;
create policy training_coaching_proposals_select_own on public.training_coaching_proposals for select to authenticated using (user_id = (select auth.uid()));
create policy training_coaching_proposals_insert_own on public.training_coaching_proposals for insert to authenticated with check (user_id = (select auth.uid()) and (program_id is null or exists (select 1 from public.programs p where p.id = program_id and p.user_id = (select auth.uid()))) and (source_session_id is null or exists (select 1 from public.workout_sessions s where s.id = source_session_id and s.user_id = (select auth.uid()))));
create policy training_coaching_proposals_update_own on public.training_coaching_proposals for update to authenticated using (user_id = (select auth.uid())) with check (user_id = (select auth.uid()) and (program_id is null or exists (select 1 from public.programs p where p.id = program_id and p.user_id = (select auth.uid()))) and (source_session_id is null or exists (select 1 from public.workout_sessions s where s.id = source_session_id and s.user_id = (select auth.uid()))));
create policy training_coaching_proposals_delete_own on public.training_coaching_proposals for delete to authenticated using (user_id = (select auth.uid()));
create index training_coaching_proposals_user_updated_idx on public.training_coaching_proposals(user_id, updated_at, id);
create trigger t_set_updated_at_training_coaching_proposals before insert or update on public.training_coaching_proposals
  for each row execute function public.set_updated_at();
create trigger t_record_tombstone_training_coaching_proposals after delete on public.training_coaching_proposals
  for each row execute function public.record_sync_tombstone();
alter publication supabase_realtime add table public.training_coaching_proposals;

alter table public.training_coaching_overrides enable row level security;
grant select, insert, update, delete on public.training_coaching_overrides to authenticated;
create policy training_coaching_overrides_select_own on public.training_coaching_overrides for select to authenticated using (user_id = (select auth.uid()));
create policy training_coaching_overrides_insert_own on public.training_coaching_overrides for insert to authenticated with check (user_id = (select auth.uid()) and exists (select 1 from public.training_coaching_proposals p where p.id = proposal_id and p.user_id = (select auth.uid())) and exists (select 1 from public.scheduled_workouts s where s.id = schedule_id and s.user_id = (select auth.uid())));
create policy training_coaching_overrides_update_own on public.training_coaching_overrides for update to authenticated using (user_id = (select auth.uid())) with check (user_id = (select auth.uid()) and exists (select 1 from public.training_coaching_proposals p where p.id = proposal_id and p.user_id = (select auth.uid())) and exists (select 1 from public.scheduled_workouts s where s.id = schedule_id and s.user_id = (select auth.uid())));
create policy training_coaching_overrides_delete_own on public.training_coaching_overrides for delete to authenticated using (user_id = (select auth.uid()));
create index training_coaching_overrides_user_updated_idx on public.training_coaching_overrides(user_id, updated_at, id);
create trigger t_set_updated_at_training_coaching_overrides before insert or update on public.training_coaching_overrides
  for each row execute function public.set_updated_at();
create trigger t_record_tombstone_training_coaching_overrides after delete on public.training_coaching_overrides
  for each row execute function public.record_sync_tombstone();
alter publication supabase_realtime add table public.training_coaching_overrides;
