-- Web track W3: synced preferences (local schema v53).
--
-- The profile, meal slots, nutrition goals, units, colour theme and similar
-- settings live in SharedPreferences on the phone and never left it, so a
-- second device — the web app above all — started from onboarding. Selected
-- keys are now mirrored into this table by the app's synced-preferences
-- bridge (lib/data/sync/preferences/) and pulled like any other synced row.
--
-- `id` is a UUID v5 of (account, key), the same on every device, so all of
-- them upsert one row per key; unique(user_id, pref_key) backs that up.
-- `value_json` is a typed envelope ({"t": "double", "v": 72.5}) so an int and
-- a double survive the round trip. Removing a preference sets deleted_at.
--
-- Same wiring as every post-hoc synced table (0014 joint_pain_logs): owner-only
-- RLS, the updated_at clock and tombstone triggers, realtime, and the pull
-- index 0017 gives every synced table.

create table user_preferences (
  id uuid primary key,
  user_id uuid not null references auth.users(id) on delete cascade,
  pref_key text not null,
  value_json text not null,
  updated_at timestamptz not null default now(),
  deleted_at timestamptz,
  unique (user_id, pref_key)
);

alter table user_preferences enable row level security;

create policy user_preferences_select_own
  on user_preferences for select using (user_id = auth.uid());
create policy user_preferences_insert_own
  on user_preferences for insert with check (user_id = auth.uid());
create policy user_preferences_update_own
  on user_preferences for update using (user_id = auth.uid()) with check (user_id = auth.uid());
create policy user_preferences_delete_own
  on user_preferences for delete using (user_id = auth.uid());

create trigger t_set_updated_at_user_preferences
  before insert or update on user_preferences
  for each row execute function set_updated_at();

create trigger t_record_tombstone_user_preferences
  after delete on user_preferences
  for each row execute function public.record_sync_tombstone();

alter publication supabase_realtime add table public.user_preferences;

create index if not exists user_preferences_user_updated_id_idx
  on public.user_preferences (user_id, updated_at, id);
