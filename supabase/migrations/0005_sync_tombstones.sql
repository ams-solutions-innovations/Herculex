-- Phase 10 sync — cross-device propagation of HARD deletes.
--
-- Delta pull is `where updated_at > cursor`, so a hard-deleted row can never
-- appear in any future pull: it is gone. Every device that already holds a
-- copy would keep it forever, and its next local edit would re-upload it.
-- This table is the durable record of "row X of type T stopped existing at
-- time D" that a delta pull can actually see.
--
-- Soft deletes (`deleted_at` set, pushed as a tombstoned upsert) still travel
-- through the normal row pull and never reach this table.

create table public.sync_tombstones (
  entity_type text        not null,
  entity_id   uuid        not null,
  -- Deliberately NOT a FK to auth.users: referential-integrity cascade
  -- deletes the parent auth.users row *before* running the cascade actions on
  -- the child tables, so a tombstone inserted by the child delete would
  -- reference an already-gone user and abort account deletion. Orphans are
  -- swept by the retention job in 0006.
  user_id     uuid        not null,
  deleted_at  timestamptz not null default now(),
  primary key (entity_type, entity_id)
);

-- The only access path: `where user_id = ? and deleted_at > cursor`,
-- ordered by deleted_at.
create index sync_tombstones_user_deleted_at_idx
  on public.sync_tombstones (user_id, deleted_at);

alter table public.sync_tombstones enable row level security;

-- Read-only for clients. There is deliberately no insert/update/delete
-- policy: only the security-definer trigger below ever writes here, so a
-- client cannot forge a tombstone for a row it does not own — which would be
-- a remote-triggered delete on every other device.
create policy sync_tombstones_select_own
  on public.sync_tombstones for select using (user_id = auth.uid());

revoke insert, update, delete on public.sync_tombstones from anon, authenticated;

-- security definer: with RLS on and no insert policy, a security-invoker
-- trigger would make every DELETE fail. definer is safe here because the
-- function writes old.user_id verbatim and the caller could only have deleted
-- a row it owns (each table's *_delete_own policy in 0003).
--
-- `set search_path = ''` + fully qualified names: a definer function with a
-- mutable search_path is a privilege-escalation vector, not just a lint.
create function public.record_sync_tombstone()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  insert into public.sync_tombstones (entity_type, entity_id, user_id, deleted_at)
  values (tg_table_name, old.id, old.user_id, now())
  on conflict (entity_type, entity_id)
    do update set deleted_at = excluded.deleted_at;
  return old;
end;
$$;

-- `from public` alone is not enough: PostgREST exposes anything the anon /
-- authenticated roles hold EXECUTE on at /rest/v1/rpc/..., and those roles
-- carry their own grants. (A direct RPC call would fail anyway — a trigger
-- function can only be invoked as a trigger — but an unauthenticated,
-- security-definer entry point in the exposed API schema has no business
-- existing.)
revoke execute on function public.record_sync_tombstone() from public, anon, authenticated;

-- The same advisor finding applies to 0004's clock trigger, which predates
-- this rule. Body needs no change (it only touches `new`), so setting the
-- search_path on the existing function is enough.
alter function public.set_updated_at() set search_path = '';

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
      'create trigger %I after delete on %I for each row execute function public.record_sync_tombstone()',
      't_record_tombstone_' || t, t
    );
  end loop;

  -- Realtime. `SyncService` already opens a channel per synced table plus one
  -- for tombstones, but none of these tables had ever been added to the
  -- publication — so every one of those subscriptions was silently dead and
  -- the 5-minute poll was doing all the work. Hints only ever trigger a delta
  -- pull; no payload is applied directly.
  foreach t in array array_append(tables, 'sync_tombstones') loop
    if not exists (
      select 1 from pg_publication_tables
      where pubname = 'supabase_realtime' and schemaname = 'public' and tablename = t
    ) then
      execute format('alter publication supabase_realtime add table public.%I', t);
    end if;
  end loop;
end $$;
