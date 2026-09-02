-- Utrditev deljenih (ne-per-user) podatkov: skupni katalog izdelkov in
-- obracun porabe AI.
--
-- Kontekst. Vsaka druga tabela v tej shemi je per-user in jo scita RLS iz
-- 0003 — najhujse, kar lahko naredi pokvarjen klient, je, da pokvari lastne
-- podatke. `product_catalogue` (0012) je edina izjema: en zapis vidijo VSI.
-- Njena zascita je bila do zdaj samo "klient ne more pisati neposredno" —
-- kar drzi, a Edge Function `product-catalogue-publish` je sprejela
-- karkoli, kar je imelo `barcode`, `name` in stevilcni `kcalPer100g`, in
-- pisala z `resolution=merge-duplicates`. Torej: zadnji pisec povozi vse,
-- brez sledi, brez pragu zaupanja, brez moznosti umika. En sam napacen
-- Gemini odgovor je trajno pokvaril podatek za vse uporabnike.
--
-- Ta migracija naredi tri stvari:
--   1. Postavi meje, ki jih baza sama vsili (CHECK constrainti) — ne glede
--      na to, kaj posilja klient ali funkcija.
--   2. Uvede zgodovino oddaj + konsenz: prva oddaja objavi, druga
--      ujemajoca potrdi, neujemajoca oznaci za pregled namesto da povozi.
--   3. Doda `ai_usage` — obracun in dnevna kvota za Gemini klice, ki jih do
--      zdaj ni nihce stel.

-- ─────────────────────────────────────────────────────────────────────
-- 1. Meje na product_catalogue
-- ─────────────────────────────────────────────────────────────────────
--
-- `not valid` na vseh: obstojece vrstice (nastale, ko validacije ni bilo)
-- se ne preverjajo, nove pa da. Migracija tako ne more pasti zaradi
-- podatkov, ki so ze notri. Ko bo baza pociscena, jih potrdi z
-- `alter table ... validate constraint ...`.

alter table public.product_catalogue
  add constraint product_catalogue_barcode_format
    check (barcode ~ '^[0-9]{8,14}$') not valid;

alter table public.product_catalogue
  add constraint product_catalogue_name_len
    check (char_length(btrim(name)) between 2 and 200) not valid;

-- 900 kcal/100 g je fizikalna meja: cista mascoba je 900. Karkoli vec je
-- napaka, ne izdelek.
alter table public.product_catalogue
  add constraint product_catalogue_kcal_range
    check (kcal_per_100g >= 0 and kcal_per_100g <= 900) not valid;

alter table public.product_catalogue
  add constraint product_catalogue_macros_range
    check (
      protein_per_100g between 0 and 100
      and carbs_per_100g between 0 and 100
      and fat_per_100g between 0 and 100
      and (fiber_per_100g is null or fiber_per_100g between 0 and 100)
      -- Vsota makrohranil ne more presegati mase. 105 namesto 100, ker
      -- deklaracije zaokrozujejo navzgor in vlaknine so lahko steti
      -- dvojno (enkrat kot ogljikovi hidrati, enkrat posebej).
      and (protein_per_100g + carbs_per_100g + fat_per_100g) <= 105
    ) not valid;

alter table public.product_catalogue
  add constraint product_catalogue_serving_range
    check (serving_grams is null or (serving_grams > 0 and serving_grams <= 10000))
    not valid;

-- ─────────────────────────────────────────────────────────────────────
-- 2. Konsenz namesto "zadnji pisec zmaga"
-- ─────────────────────────────────────────────────────────────────────

alter table public.product_catalogue
  -- Koliko neodvisnih oddaj se strinja s trenutno objavljenimi vrednostmi.
  add column if not exists submission_count integer not null default 1,
  -- true, ko je `submission_count >= 2` ali ko je vrstico potrdil clovek.
  -- Potrjene vrstice se ne prepisujejo avtomatsko.
  add column if not exists verified boolean not null default false,
  -- true, ko je prisla oddaja, ki se z objavljeno NE ujema. Podatek ostane
  -- objavljen (bolje priblizek kot nic), a je oznacen za pregled.
  add column if not exists needs_review boolean not null default false,
  add column if not exists confidence double precision,
  -- Katera pot je nazadnje pisala vrstico ('gemini', 'off', 'manual').
  add column if not exists last_source text,
  -- Soft-delete. Do zdaj ni bilo nacina umakniti spornega izdelka.
  add column if not exists deleted_at timestamptz;

