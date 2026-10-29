-- Program-builder (v39) tables: cross-device delete propagation and realtime.
--
-- 20260908200007_program_builder_v39.sql gave these seven tables RLS and the
-- updated_at clock but not the two things 0005 wired onto every table that
-- existed then:
--
--   * the tombstone trigger. Deletes of these rows are HARD deletes (the
--     planner regenerates a program's slots by deleting and re-inserting them),
--     and a delta pull (`where updated_at > cursor`) can never see a row that
--     no longer exists. Without a tombstone every other device keeps the stale
--     slot forever, and the regenerated slot then collides with it on the
--     local `(program_id, slot_key)` unique index, so the pull cannot apply
--     and the table's cursor stalls.
--   * membership of the `supabase_realtime` publication. SyncService opens a
--     channel for every synced table; for these seven it has been dead, so
--     the 5-minute poll was the only path. Realtime only ever triggers a
--     delta pull — no payload is applied directly.
--
-- Idempotent: safe to run on a project where either part is already there.

do $$
declare
  t text;
  tables text[] := array[
    'prescription_templates', 'physique_programming_profiles',
    'program_exercise_slots', 'program_slot_pool_members',
    'rotation_assignments', 'exercise_preferences', 'gym_equipment'
  ];
begin
  foreach t in array tables loop
    if not exists (
      select 1
      from pg_trigger
      where tgname = 't_record_tombstone_' || t
        and tgrelid = format('public.%I', t)::regclass
    ) then
      execute format(
        'create trigger %I after delete on public.%I for each row execute function public.record_sync_tombstone()',
        't_record_tombstone_' || t, t
      );
    end if;

    if not exists (
      select 1
      from pg_publication_tables
      where pubname = 'supabase_realtime'
        and schemaname = 'public'
        and tablename = t
    ) then
      execute format('alter publication supabase_realtime add table public.%I', t);
    end if;
  end loop;
end $$;
