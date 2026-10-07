-- ─────────────────────────────────────────────────────────────────────
-- Per-kind AI usage quota (KB-05, D-10..D-14)
-- ─────────────────────────────────────────────────────────────────────
--
-- Supersedes `public.ai_usage_bump` as defined in
-- `0018_shared_data_hardening.sql` (lines ~358-398) — that file is already
-- applied both locally and remotely and is NOT edited here.
--
-- Two changes from 0018's version:
--
-- 1. The quota sum now scopes to `and kind = p_kind`. `ai_usage` already
--    keys on `(user_id, day, kind)`; 0018 summed across every kind for a
--    user/day, which meant exhausting one kind (e.g. `dream_physique`)
--    silently blocked every other kind (e.g. `food_photo`) for the rest of
--    the day. Each kind now spends only its own budget.
--
-- 2. `p_daily_limit` drops its `default 50`. After this plan's
--    `supabase/functions/gemini-analyze/index.ts` change, the function's
--    only production caller always passes an explicit, per-kind limit via
--    `limitForKind()`. A bare default here would silently reintroduce the
--    old shared-cap number for any future direct SQL caller that forgets
--    the third argument.
--
-- Postgres refuses to remove a parameter default via `create or replace
-- function` (SQLSTATE 42P13, "cannot remove parameter defaults from
-- existing function") — confirmed against the live project. The function
-- must be dropped and recreated instead, which resets its grants to the
-- Postgres default (EXECUTE granted to PUBLIC) — the `revoke` from 0018
-- is therefore re-run below, not skipped.
drop function if exists public.ai_usage_bump(uuid, text, integer);

create function public.ai_usage_bump(
  p_user_id     uuid,
  p_kind        text,
  p_daily_limit integer
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_today integer;
  v_new   integer;
begin
  if p_user_id is null then
    raise exception 'not authenticated' using errcode = '42501';
  end if;

  -- Kvota je dnevni sesestevek klicev ZNOTRAJ ENEGA `kind`-a, ne cez vse
  -- vrste — glej opombo zgoraj.
  select coalesce(sum(calls), 0) into v_today
  from public.ai_usage
  where user_id = p_user_id
    and day = (now() at time zone 'utc')::date
    and kind = p_kind;

  if v_today >= p_daily_limit then
    return jsonb_build_object('allowed', false, 'used', v_today, 'limit', p_daily_limit);
  end if;

  -- `ai_usage.calls` brez sheme: v ON CONFLICT DO UPDATE se ciljna tabela
  -- naslavlja po imenu/aliasu, ne po polni poti — `public.ai_usage.calls` bi
  -- bila napaka, tudi (in prav posebej) pri `search_path = ''`.
  insert into public.ai_usage as u (user_id, day, kind, calls)
  values (p_user_id, (now() at time zone 'utc')::date, p_kind, 1)
  on conflict (user_id, day, kind)
    do update set calls = u.calls + 1
  returning u.calls into v_new;

  return jsonb_build_object('allowed', true, 'used', v_today + 1, 'limit', p_daily_limit);
end;
$$;

revoke execute on function public.ai_usage_bump(uuid, text, integer) from public, anon, authenticated;
