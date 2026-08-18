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

-- ── Client RPCs ────────────────────────────────────────────────────────
--
-- All five functions in this section are SECURITY DEFINER with an empty,
-- pinned search_path and fully qualified names throughout their bodies —
-- the same rule 0005_sync_tombstones.sql states for
-- record_sync_tombstone(): a definer function with a mutable search_path
-- is a privilege-escalation vector, not just a lint.

create function public.buddy_create_session(
  p_workout_session_uuid uuid,
  p_display_name         text,
  p_avatar_url            text
)
returns table (buddy_session_id uuid, join_token text)
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_uid     uuid := (select auth.uid());
  v_session uuid;
  v_token   text;
begin
  if v_uid is null then
    raise exception 'not authenticated' using errcode = '42501';
  end if;

  -- gen_random_uuid() is core Postgres (13+) and CSPRNG-backed: ~122 bits
  -- of entropy, no pgcrypto dependency.
  v_token := gen_random_uuid()::text;

  insert into public.buddy_sessions (created_by)
  values (v_uid)
  returning id into v_session;

  insert into public.buddy_participants
    (buddy_session_id, user_id, workout_session_uuid, display_name, avatar_url)
  values (v_session, v_uid, p_workout_session_uuid, p_display_name, p_avatar_url);

  -- Token TTL: 10 minutes, a single named literal here — tune only in this
  -- one place.
  insert into public.buddy_join_tokens
    (token_hash, buddy_session_id, created_by, expires_at)
  values (
    sha256(convert_to(v_token, 'UTF8')),
    v_session,
    v_uid,
    now() + interval '10 minutes'
  );

  return query select v_session, v_token;
end;
$$;

create function public.buddy_join_session(
  p_token                text,
  p_workout_session_uuid uuid,
  p_display_name         text,
  p_avatar_url            text
)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_uid uuid := (select auth.uid());
  v_tok public.buddy_join_tokens;
begin
  if v_uid is null then
    raise exception 'invalid or expired join code' using errcode = '42501';
  end if;

  -- `for update` makes check-then-consume atomic: two simultaneous scans
  -- of the same QR code cannot both succeed.
  select * into v_tok
  from public.buddy_join_tokens
  where token_hash = sha256(convert_to(p_token, 'UTF8'))
  for update;

  -- One combined gate, one message. Distinguishing "not found" from
  -- "expired" from "already consumed" from "session ended" from
  -- "session full" is an existence oracle — a later refactor must not
  -- split this into per-cause messages.
  if v_tok.token_hash is null
     or v_tok.expires_at <= now()
     or v_tok.consumed_at is not null
     or v_tok.created_by = v_uid
     or exists (
          select 1 from public.buddy_sessions
          where id = v_tok.buddy_session_id and ended_at is not null
        )
     or (
          select count(*) from public.buddy_participants
          where buddy_session_id = v_tok.buddy_session_id and left_at is null
        ) >= 2
  then
    raise exception 'invalid or expired join code' using errcode = '42501';
  end if;

  update public.buddy_join_tokens
  set consumed_at = now(), consumed_by = v_uid
  where token_hash = v_tok.token_hash;

  insert into public.buddy_participants
    (buddy_session_id, user_id, workout_session_uuid, display_name, avatar_url)
  values (v_tok.buddy_session_id, v_uid, p_workout_session_uuid, p_display_name, p_avatar_url);

  return v_tok.buddy_session_id;
end;
$$;

create function public.buddy_append_event(
  p_buddy_session_id uuid,
  p_kind              text,
  p_payload           jsonb
)
returns bigint
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_uid uuid := (select auth.uid());
  v_seq bigint;
begin
  if v_uid is null then
    raise exception 'not authenticated' using errcode = '42501';
  end if;

  -- Participation is re-checked on every append, independently of
  -- whatever the Realtime authorization cache currently believes: a
  -- departed participant (left_at set) or an ended session (ended_at set)
  -- can never write here even while their websocket connection is still
  -- open.
  if not exists (
    select 1
    from public.buddy_participants p
    join public.buddy_sessions s on s.id = p.buddy_session_id
    where p.buddy_session_id = p_buddy_session_id
      and p.user_id = v_uid
      and p.left_at is null
      and s.ended_at is null
  ) then
    raise exception 'not a participant' using errcode = '42501';
  end if;

  -- Per-session counter under a row lock, held to commit: the second
  -- writer cannot obtain a number until the first is visible, so this is
  -- gapless and commit-ordered. Trivial contention at the two writers
  -- this table ever has.
  select next_seq into v_seq
  from public.buddy_sessions
  where id = p_buddy_session_id
  for update;

  insert into public.buddy_session_events
    (buddy_session_id, seq, actor_user_id, kind, payload)
  values (p_buddy_session_id, v_seq, v_uid, p_kind, p_payload);

  update public.buddy_sessions set next_seq = v_seq + 1 where id = p_buddy_session_id;

  return v_seq;