-- Zgodovina. Objavljena vrstica je pogled na resnico; to je dokazno gradivo
-- za njo — vkljucno z grounding viri, ki jih je Gemini uporabil. Brez tega
-- ni nacina preveriti, od kod je stevilka.
create table if not exists public.product_catalogue_submissions (
  id             uuid primary key default gen_random_uuid(),
  barcode        text not null,
  contributed_by uuid references auth.users(id) on delete set null,
  payload        jsonb not null,
  source         text not null default 'gemini',
  confidence     double precision,
  -- 'published' (postala/potrdila objavljeno vrstico) ali 'conflict'
  -- (ni se ujemala; objavljena vrstica je dobila needs_review).
  outcome        text not null,
  created_at     timestamptz not null default now(),
  constraint product_catalogue_submissions_outcome_check
    check (outcome in ('published', 'confirmed', 'conflict', 'rejected'))
);

create index if not exists product_catalogue_submissions_barcode_idx
  on public.product_catalogue_submissions (barcode, created_at desc);

create index if not exists product_catalogue_submissions_contributor_idx
  on public.product_catalogue_submissions (contributed_by, created_at desc);

alter table public.product_catalogue_submissions enable row level security;

-- RLS vklopljen, nic politik: deny-all za anon in authenticated. Isti
-- vzorec kot `buddy_join_tokens` v 0011 — samo SECURITY DEFINER rutina
-- spodaj kdaj pise ali bere tu.
revoke all on public.product_catalogue_submissions from anon, authenticated;

-- ─────────────────────────────────────────────────────────────────────
-- 3. contributed_by ni vec javen
-- ─────────────────────────────────────────────────────────────────────
--
-- Politika `product_catalogue_select_all` (0012) je `using (true)`, torej
-- je vsak prijavljen uporabnik lahko naredil
-- `select contributed_by from product_catalogue` in dobil seznam UUID-jev
-- ljudi, ki so prispevali. To ni katastrofa (UUID ni ime), je pa osebni
-- podatek na javno berljivi tabeli in nima nobene funkcije na klientu.
--
-- OPOZORILO ZA KLIENTA: po tem stavku `select *` na tej tabeli vrne 42501.
-- `ProductCatalogueRepository.lookupByBarcode()` MORA nasteti stolpce
-- eksplicitno. Ta migracija in ta sprememba klienta gresta skupaj.
revoke select (contributed_by) on public.product_catalogue
  from anon, authenticated;

