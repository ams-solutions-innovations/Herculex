-- Phase 11 (gym-buddy-live-workout) — BUD-01, BUD-04, BUD-05, BUD-06.
--
-- Self-contained migration, following the shape of
-- 0009_fasting_schedules.sql: it spells out its own tables, RLS, triggers
-- and RPCs rather than editing the 0003/0004/0005 DO-block loops that
-- already ran against the live project.
--
-- Two rules govern every statement in this file:
--   1. Nothing here alters, drops or replaces any policy created by
--      0003_sync_rls.sql. The only statement in this file that names one of
--      that migration's tables at all is an additive `add column`.
--   2. Cross-user visibility is confined to the four tables created below.
--      No policy here grants a partner read access to any other user's
--      training, nutrition, measurement or biometric data.
--
-- Applying this file to a live project is plan 11-05, not this plan.

-- Preflight: realtime.send's signature is only described in prose by the
-- Supabase docs — no page prints the actual `create function` line — so
-- this guard turns a wrong assumption into a named failure at db push time
-- instead of a broadcast trigger that silently never fires.
do $$
begin
  if to_regprocedure('realtime.send(jsonb, text, text, boolean)') is null then
    raise exception 'expected realtime.send(payload jsonb, event text, topic text, private boolean) not found on this project. Run select pg_get_functiondef(''realtime.send''::regproc) against the target project and update the call site in this migration''s buddy_broadcast_event() to match the real signature before re-running db push.';
  end if;
end;
$$;

-- ── Tables ──────────────────────────────────────────────────────────────

create table public.buddy_sessions (
  id          uuid primary key default gen_random_uuid(),
  created_by  uuid not null references auth.users(id) on delete cascade,
  created_at  timestamptz not null default now(),
  ended_at    timestamptz,
  -- Per-session monotonic append counter. Deliberately NOT an auto-
  -- increment column: those hand out their value before commit and never
  -- roll it back, so a consumer filtering "where seq > last_seen" could
  -- permanently skip an event whose transaction committed later than a
  -- higher-numbered one. buddy_append_event() advances this under
  -- `for update` instead, which is gapless and commit-ordered at the
  -- two-writer scale this table ever serves.
  next_seq    bigint not null default 1,
  -- Recommended alternative to parsing the channel topic with a substring
  -- and a cast in the realtime.messages policies below: a client can
  -- request any topic string it likes, and a parse of a hostile string
  -- must never be able to throw. Comparing against this generated column
  -- avoids the cast entirely.
  topic       text generated always as ('buddy:' || id::text) stored
);

create table public.buddy_participants (
  buddy_session_id     uuid not null references public.buddy_sessions(id) on delete cascade,
  user_id               uuid not null references auth.users(id) on delete cascade,
  -- Bare identifier only — links to WorkoutSessions.sessionUuid on that
  -- participant's own device. It grants no read access to that table;
  -- ownership there is still gated solely by the frozen policies in
  -- 0003_sync_rls.sql.
  workout_session_uuid  uuid not null,
  -- Minimal display identity, denormalised by the joining user themselves
  -- at join time. There is no server-side profiles table in this project,
  -- so this is the only source for a partner's name/avatar.
  display_name          text,
  avatar_url             text,
  joined_at              timestamptz not null default now(),
  left_at                timestamptz,
  primary key (buddy_session_id, user_id)
);

create table public.buddy_session_events (
  buddy_session_id uuid        not null references public.buddy_sessions(id) on delete cascade,
  -- Assigned by buddy_append_event() under a row lock on buddy_sessions —
  -- never a database auto-increment type. Auto-increment values are handed
  -- out before commit and are never rolled back, so a consumer polling
  -- "where seq > last_seen" could permanently skip an event whose
  -- transaction committed out of allocation order. A hand-managed counter,
  -- taken under `for update` and held to commit, avoids that gap entirely.
  seq              bigint      not null,
  actor_user_id    uuid        not null,
  kind             text        not null,
  payload          jsonb       not null,
  created_at       timestamptz not null default now(),
  primary key (buddy_session_id, seq),
  constraint buddy_session_events_kind_check
    check (kind in ('add', 'remove', 'reorder', 'replace', 'session_ended'))
);

