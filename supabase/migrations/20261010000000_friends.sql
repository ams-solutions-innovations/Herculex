-- Gym Buddy friends: invite by QR / link, compare published summaries.
--
-- Privacy model: nothing here opens the synced training tables (0003's
-- owner-only RLS stays exactly as it is — test/buddy/rls_frozen_test.dart
-- pins it). Each user instead *publishes* a small summary row
-- (friend_snapshots.payload) that friends may read, and only while the owner
-- keeps friend_profiles.sharing_enabled on.
--
-- No local drift table mirrors any of this: the app reads it live, so no
-- schemaVersion bump goes with this migration.

-- ── Tables ──────────────────────────────────────────────────────────────

create table public.friend_profiles (
  user_id         uuid primary key references auth.users(id) on delete cascade,
  display_name    text,
  avatar_id       text,
  sharing_enabled boolean not null default true,
  updated_at      timestamptz not null default now()
);

create table public.friend_snapshots (
  user_id    uuid primary key references auth.users(id) on delete cascade,
  payload    jsonb not null,
  updated_at timestamptz not null default now()
);

-- One row per pair, smaller uuid first, so a pair cannot exist twice.
create table public.friendships (
  user_a     uuid not null references auth.users(id) on delete cascade,
  user_b     uuid not null references auth.users(id) on delete cascade,
  created_at timestamptz not null default now(),
  primary key (user_a, user_b),
  check (user_a < user_b)
);

create index friendships_user_b_idx on public.friendships (user_b);

-- Same "only a SECURITY DEFINER routine touches this" idiom as
-- buddy_join_tokens in 0011: RLS on, no policies, all privileges revoked.
create table public.friend_invite_tokens (
  token_hash  bytea primary key,
  created_by  uuid not null references auth.users(id) on delete cascade,
  expires_at  timestamptz not null,
  consumed_at timestamptz,
  consumed_by uuid
);

create index friend_invite_tokens_expires_idx
  on public.friend_invite_tokens (expires_at);

-- The client never sends updated_at (its clock is not authoritative).
create function public.friend_touch_updated_at()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  new.updated_at := now();
  return new;
end;
$$;

create trigger t_friend_profiles_touch
  before insert or update on public.friend_profiles
  for each row execute function public.friend_touch_updated_at();

create trigger t_friend_snapshots_touch
  before insert or update on public.friend_snapshots
  for each row execute function public.friend_touch_updated_at();

-- ── Helpers ─────────────────────────────────────────────────────────────
--
-- plpgsql, not sql, for the reason 0011 gives for is_buddy_participant():
-- a single-SELECT sql function is inlined and loses its definer context.

create function public.are_friends(p_a uuid, p_b uuid)
returns boolean
language plpgsql
stable
security definer
set search_path = ''
as $$
begin
  return exists (
    select 1 from public.friendships
    where user_a = least(p_a, p_b) and user_b = greatest(p_a, p_b)
  );
end;
$$;

grant execute on function public.are_friends(uuid, uuid) to authenticated;

-- True when the caller may read [p_owner]'s published rows: it is the caller,
-- or a friend who has sharing on.
create function public.can_read_friend(p_owner uuid)
returns boolean
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_uid uuid := (select auth.uid());
begin
  if v_uid is null then
    return false;
  end if;
  if p_owner = v_uid then
    return true;
  end if;
  return public.are_friends(v_uid, p_owner)
     and coalesce(
           (select sharing_enabled from public.friend_profiles
            where user_id = p_owner),
           false
         );
end;
$$;

grant execute on function public.can_read_friend(uuid) to authenticated;

-- ── Row level security ──────────────────────────────────────────────────

alter table public.friend_profiles      enable row level security;
alter table public.friend_snapshots     enable row level security;
alter table public.friendships          enable row level security;
alter table public.friend_invite_tokens enable row level security;

-- A friend's name and avatar stay visible even with sharing off, so the
-- friends list does not show blank rows; the stats are what sharing hides.
create policy friend_profiles_select
  on public.friend_profiles for select
  using (
    user_id = (select auth.uid())
    or public.are_friends((select auth.uid()), user_id)
  );

create policy friend_profiles_insert_own
  on public.friend_profiles for insert
  with check (user_id = (select auth.uid()));

create policy friend_profiles_update_own
  on public.friend_profiles for update
  using (user_id = (select auth.uid()))
  with check (user_id = (select auth.uid()));