end;
$$;

-- Broadcast is derived from the durable row by this trigger, never sent
-- alongside it by the client — so "the log is the source of truth" is
-- structural rather than a convention a refactor could break.
create function public.buddy_broadcast_event()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  perform realtime.send(
    jsonb_build_object(
      'seq',     new.seq,
      'kind',    new.kind,
      'actor',   new.actor_user_id,
      'payload', new.payload
    ),
    'buddy_event',
    'buddy:' || new.buddy_session_id::text,
    true
  );
  return null;
end;
$$;

-- Trigger-only, matching the revoke pattern at
-- 0005_sync_tombstones.sql:69 for public.record_sync_tombstone(): a
-- security-definer function with no legitimate direct-call use case has no
-- business being reachable through the exposed PostgREST RPC surface.
revoke execute on function public.buddy_broadcast_event() from public, anon, authenticated;

create trigger t_buddy_broadcast_event after insert on public.buddy_session_events
  for each row execute function public.buddy_broadcast_event();

grant execute on function public.buddy_create_session(uuid, text, text) to authenticated;
grant execute on function public.buddy_join_session(text, uuid, text, text) to authenticated;
grant execute on function public.buddy_append_event(uuid, text, jsonb) to authenticated;

-- ── RLS on realtime.messages ──────────────────────────────────────────
--
-- RLS is already enabled by default on realtime.messages; no
-- `alter table realtime.messages enable row level security` is issued
-- here.

-- Receiving broadcast on a buddy topic. Joins against the generated
-- `topic` column on buddy_sessions instead of parsing realtime.topic()
-- with a substring and a uuid cast — a client can request any topic
-- string it likes, and a parse of a hostile string must never be able to
-- throw.
create policy buddy_can_receive_broadcast
  on realtime.messages for select
  to authenticated
  using (
    realtime.messages.extension = 'broadcast'
    and exists (
      select 1
      from public.buddy_sessions s
      where s.topic = (select realtime.topic())
        and public.is_buddy_participant(s.id)
    )
  );

-- The only INSERT clients ever need on realtime.messages: presence
-- check-ins. Choreography broadcast always originates from
-- t_buddy_broadcast_event above, never from a client — this is the
-- tightest surface available here, and a direct BUD-05 win.
create policy buddy_can_send_presence
  on realtime.messages for insert
  to authenticated
  with check (
    realtime.messages.extension = 'presence'
    and exists (
      select 1
      from public.buddy_sessions s
      where s.topic = (select realtime.topic())
        and public.is_buddy_participant(s.id)
    )
  );

-- The one additive change to an existing synced table. This is a column
-- addition only — it names no policy and alters no policy, so every
-- frozen policy stays exactly as 0003 created it.
alter table public.workout_sessions add column if not exists buddy_session_id uuid;

-- Deliberately not added to the realtime publication that drives
-- postgres_changes delivery. These four tables are consumed exclusively
-- via the broadcast trigger above; adding them there as well would open a
-- second, unauthorised delivery path for the same rows.

-- ── Token cleanup ──────────────────────────────────────────────────────
--
-- Same daily-retention idiom as 0006_sync_tombstone_retention.sql. Unlike
-- that migration, the pg_cron install here is guarded: this file must not
-- fail to apply just because some future or alternate target project
-- lacks the extension. If it is missing, cleanup silently degrades to
-- "expired join tokens accumulate until a later migration schedules a
-- job" — harmless, since every read path to this table is already
-- deny-all.
do $$
begin
  begin
    create extension if not exists pg_cron;
  exception when others then
    raise notice 'pg_cron unavailable — buddy_join_tokens cleanup job not scheduled (%).', sqlerrm;
  end;

  if exists (select 1 from pg_extension where extname = 'pg_cron') then
    perform cron.schedule(
      'buddy_join_tokens_gc',
      '23 3 * * *',
      $cron$delete from public.buddy_join_tokens where expires_at < now() - interval '1 day'$cron$
    );
  else
    raise notice 'pg_cron extension not present — buddy_join_tokens rows will accumulate until a future migration schedules cleanup.';
  end if;
end;
$$;