-- No separate index on (buddy_session_id, seq): the composite primary key
-- above already serves the backfill query
-- (`where buddy_session_id = ? and seq > ? order by seq`) directly, so a
-- second index would be redundant.

-- Invisible to every client. No RLS policy is created for this table at
-- all (see below), and all DML privileges are revoked — the same
-- "only a SECURITY DEFINER routine writes here" idiom as
-- public.sync_tombstones in 0005_sync_tombstones.sql.
create table public.buddy_join_tokens (
  token_hash       bytea primary key,
  buddy_session_id uuid not null references public.buddy_sessions(id) on delete cascade,
  created_by       uuid not null,
  expires_at       timestamptz not null,
  consumed_at      timestamptz,
  consumed_by      uuid
);

-- ── Participation helper ───────────────────────────────────────────────
--
-- LANGUAGE plpgsql is load-bearing, not stylistic. A function declared in
-- the SQL procedural language, with a body that is a single SELECT, is
-- inlined by the Postgres planner; inlining discards the SECURITY DEFINER
-- context, so the inner select would be re-subjected to RLS on
-- buddy_participants and any policy that calls this helper would recurse
-- into itself. plpgsql bodies are never inlined, so the definer boundary
-- holds.
create function public.is_buddy_participant(p_session uuid)
returns boolean
language plpgsql
stable
security definer
set search_path = ''
as $$
begin
  return exists (
    select 1
    from public.buddy_participants
    where buddy_session_id = p_session
      and user_id = (select auth.uid())
      and left_at is null
  );
end;
$$;

-- Unlike the trigger-only public.record_sync_tombstone() in
-- 0005_sync_tombstones.sql, EXECUTE must stay granted here: this function
-- is called from inside RLS policies evaluated as the authenticated role,
-- and a revoked EXECUTE would make every buddy select fail.
grant execute on function public.is_buddy_participant(uuid) to authenticated;

-- ── Row level security on the buddy tables ────────────────────────────
alter table public.buddy_sessions       enable row level security;
alter table public.buddy_participants   enable row level security;
alter table public.buddy_session_events enable row level security;
alter table public.buddy_join_tokens    enable row level security;

-- buddy_sessions: readable by participants and by its creator; never
-- client-updated (next_seq must only move inside buddy_append_event()).
create policy buddy_sessions_select_participant
  on public.buddy_sessions for select
  using (public.is_buddy_participant(id) or created_by = (select auth.uid()));

create policy buddy_sessions_insert_own
  on public.buddy_sessions for insert
  with check (created_by = (select auth.uid()));

revoke update, delete on public.buddy_sessions from anon, authenticated;

-- buddy_participants: readable by participants. The one client-writable
-- field is your own left_at (the "leave" action); every other write path
-- goes through buddy_create_session() / buddy_join_session() below, so no
-- insert policy exists at all.
create policy buddy_participants_select_participant
  on public.buddy_participants for select
  using (public.is_buddy_participant(buddy_session_id));

create policy buddy_participants_update_self
  on public.buddy_participants for update
  using (user_id = (select auth.uid()))
  with check (user_id = (select auth.uid()));

revoke insert, delete on public.buddy_participants from anon, authenticated;

-- buddy_session_events: readable by participants, written only by
-- buddy_append_event() below.
create policy buddy_session_events_select_participant
  on public.buddy_session_events for select
  using (public.is_buddy_participant(buddy_session_id));

revoke insert, update, delete on public.buddy_session_events from anon, authenticated;

-- buddy_join_tokens: RLS enabled, zero policies created. RLS-on plus no
-- policy is deny-all for every ordinary role — only the table owner and
-- SECURITY DEFINER routines that run as the owner can ever see a row here.
revoke all on public.buddy_join_tokens from anon, authenticated;