create policy friend_snapshots_select
  on public.friend_snapshots for select
  using (public.can_read_friend(user_id));

create policy friend_snapshots_insert_own
  on public.friend_snapshots for insert
  with check (user_id = (select auth.uid()));

create policy friend_snapshots_update_own
  on public.friend_snapshots for update
  using (user_id = (select auth.uid()))
  with check (user_id = (select auth.uid()));

create policy friendships_select_member
  on public.friendships for select
  using ((select auth.uid()) in (user_a, user_b));

-- Either side may end a friendship. Creation only goes through
-- friend_accept_invite(), so there is no insert policy.
create policy friendships_delete_member
  on public.friendships for delete
  using ((select auth.uid()) in (user_a, user_b));

revoke insert, update on public.friendships from anon, authenticated;
revoke all on public.friend_invite_tokens from anon, authenticated;

-- ── RPCs ────────────────────────────────────────────────────────────────

create function public.friend_create_invite()
returns text
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_uid   uuid := (select auth.uid());
  v_token text;
begin
  if v_uid is null then
    raise exception 'not authenticated' using errcode = '42501';
  end if;

  v_token := gen_random_uuid()::text;

  -- Invite TTL: 7 days — long enough to sit in a chat, single use.
  insert into public.friend_invite_tokens (token_hash, created_by, expires_at)
  values (
    sha256(convert_to(v_token, 'UTF8')),
    v_uid,
    now() + interval '7 days'
  );

  return v_token;
end;
$$;

-- Returns the new friend's user id.
create function public.friend_accept_invite(p_token text)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_uid uuid := (select auth.uid());
  v_tok public.friend_invite_tokens;
begin
  if v_uid is null then
    raise exception 'invalid or expired invite' using errcode = '42501';
  end if;

  select * into v_tok
  from public.friend_invite_tokens
  where token_hash = sha256(convert_to(p_token, 'UTF8'))
  for update;

  -- One combined gate and one message, as in buddy_join_session(): telling
  -- "unknown" from "expired" from "used" is an existence oracle.
  if v_tok.token_hash is null
     or v_tok.expires_at <= now()
     or v_tok.consumed_at is not null
     or v_tok.created_by = v_uid
  then
    raise exception 'invalid or expired invite' using errcode = '42501';
  end if;

  update public.friend_invite_tokens
  set consumed_at = now(), consumed_by = v_uid
  where token_hash = v_tok.token_hash;

  insert into public.friendships (user_a, user_b)
  values (least(v_uid, v_tok.created_by), greatest(v_uid, v_tok.created_by))
  on conflict do nothing;

  return v_tok.created_by;
end;
$$;

-- Buddy sessions the caller and [p_friend] were both in. Reads
-- buddy_participants as definer because its own RLS only shows live
-- sessions; the friendship check keeps this from probing strangers.
create function public.friend_shared_sessions(p_friend uuid)
returns table (buddy_session_id uuid, joined_at timestamptz)
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_uid uuid := (select auth.uid());
begin
  if v_uid is null or not public.are_friends(v_uid, p_friend) then
    return;
  end if;
  return query
    select me.buddy_session_id, least(me.joined_at, them.joined_at)
    from public.buddy_participants me
    join public.buddy_participants them
      on them.buddy_session_id = me.buddy_session_id
     and them.user_id = p_friend
    where me.user_id = v_uid
    order by 2 desc
    limit 50;
end;
$$;

revoke all on function public.friend_create_invite() from public, anon;
revoke all on function public.friend_accept_invite(text) from public, anon;
revoke all on function public.friend_shared_sessions(uuid) from public, anon;
grant execute on function public.friend_create_invite() to authenticated;
grant execute on function public.friend_accept_invite(text) to authenticated;
grant execute on function public.friend_shared_sessions(uuid) to authenticated;

-- ── Token cleanup ───────────────────────────────────────────────────────
-- Guarded exactly like 0011: pg_cron may be unavailable.
do $$
begin
  if exists (select 1 from pg_extension where extname = 'pg_cron') then
    perform cron.schedule(
      'friend_invite_tokens_gc',
      '17 3 * * *',
      $cron$delete from public.friend_invite_tokens where expires_at < now() - interval '1 day'$cron$
    );
  else
    raise notice 'pg_cron not present — friend_invite_tokens rows will accumulate until cleanup is scheduled.';
  end if;
end;
$$;