-- ─────────────────────────────────────────────────────────────────────
-- 4. Edina pisalna pot
-- ─────────────────────────────────────────────────────────────────────
--
-- Logika zivi tu, ne v Edge Functionu, iz enega razloga: konsenz je
-- read-modify-write. V TypeScriptu bi bila to dva HTTP klica z dirko med
-- njima — dva hkratna skena istega izdelka bi oba prebrala
-- `submission_count = 1` in oba zapisala 2. Tu je vse pod enim `for update`
-- v eni transakciji.
--
-- Edge Function `product-catalogue-publish` ostane vstopna tocka (preveri
-- JWT, klice to s service-role kljucem) — tako je pisalna pot se vedno ena
-- sama in dokumentirana, kot pravi 0012.
create or replace function public.product_catalogue_submit(
  p_user_id    uuid,
  p_barcode    text,
  p_payload    jsonb,
  p_source     text default 'gemini',
  p_confidence double precision default null
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_existing public.product_catalogue;
  v_recent   integer;
  v_matches  boolean;
  v_outcome  text;
  v_kcal     double precision := (p_payload->>'kcal_per_100g')::double precision;
  v_protein  double precision := coalesce((p_payload->>'protein_per_100g')::double precision, 0);
  v_carbs    double precision := coalesce((p_payload->>'carbs_per_100g')::double precision, 0);
  v_fat      double precision := coalesce((p_payload->>'fat_per_100g')::double precision, 0);
begin
  if p_user_id is null then
    raise exception 'not authenticated' using errcode = '42501';
  end if;

  -- Omejitev prispevkov. Brez nje lahko en racun objavi 10.000 izdelkov v
  -- minuti in pokvari katalog vsem. 30/uro je vec, kot jih clovek fizicno
  -- lahko skenira, in dovolj malo, da je skripta neuporabna.
  select count(*) into v_recent
  from public.product_catalogue_submissions
  where contributed_by = p_user_id
    and created_at > now() - interval '1 hour';

  if v_recent >= 30 then
    raise exception 'submission rate limit exceeded' using errcode = 'P0001';
  end if;

  -- Mehka kontrola: kcal se mora priblizno ujemati z makrohranili
  -- (Atwater: 4/4/9). Ce se ne, je nekaj narobe prebrano — ne zavrni, a
  -- oznaci. `not valid` CHECK-i zgoraj lovijo nemogoce, to lovi
  -- nekonsistentno.
  if v_kcal is null
     or abs(v_kcal - (4 * v_protein + 4 * v_carbs + 9 * v_fat)) > greatest(40, v_kcal * 0.25)
  then
    insert into public.product_catalogue_submissions
      (barcode, contributed_by, payload, source, confidence, outcome)
    values (p_barcode, p_user_id, p_payload, p_source, p_confidence, 'rejected');
    return jsonb_build_object('status', 'rejected', 'reason', 'macro_mismatch');
  end if;

  select * into v_existing
  from public.product_catalogue
  where barcode = p_barcode
  for update;

  -- Prvi vnos za ta barcode: objavi takoj, neverificiran.
  if v_existing.barcode is null then
    insert into public.product_catalogue (
      barcode, name, brand,
      kcal_per_100g, protein_per_100g, carbs_per_100g, fat_per_100g,
      fiber_per_100g, sodium_mg_per_100g, potassium_mg_per_100g,
      cholesterol_mg_per_100g, serving_grams, serving_label,
      reference_basis, source, contributed_by,
      submission_count, verified, confidence
    )
    values (
      p_barcode,
      btrim(p_payload->>'name'),
      nullif(btrim(coalesce(p_payload->>'brand', '')), ''),
      v_kcal, v_protein, v_carbs, v_fat,
      (p_payload->>'fiber_per_100g')::double precision,
      (p_payload->>'sodium_mg_per_100g')::double precision,
      (p_payload->>'potassium_mg_per_100g')::double precision,
      (p_payload->>'cholesterol_mg_per_100g')::double precision,
      (p_payload->>'serving_grams')::double precision,
      nullif(btrim(coalesce(p_payload->>'serving_label', '')), ''),
      coalesce(nullif(btrim(coalesce(p_payload->>'reference_basis', '')), ''), '100 g'),
      p_source, p_user_id,
      1, false, p_confidence
    );
    v_outcome := 'published';

  else
    -- Se oddaja ujema z objavljenim? 10 % tolerance na vsakem makru.
    v_matches :=
      abs(v_existing.kcal_per_100g - v_kcal) <= greatest(10, v_existing.kcal_per_100g * 0.1)
      and abs(v_existing.protein_per_100g - v_protein) <= greatest(1, v_existing.protein_per_100g * 0.1)
      and abs(v_existing.carbs_per_100g - v_carbs) <= greatest(1, v_existing.carbs_per_100g * 0.1)
      and abs(v_existing.fat_per_100g - v_fat) <= greatest(1, v_existing.fat_per_100g * 0.1);

    if v_matches then
      update public.product_catalogue
      set submission_count = submission_count + 1,
          verified = true,                   -- dve neodvisni ujemajoci oddaji
          confidence = greatest(coalesce(confidence, 0), coalesce(p_confidence, 0)),
          deleted_at = null,
          updated_at = now()
      where barcode = p_barcode;
      v_outcome := 'confirmed';

    elsif v_existing.verified then
      -- Potrjenega podatka nova neujemajoca oddaja NE povozi. To je celoten
      -- smisel `verified`.
      update public.product_catalogue
      set needs_review = true, updated_at = now()
      where barcode = p_barcode;
      v_outcome := 'conflict';

    else
      -- Neverificirano in neujemajoce: novejsi podatek prevzame (verjetneje
      -- je popravek kot poslabsanje), a stevec se resetira in vrstica gre v
      -- pregled.
      update public.product_catalogue
      set name = btrim(p_payload->>'name'),
          brand = nullif(btrim(coalesce(p_payload->>'brand', '')), ''),
          kcal_per_100g = v_kcal,
          protein_per_100g = v_protein,
          carbs_per_100g = v_carbs,
          fat_per_100g = v_fat,
          fiber_per_100g = (p_payload->>'fiber_per_100g')::double precision,
          sodium_mg_per_100g = (p_payload->>'sodium_mg_per_100g')::double precision,
          potassium_mg_per_100g = (p_payload->>'potassium_mg_per_100g')::double precision,
          cholesterol_mg_per_100g = (p_payload->>'cholesterol_mg_per_100g')::double precision,
          serving_grams = (p_payload->>'serving_grams')::double precision,
          serving_label = nullif(btrim(coalesce(p_payload->>'serving_label', '')), ''),
          submission_count = 1,
          needs_review = true,
          confidence = p_confidence,
          last_source = p_source,
          updated_at = now()
      where barcode = p_barcode;
      v_outcome := 'conflict';
    end if;
  end if;

  insert into public.product_catalogue_submissions
    (barcode, contributed_by, payload, source, confidence, outcome)
  values (p_barcode, p_user_id, p_payload, p_source, p_confidence, v_outcome);

  return jsonb_build_object('status', v_outcome);
end;
$$;

-- Klicana samo s service-role kljucem iz Edge Functiona. Nikoli
-- neposredno s klienta: podpisi `p_user_id` kot argument, kar bi
-- authenticated roli omogocilo, da se predstavi kot kdorkoli.
revoke execute on function public.product_catalogue_submit(uuid, text, jsonb, text, double precision)
  from public, anon, authenticated;

-- Bralna pot ne sme videti umaknjenih izdelkov. Politika iz 0012 je
-- `using (true)` in je po `docs/supabase-migrations.md` NE smemo
-- spreminjati na siroko — a dodati ozjo je varno in ne dotakne 0003.
drop policy if exists product_catalogue_select_all on public.product_catalogue;
create policy product_catalogue_select_live on public.product_catalogue
  for select using (deleted_at is null);

-- ─────────────────────────────────────────────────────────────────────
-- 5. Obracun porabe AI
-- ─────────────────────────────────────────────────────────────────────
--
-- Do zdaj ni bilo nobenega stevca: en racun je lahko poslal 12 MB sliko v
-- zanki in edini signal bi bil racun od Googla ob koncu meseca.

create table if not exists public.ai_usage (
  user_id uuid    not null references auth.users(id) on delete cascade,
  day     date    not null default (now() at time zone 'utc')::date,
  kind    text    not null,
  calls   integer not null default 0,
  primary key (user_id, day, kind)
);

alter table public.ai_usage enable row level security;

-- Uporabnik lahko vidi svojo porabo (za "danes si porabil 12/50"), pisati
-- pa ne more nihce razen definer funkcije spodaj — sicer bi si kvoto
-- preprosto ponastavil.
create policy ai_usage_select_own on public.ai_usage
  for select using (user_id = auth.uid());

revoke insert, update, delete on public.ai_usage from anon, authenticated;

-- Poveca stevec in vrne, ali je klic dovoljen.
create or replace function public.ai_usage_bump(
  p_user_id     uuid,
  p_kind        text,
  p_daily_limit integer default 50
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

  -- Kvota je dnevni SEsestevek vseh vrst, ne na vrsto — sicer bi jo bilo
  -- trivialno obiti z menjavanjem `kind`.
  select coalesce(sum(calls), 0) into v_today
  from public.ai_usage
  where user_id = p_user_id
    and day = (now() at time zone 'utc')::date;

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

revoke execute on function public.ai_usage_bump(uuid, text, integer)
  from public, anon, authenticated;

-- Retencija: 90 dni je dovolj za mesecni pregled porabe, isti vzorec kot
-- 0006 in 0011.
do $$
begin
  if exists (select 1 from pg_extension where extname = 'pg_cron') then
    perform cron.schedule(
      'ai_usage_gc',
      '31 3 * * *',
      $cron$delete from public.ai_usage where day < (now() at time zone 'utc')::date - 90$cron$
    );
  else
    raise notice 'pg_cron not present — ai_usage rows will accumulate.';
  end if;
end;
$$;
