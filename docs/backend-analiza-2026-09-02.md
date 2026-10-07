# Backend — globoka analiza in TODO (2026-09-02)

Obseg: Supabase projekt `ldzgyzigvbwofbswitrv` — Postgres shema, RLS, Edge
Functions, Storage, Realtime, sync engine (`lib/data/sync/`), skrivnosti.

Kratek povzetek: **arhitektura je dobra** (per-user RLS, server-side LWW ura,
tombstones, deny-all + SECURITY DEFINER vzorec za skupne tabele). Kar manjka,
so **operativne stvari**: neuporabljeni indeksi, nepaginiran pull, dve
neapplied migraciji in Gemini secret, ki je nastavljen na napačnem projektu.

---

## 0. Prioritetni seznam

| # | Stvar | Resnost | Kje |
|---|---|---|---|
| 1 | `GEMINI_API_KEY` ni na pravem projektu | **Blocker** | §1 |
| 2 | Migraciji `0015` + `0016` nista applied | **Blocker** | §2 |
| 3 | ~~Nobenega indeksa na 38 sinhroniziranih tabelah~~ → migracija `0017` napisana, čaka `db push` | **P0 (perf)** | §3 |
| 4 | ~~`pull()` nima `.order()` + `.range()`~~ → popravljeno v kodi | **P0 (correctness)** | §4 |
| 5 | ~~`product_catalogue` brez validacije / dedup / moderacije~~ → migracija `0018` + prepisana funkcija | **P1** | §5 |
| 6 | ~~Gemini funkcija brez rate-limita~~ → `ai_usage` + dnevna kvota | **P1** | §6 |
| 7 | 37 realtime kanalov na napravo | **P1** | §7 |
| 8 | ~~`SupabaseSyncBackendService` brez razlikovanja napak~~ → popravljeno v kodi | **P1** | §8 |
| 9 | Storage bucket `user-photos` — brez lifecycle, brez limita na uporabnika | **P2** | §9 |
| 10 | Ni CI-ja za `db push` / deploy funkcij; ni backup/restore plana | **P2** | §10 |

---

## 1. Gemini API ključ kot secret

### Stanje

Koda je **že pravilna** — RB-01 je zaprt. Flutter nikjer nima ključa
(`Env` nima `GEMINI_API_KEY`), klici gredo skozi Edge Function
`gemini-analyze`, ki bere `Deno.env.get("GEMINI_API_KEY")`, in
`config.toml` ima `verify_jwt = true`.

**Problem:** `docs/rb01-gemini-secret-remediation.md` izrecno pravi, da je
ključ nastavljen na `jioesomepkauponjrena` (SummitSki), funkcija pa je bila
15. 8. redeploy-ana na `ldzgyzigvbwofbswitrv` — in tam
**`GEMINI_API_KEY` še ni bil nastavljen**. Dokler ni, vsak AI klic vrne
`503 "Gemini is not configured on the server."`.

### Kaj narediti (PowerShell na Windows, iz korena repota)

```powershell
npm install                                   # pinnan CLI 2.114.0
$env:SUPABASE_ACCESS_TOKEN = "sbp_..."        # iz dashboard/account/tokens
npx supabase link --project-ref ldzgyzigvbwofbswitrv

# 1. Preveri, kaj je trenutno nastavljeno
npx supabase secrets list --project-ref ldzgyzigvbwofbswitrv

# 2. Nastavi (NE prek datoteke, ki bi končala v gitu)
npx supabase secrets set GEMINI_API_KEY=... --project-ref ldzgyzigvbwofbswitrv
npx supabase secrets set GEMINI_MODEL=gemini-2.0-flash --project-ref ldzgyzigvbwofbswitrv

# 3. Redeploy, da funkcija pobere nov env
npx supabase functions deploy gemini-analyze --project-ref ldzgyzigvbwofbswitrv --use-api
npx supabase functions list --project-ref ldzgyzigvbwofbswitrv   # ACTIVE + verify_jwt: true
```

`SUPABASE_URL`, `SUPABASE_ANON_KEY`, `SUPABASE_SERVICE_ROLE_KEY` so
avtomatsko injectani v vsako funkcijo — teh **ne** nastavljaj ročno.

### Kar je še odprto okrog ključa

- **Ključ na napačnem projektu je treba revoke-ati.** Če je isti Google API
  ključ še vedno aktiven na SummitSki projektu, ga rotiraj: nov ključ v
  Google AI Studio, star izbriši, nov nastavi samo na Herculexu.
- **Omeji ključ v Google Cloud Console**: API restrictions → samo
  Generative Language API, plus quota per minute. Edge Function nima
  fiksnega IP-ja, zato IP restriction ni možen — quota je edina obramba.
- **Rotacijski postopek zapiši** (§6) — trenutno ni nikjer dokumentiran.
- `.secrets/live_sync.json` ima gesla dveh živih računov v plain textu.
  Gitignoran je, ampak `martin.dumanic@gmail.com` še vedno nosi throwaway
  geslo iz RB-02 verifikacije. Zamenjaj ga.

---

## 2. Neapplied migracije (blocker za release)

`docs/supabase-migrations.md` potrjuje `0001`–`0013` kot local == remote.
**`0015` in `0016` sta napisani, a nista applied.** Lokalna drift shema je
že v37.

Posledica, ki jo migraciji sami opisujeta: `SyncService._buildRemotePayload`
dela `SELECT *` in pošlje vsak stolpec, ki ni FK/localOnly/dateTime. Zato
v37 klient pošilja `workout_sessions.photo_path`, `.calories_burned`,
celotni tabeli `workout_circuits`/`circuit_exercises` in šest novih stolpcev
na `exercise_progressions`. Postgres odgovori `PGRST204` / `42P01`,
`_pushOne` retry-ja z backoffom in **po 8 poskusih karantenira op**. Vsak
končan trening tiho neha prihajati v oblak.

```powershell
npx supabase migration list                  # potrdi, da 0015/0016 nimata Remote
npx supabase db push --yes                   # aplicira po vrsti
npx supabase migration list                  # potrdi
```

Po tem je treba **retry-jati karantenirane outbox vrstice** na vsaki napravi,
ki je že tekla na v33+. Trenutno ni UI poti za to — glej §8.

> Pravilo, ki ga velja avtomatizirati: `schemaVersion` bump = 5 opravil
> (CLAUDE.md). Peto (`supabase/migrations/NNNN_*.sql`) je edino, ki ga noben
> test ne ujame. Predlog: test, ki prebere `syncTableSpecs` + drift shemo in
> primerja stolpce z zadnjo migracijo — ali vsaj skripta
> `tool/check_remote_schema.dart`, ki dela `select *` limit 0 na vsako
> sinhronizirano tabelo in primerja stolpce.

---

## 3. Indeksi — trenutno jih praktično ni

Skozi vseh 16 migracij obstaja **en sam** `create index`
(`sync_tombstones_user_deleted_at_idx`). Vse ostalo se zanaša na primarne
ključe.

Vsak delta pull je:

```sql
select * from <tabela> where user_id = ? and updated_at > ?
```

Brez indeksa je to **sequential scan cele tabele** ob vsakem pull-u, na 38
tabelah, na vsakih 5 minut, za vsakega uporabnika. Dokler je uporabnikov
malo, se ne vidi; pri nekaj sto uporabnikih z leti zgodovine `set_entries`
in `food_entries` postaneta prvi, ki zapečeta CPU.

**Kar dodaj (nova migracija `0017_sync_indexes.sql`):**

```sql
-- Točno oblika, ki jo dela SupabaseSyncBackendService.pull().
do $$
declare
  t text;
  tables text[] := array[ /* istih 38 imen kot v 0003 + 0009/0011/0014/0015 */ ];
begin
  foreach t in array tables loop
    execute format(
      'create index if not exists %I on public.%I (user_id, updated_at)',
      t || '_user_updated_at_idx', t
    );
  end loop;
end $$;
```

Dodatno, ciljano:

```sql
-- pullExistingIds: select id where user_id = ?  → pokrit z zgornjim, a
-- covering index je cenejši:
create index if not exists set_entries_user_id_idx on set_entries (user_id) include (id);

-- FK-ji brez indeksa: vsak `references` stolpec, po katerem se briše
-- (cascade), potrebuje indeks, sicer je vsak delete seq scan otroka.
create index if not exists set_entries_workout_exercise_idx on set_entries (workout_exercise_id);
create index if not exists workout_exercises_session_idx on workout_exercises (workout_session_id);
create index if not exists food_entries_food_idx on food_entries (food_id);
-- ... isto za vseh ~40 FK robov iz fk_constraints_test.dart

-- Partial index za "žive" vrstice — večina pull-ov ne rabi tombstonov:
create index if not exists food_entries_live_idx
  on food_entries (user_id, updated_at) where deleted_at is null;
```

Preveri po deploy-u v Dashboard → Advisors → Performance; Supabase sam
javi "unindexed foreign keys" in "unused index".

---

## 4. Pull ni paginiran — tiha izguba vrstic

`supabase_sync_backend_service.dart`:

```dart
final rows = await _client.from(table).select()
    .eq('user_id', userId)
    .gt('updated_at', since.toUtc().toIso8601String());
```

Ni `.order()`, ni `.range()`, ni `.limit()`.

Supabase ima privzeto **`db-max-rows = 1000`** (API Settings → Max rows).
PostgREST torej vrne prvih 1000 vrstic v **nedefiniranem vrstnem redu**.
`_pullTable` nato nastavi kurzor na `max(updated_at)` vrnjene serije. Vse
vrstice z manjšim `updated_at`, ki v teh 1000 niso bile, so **za vedno
preskočene** — kurzor je šel mimo njih.

To zadene točno tam, kjer boli: prva sinhronizacija na novi napravi za račun
z leti `set_entries`.

Popravek:

```dart
@override
Future<List<Map<String, dynamic>>> pull(String table, {
  required String userId, required DateTime since,
}) async {
  const page = 500;
  final out = <Map<String, dynamic>>[];
  var cursor = since;
  while (true) {
    final rows = await _client.from(table).select()
        .eq('user_id', userId)
        .gt('updated_at', cursor.toUtc().toIso8601String())
        .order('updated_at', ascending: true)
        .order('id', ascending: true)          // deterministični tie-break
        .limit(page);
    final list = (rows as List).cast<Map<String, dynamic>>();
    out.addAll(list);
    if (list.length < page) break;
    cursor = DateTime.parse(list.last['updated_at'] as String);
  }
  return out;
}
```

Pozor na isti robni primer kot pri tombstonih: skupina vrstic z **istim**
`updated_at` (kaskadni upsert) je lahko prerezana na meji strani. Zato
`.order('id')` kot drugi ključ in — če hočeš strogo — keyset paginacija po
`(updated_at, id)` namesto samo po `updated_at`.

Isti problem ima `pullExistingIds()` (`_fullReconcile`): `select('id')` brez
limita → tudi ta se ustavi pri 1000 in `_fullReconcile` bi pobrisal lokalne
vrstice, ki jih ni videl. **To je nevarnejše od §4 zgoraj**, ker
`_fullReconcile` briše. Nujno paginirati po `id`.

---

## 5. Hrana v javni bazi (`product_catalogue`)

### Kako trenutno teče

1. Skeniran barcode → lokalni Drift katalog (44.913 vrstic iz workbooka).
2. Miss → `ProductCatalogueRepository.lookupByBarcode()` — direkten
   `select ... eq('barcode') maybeSingle()` na javni tabeli
   (RLS: `for select using (true)`).
3. Miss → uporabnik fotografira izdelek → `gemini-analyze` kind
   `barcode_product` (Google Search grounding) → uporabnik **uredi in
   potrdi** v `BarcodeProductReviewDialog` → shrani lokalno **in**
   `functions.invoke('product-catalogue-publish')`.
4. Edge Function piše s service-role ključem, `on_conflict=barcode`,
   `resolution=merge-duplicates`.

Model je pravilno zastavljen: **klient nikoli ne piše neposredno** v skupno
tabelo, RLS nima insert/update policy-ja, edina pot je funkcija za JWT.

### Kaj manjka, preden gre to v produkcijo

**a) Nič validacije vhoda.** Funkcija zahteva le `barcode`, `name`,
`kcalPer100g`. Sprejme `kcal_per_100g = 999999`, prazen `name`, barcode
`"abc"`. Dodaj v funkcijo in/ali kot CHECK constraint:

```sql
alter table product_catalogue
  add constraint product_catalogue_barcode_format
    check (barcode ~ '^[0-9]{8,14}$'),
  add constraint product_catalogue_kcal_sane
    check (kcal_per_100g >= 0 and kcal_per_100g <= 900),
  add constraint product_catalogue_macros_sane
    check (protein_per_100g between 0 and 100
       and carbs_per_100g between 0 and 100
       and fat_per_100g   between 0 and 100),
  add constraint product_catalogue_name_len
    check (char_length(btrim(name)) between 2 and 200);
```

Plus mehka kontrola: `kcal ≈ 4·P + 4·C + 9·F ± 20 %`. Če ne drži, ne
zavrni — označi `needs_review = true`.

**b) `merge-duplicates` pomeni, da zadnji povozi vse.** Kdorkoli
skenira isti barcode, prepiše prejšnji vnos brez sledi. To je *shared*
tabela — en slab vnos pokvari podatek vsem. Priporočena sprememba sheme:

```sql
-- Predlogi, ne resnica.
create table product_catalogue_submissions (
  id uuid primary key default gen_random_uuid(),
  barcode text not null,
  contributed_by uuid references auth.users(id) on delete set null,
  payload jsonb not null,
  confidence double precision,
  source text not null default 'gemini',
  created_at timestamptz not null default now()
);
create index on product_catalogue_submissions (barcode, created_at desc);

-- Objavljena resnica ostane product_catalogue, dobi pa:
alter table product_catalogue
  add column submission_count integer not null default 1,
  add column confidence double precision,
  add column verified boolean not null default false,
  add column needs_review boolean not null default false,
  add column last_source text;
```

Pravilo objave v funkciji: prvi vnos objavi takoj z `verified = false`.
Naslednji vnos za isti barcode **ne prepiše** verified vrstice; če se
makro vrednosti ujemajo z obstoječimi (±10 %), poveča `submission_count`
in pri ≥ 2 postavi `verified = true`. Če se **ne** ujemajo, gre samo v
`submissions` in postavi `needs_review = true`. Ročni pregled kasneje.

**c) Rate limit na prispevke.** Zdaj lahko en račun objavi 10.000 izdelkov
v minuti. V funkcijo:

```ts
// pred upsertom
const { count } = await countSubmissionsLastHour(contributedBy);
if (count > 30) return json({ error: "Rate limit." }, 429);
```

ali čisto v SQL — `create index on product_catalogue (contributed_by, created_at)`
+ preverjanje v funkciji.

**d) Ni indeksa za iskanje po imenu.** Ko boš hotel "poišči izdelek po
imenu" v javnem katalogu (ne samo po barcode), rabiš:

```sql
create extension if not exists pg_trgm;
create index product_catalogue_name_trgm_idx
  on product_catalogue using gin (name gin_trgm_ops);
create index product_catalogue_brand_idx on product_catalogue (brand);
```

**e) GDPR/pravno.** `contributed_by` je osebni podatek na javno berljivi
tabeli. Vsak prijavljen uporabnik lahko naredi
`select contributed_by from product_catalogue` in dobi seznam UUID-jev.
Ni katastrofa (UUID ni ime), ampak pravilneje je stolpec skriti:

```sql
revoke select (contributed_by) on product_catalogue from anon, authenticated;
```

ali objavo brati skozi view, ki tega stolpca nima. `docs/PRIVACY_POLICY.md`
naj to izrecno omenja ("prispevani izdelki postanejo javni").

**f) Zapisi so trenutno nepovratni.** Ni `deleted_at`, ni načina, da bi
sporen izdelek umaknil. Dodaj soft-delete + filter v `lookupByBarcode`.

**g) Gemini `barcode_product` ne shrani dokaza.** Rezultat grounded iskanja
se zavrže. Shrani `payload.groundingMetadata` (URL-je virov) v
`submissions.payload` — brez tega ni načina preveriti, od kod je številka.

---

## 6. `gemini-analyze` — stroški in zloraba

Funkcija je varna glede ključa, **ni pa varna glede računa**.

- **Ni rate-limita.** Vsak prijavljen uporabnik lahko pošlje 12 MB sliko
  v zanki. Pri `gemini-2.0-flash` je to hitro resen strošek. Dodaj števec
  na uporabnika (tabela `ai_usage (user_id, day, calls)` + `upsert`
  z `on conflict do update set calls = calls + 1`, zavrni nad kvoto).
- **Ni logiranja porabe.** Ne veš, koliko klicev kdo dela in katera
  `kind` je najdražja. Ista tabela to reši.
- **Timeout 35 s, Edge Function limit je 150 s wall-clock** — v redu, a
  `body_fat_estimate` z več slikami lahko pride blizu. Omeji število slik
  (npr. max 4).
- **12 MB base64 na sliko** je previsoko: base64 je +33 %, torej ~9 MB
  originala. Stisni na klientu na ≤ 1600 px / ~1,5 MB, in v funkciji
  spusti limit na 2 MB. Prihranek pri Gemini tokenih je velik.
- **CORS `Access-Control-Allow-Origin: "*"`** na vseh treh funkcijah. Za
  mobilno aplikacijo ni potrebno; za `verify_jwt = true` funkcijo ni
  luknja, je pa nepotrebna površina. Omeji na dejansko potrebne izvore
  ali odstrani.
- **Napake se pošiljajo generično** (`502 "Gemini analysis failed"`) — v
  redu za uporabnika, a `console.error` je edina sled. Vključi
  Sentry/log drain, sicer ne boš vedel, ali AI pot sploh deluje v
  produkciji.

---

## 7. Realtime — 37 kanalov na napravo

`realtimeHints()` odpre **en kanal na sinhronizirano tabelo** plus enega za
tombstone — pri 38 tabelah je to 39 `channel().subscribe()` klicev ob
vsakem zagonu, vsak s `postgres_changes` filtrom na `user_id`.

Posledice:
- Supabase Realtime ima rate limit na *join*-e kanalov (privzeto 100/s na
  projekt). Deset naprav, ki se hkrati prebudijo, ta limit preseže in del
  naročnin tiho odpove — natanko tisto, kar je `0005` že enkrat popravil.
- Vsak `postgres_changes` filter pomeni delo na strani WAL dekodirnika za
  vsako spremembo, za vsakega naročnika.

Boljša oblika: **en kanal, en broadcast**. Trigger (isti vzorec kot
`buddy_broadcast_event`) pošlje `realtime.send('{"table":"..."}', 'sync_hint',
'sync:' || user_id, true)`, klient posluša en sam topic `sync:<uid>` in iz
payloada prebere, katero tabelo naj pullа. Poleg tega je RLS na
`realtime.messages` že vzpostavljen vzorec v `0011`.

To je večji poseg — zabeleži kot nalogo, ne kot hotfix.

---

## 8. Obravnava napak v sync backendu

Iz audita 26. 8., še vedno velja:

- `SupabaseSyncBackendService` **nima nobenega `try/catch`**. `401 JWT
  expired` in `23503 foreign_key_violation` sta oba samo `e.toString()` v
  `last_error` in oba retry-jata 8-krat. Potekel token torej **karantenira
  cel outbox v ~20 minutah** namesto da bi sprožil refresh.
- Popravek: `on PostgrestException catch (e)` in razvrsti po
  `e.code`:
  - `PGRST301` / `401` → ne štej poskusa, sproži `refreshSession()`.
  - `23503` (FK) → pusti retry (self-heal, kot je opisano v DEBT.md).
  - `PGRST204` / `42P01` (manjkajoč stolpec/tabela) → **takoj karantena
    + glasna napaka**, retry nima smisla, in to je natanko §2.
  - `23505` → LWW, obravnavaj kot uspeh.
- **Ni poti za "retry karantenirane vrstice".** Po vsaki uporabljeni
  migraciji jih je treba ročno odklenti. Dodaj metodo
  `SyncService.retryQuarantined()` in gumb v Profile → Sync diagnostics.
- `pushOnce`/`pullAll` iz `Timer.periodic` z zavrženim Future in brez
  `catch` — uncaught async error vsakih 20 s. Ovij v `unawaited(... .catchError(...))`.

---

## 9. Storage

`user-photos` bucket je pravilno privaten z per-user folder RLS. Manjka:

- **Nobene kvote na uporabnika.** 10 MB/datoteko × neomejeno datotek.
  Dodaj števec ali pg_cron job, ki šteje `storage.objects` po uporabniku.
- **Ni lifecycle politike** — izbrisane fotografije napredka ostanejo,
  če klient ne pokliče delete. `delete-account` jih počisti, običajen
  izbris posamezne fotografije pa ni preverjen.
- **Ni transformacij** — polnoresolucijska fotografija se prenaša tudi za
  thumbnail. Supabase image transformations (`?width=200`) so na Pro planu;
  do takrat generiraj thumbnail na klientu in naloži oba.
- Bucket ni omenjen v nobeni migraciji po `0008` — preveri, da je res
  ustvarjen na `ldzgyzigvbwofbswitrv` in ne le na SummitSki projektu.

---

## 10. Operativa

- **Ni CI-ja.** `.github/workflows` ne obstaja. Minimalno bi rad imel
  workflow, ki na push na `main` požene `flutter analyze` + `flutter test`
  + `dart run tool/check_structure.dart`, in ločen ročni workflow za
  `supabase db push` + `functions deploy` z `SUPABASE_ACCESS_TOKEN` iz
  GitHub Secrets.
- **Ni backup plana.** Free tier ima dnevne backupe s 7-dnevno retencijo
  in **brez** PITR. Za produkcijo z uporabniškimi podatki je to premalo —
  bodisi Pro (PITR), bodisi nočni `pg_dump` v ločen storage.
- **Ni staging projekta.** Vse migracije gredo direktno v produkcijo.
  Drugi Supabase projekt (`herculex-staging`) + `--project-ref` preklop
  je poceni in odpravi razred napak, ki jih je ta repo že dvakrat imel
  (napačen projekt, neapplied migracije).
- **Auth**: e-mail verifikacija je odložena na v2 (DEBT.md), leaked-password
  zaščita je Pro. Preden gre v App Store, vsaj vklopi:
  - Auth → Rate limits (privzeti so ohlapni),
  - Auth → Sessions → refresh token rotation + reuse detection,
  - potrditev, da so redirect URL-ji omejeni na `io.supabase.herculex://`.
- **Dashboard → Advisors** (Security + Performance) preglej po vsakem
  `db push` — ujame `search_path` na funkcijah, neindeksirane FK-je,
  RLS luknje.
- `.secrets/live_sync.json` kaže na napačen projekt (blokira
  `test/sync/live_buddy_test.dart`, glej `.planning/STATE.md`). Popravi
  ob istem prehodu kot §1.

---

## 11. Predlagan vrstni red dela

1. `GEMINI_API_KEY` + `GEMINI_MODEL` na `ldzgyzigvbwofbswitrv`, redeploy,
   rotacija starega ključa. (§1)
2. `db push` za `0015` + `0016`, nato retry karanteniranih vrstic. (§2)
3. Migracija `0017_sync_indexes.sql` — `(user_id, updated_at)` na vseh
   sinhroniziranih tabelah + FK indeksi. (§3)
4. Paginacija v `pull()` **in** `pullExistingIds()`. (§4) — to je edina
   točka na seznamu, kjer se podatki lahko tiho izgubijo.
5. Razvrščanje napak v `SupabaseSyncBackendService` + `retryQuarantined()`. (§8)
6. Migracija `0018_product_catalogue_hardening.sql` — CHECK constrainti,
   `submissions` tabela, `verified`/`needs_review`, trgm indeks, skritje
   `contributed_by`. (§5)
7. `ai_usage` tabela + rate limit v `gemini-analyze`, manjši image limit. (§6)
8. Staging projekt + CI workflow. (§10)
9. Realtime konsolidacija na en broadcast kanal. (§7)


---

## 12. Dnevnik — kaj je narejeno (2026-09-02, druga seja)

Točke 3, 4 in 8 so implementirane v kodi. Točki 1 in 2 zahtevata omrežni
dostop do Supabase, ki ga to okolje nima (egress do `*.supabase.co` je
blokiran, CLI v `node_modules` je Windows-only in ne teče v Linux VM) — to
moraš pognati sam, ukazi so v §1 in §2.

### Novo / spremenjeno

| Datoteka | Kaj |
|---|---|
| `supabase/migrations/0017_sync_indexes.sql` | **novo.** 40 delta-pull indeksov `(user_id, updated_at, id)`, 35 FK indeksov, trgm indeks na `product_catalogue.name`, dva buddy indeksa. Vse `if not exists`. |
| `lib/data/sync/sync_backend_service.dart` | `pullPageSize`, `SyncErrorKind`, `SyncBackendException`. |
| `lib/data/sync/supabase_sync_backend_service.dart` | Keyset paginacija v `pull()` in `pullExistingIds()`; `_guard`/`_classify` na vseh metodah. |
| `lib/data/sync/sync_service.dart` | `_pushOne` veje po vrsti napake; `retryQuarantined()`; `_fireAndLog` okoli obeh `Timer.periodic`. |
| `test/sync/fake_sync_backend_service.dart` | `upsertFailureKind` za tipizirane napake. |
| `test/sync/sync_error_classification_test.dart` | **novo.** 7 testov. |

### Podrobnosti

**Paginacija** je keyset po `(updated_at, id)`, ne offset. `id` ni okras:
kaskadni zapis ožigosa več vrstic z enim `now()`, zato lahko meja strani pade
sredi skupine z istim `updated_at`. Paginacija samo po `updated_at` bi v tem
primeru bodisi zaciklala (polna stran identičnih časovnih žigov nikoli ne
premakne kurzorja) bodisi preskočila ostanek skupine. Prva stran uporabi
navaden `.gt()`, naslednje `.or(updated_at.gt.X,and(updated_at.eq.X,id.gt.Y))`.

`pullExistingIds()` paginira po `id` (primarni ključ, unikaten in totalno
urejen). Ta je bil nevarnejši od `pull()`, ker `_fullReconcile` na podlagi
tega seznama **briše** lokalne vrstice.

`pullPageSize = 500` je namerno pod privzetim `db-max-rows = 1000`, da o meji
strani odloča koda in ne nastavitev v dashboardu.

**Razvrščanje napak** — `_classify()` mapira `PostgrestException` na
`SyncErrorKind`:

| Koda | Kind | Obnašanje v `_pushOne` |
|---|---|---|
| `PGRST301/302`, 401, 403, sporočilo z "jwt" | `auth` | **Ne šteje poskusa**, retry čez 30 s |
| `PGRST204/205`, `42P01`, `42703` | `schema` | **Takojšnja karantena** + glasen log |
| `23503` | `foreignKey` | Običajen backoff (self-heal) |
| `23505` | `conflict` | Potrjeno kot uspeh, op se izbriše |
| Socket/Timeout/Http | `transient` | Običajen backoff |

Netipizirane napake (npr. lokalni Drift failure med gradnjo payloada) padejo
v generični `catch`, ki se obnaša točno kot prej — obstoječi testi so
nedotaknjeni.

**`retryQuarantined()`** je nova metoda na `SyncService`. Karantena je bila do
zdaj dokončna (`pushOnce` filtrira `attempts < maxPushAttempts`), tudi čez
restart aplikacije. To je pravilno za resnično pokvarjeno vrstico in narobe
za pogosti primer: neaplicirana migracija karantenira celotno tabelo, potem pa
ni bilo poti nazaj brez ročnega urejanja baze. **To poženi po `db push` za
0015/0016.** Namerno ne pushne sama — klicatelj odloči kdaj.

### Kaj ostane

- [ ] `GEMINI_API_KEY` verificirati na `ldzgyzigvbwofbswitrv` (§1)
- [ ] `db push` za `0015`, `0016`, `0017` (§2, §3)
- [ ] `retryQuarantined()` priklopiti na gumb v Profile → Sync diagnostics
- [ ] `flutter analyze` + `flutter test` (v tem okolju ni Dart SDK-ja)
- [ ] `0018_product_catalogue_hardening.sql` (§5)
- [ ] `ai_usage` + rate limit v `gemini-analyze` (§6)


---

## 13. Dnevnik — točki 5 in 6 (2026-09-02, tretja seja)

### Novo / spremenjeno

| Datoteka | Kaj |
|---|---|
| `supabase/migrations/0018_shared_data_hardening.sql` | **novo.** CHECK constrainti, `product_catalogue_submissions`, konsenz stolpci, soft-delete, `product_catalogue_submit()` RPC, `ai_usage` + `ai_usage_bump()` RPC, pg_cron GC. |
| `supabase/functions/product-catalogue-publish/index.ts` | Ne piše več neposredno v tabelo — kliče RPC. Dodana oblika-preverjanje in 429 na rate limit. |
| `supabase/functions/gemini-analyze/index.ts` | Kvota pred klicem, `callerUserId`, meja slike 12 MB → 2,6 MB base64, max 4 slike, `groundingSources` v odgovoru. |
| `lib/features/nutrition/data/product_catalogue_repository.dart` | Eksplicitni seznam stolpcev (obvezno!), `verified`/`needsReview`/`submissionCount`, `confidence`/`evidence` na `publish()`. |
| `lib/features/nutrition/data/gemini_food_analyzer_service.dart` | `groundingSources` + `evidence` na `GeminiBarcodeProductResult`. |
| `lib/features/nutrition/presentation/dialogs/barcode_product_review_dialog.dart` | Poda `confidence` in `evidence` v `publish()`. |

### Konsenz — kako se zdaj obnaša

Vsa logika je v `product_catalogue_submit()`, ker je konsenz
read-modify-write: v TypeScriptu bi bila to dva HTTP klica z dirko med
njima (dva hkratna skena istega izdelka bi oba prebrala `submission_count = 1`
in oba zapisala 2). V Postgresu je vse pod enim `for update`.

| Stanje | Nova oddaja | Izid |
|---|---|---|
| Barcode še ne obstaja | — | `published`, `verified = false` |
| Obstaja, ujema se (±10 %) | — | `confirmed`, `verified = true`, `submission_count++` |
| Obstaja, **verificiran**, ne ujema se | — | `conflict` — objavljeni podatek se **NE** povozi, dobi `needs_review` |
| Obstaja, neverificiran, ne ujema se | — | `conflict` — novejši prevzame, števec na 1, `needs_review` |
| kcal se ne ujema z makri (Atwater ±25 %) | — | `rejected`, gre samo v `submissions` |
| >30 oddaj v zadnji uri | — | `P0001` → HTTP 429 |

### ⚠️ Nujno: klient in migracija gresta skupaj

`0018` naredi `revoke select (contributed_by)`. Po tem `select *` na
`product_catalogue` vrne **42501**. Zato ima `lookupByBarcode()` zdaj
eksplicitni seznam stolpcev. **Če deployaš migracijo brez novega klienta, se
iskanje po barcode zlomi za obstoječe naprave.** Bodisi obojega hkrati,
bodisi najprej klienta.

### Odkrito ob poti, ni popravljeno

`supplement_edit_sheet.dart` objavlja v `product_catalogue` vrednosti **na
odmerek**, ne na 100 g (`servingGrams: doseValue`, hranila iz `_nutrients`
brez pretvorbe). To je bilo narobe že prej; z 0018 se bo del teh oddaj zdaj
tiho zavrnil (`rejected`) na Atwater preverjanju namesto da bi pokvaril
skupni katalog — kar je boljše, a ni popravek. Pravi popravek je pretvorba
na 100 g pred objavo, ali ločena `supplement_catalogue` tabela.

### Kaj ostane

- [ ] `db push` za `0015`, `0016`, `0017`, `0018`
- [ ] `supabase functions deploy product-catalogue-publish gemini-analyze`
- [ ] Klient in `0018` deployati skupaj (glej opozorilo zgoraj)
- [ ] `SyncService.retryQuarantined()` po `db push` + gumb v Sync diagnostics
- [ ] `flutter analyze` + `flutter test`
- [ ] UI: prikazati `verified` / `needs_review` ob community izdelku
- [ ] Supplement per-dose → per-100 g pretvorba
- [ ] §7 (realtime kanali), §10 (staging + CI + backup)


---

## 14. Dnevnik — 0018 dokončan (2026-09-02, četrta seja)

`product_catalogue_submit` je zdaj **klican neposredno s klienta**, ne prek
Edge Functiona. Sprememba je narejena v `0018` in ne v novi migraciji, ker
`0018` še ni applied — pravilo o nedotakljivosti velja šele, ko se ime
pojavi v `migration list` tudi v Remote stolpcu.

| Datoteka | Kaj |
|---|---|
| `supabase/migrations/0018_shared_data_hardening.sql` | `product_catalogue_submit` brez `p_user_id`, bere `auth.uid()`; `grant execute ... to authenticated`. Nov podpis: `(text, jsonb, text, double precision)`. |
| `lib/features/nutrition/data/product_catalogue_repository.dart` | `functions.invoke('product-catalogue-publish')` → `rpc('product_catalogue_submit')`. Ključi v `p_payload` so imena Postgres stolpcev, ne camelCase. |
| `supabase/config.toml` | `[functions.product-catalogue-publish]` odstranjen, z zapisanim razlogom. |
| `supabase/functions/product-catalogue-publish/` | Premaknjeno v `supabase/_to_delete/` (brisanje na disku ni bilo dovoljeno). |

### Zakaj je to varnejše, ne samo hitrejše

1. **Uporabnikov id ni več parameter.** Dokler je bil, je bila varnost
   odvisna od predpostavke, da je edini klicatelj strežnik s service-role
   ključem — predpostavke, ki jo prihodnji refaktor lahko tiho podre. Zdaj
   je identiteta neponaredljiva po konstrukciji.
2. **Service-role ključ v tej poti ne nastopa več.** Vsaka rutina, ki ga
   uporablja, je potencialna IDOR luknja, ker je RLS znotraj nje izklopljen.
3. Ni hladnega zagona in ni dveh HTTP obhodov namesto enega.

Ker je funkcija zdaj dosegljiva vsakemu prijavljenemu uporabniku, je
**omejitev 30 oddaj/uro nosilna, ne higienska.**

### Nasprotni primer, ki ga velja zapomniti

`ai_usage_bump` **obdrži** `p_user_id` in ostane revoked. Razlika ni v tem,
ali je rutina definer, ampak čigavo odločitev sprejema:
`product_catalogue_submit` odloča o uporabnikovih lastnih prispevkih,
`ai_usage_bump` pa o njegovi kvoti in sprejme `p_daily_limit` kot argument.
Če bi ga smel klicati klient, bi si kvoto nastavil sam. To je zdaj zapisano
tudi v komentarju nad funkcijo.

### Ročno, ker brisanje na disku ni dovoljeno

```powershell
Remove-Item -Recurse -Force supabase\_to_delete
npx supabase functions delete product-catalogue-publish --project-ref ldzgyzigvbwofbswitrv
```

Drugi ukaz je obvezen: funkcija je na strežniku še vedno deployana in bo
delovala, dokler je ne odstraniš — kar pomeni **dve pisalni poti** v isto
tabelo, od katerih ena še vedno piše s service-role ključem.

## 15. Dnevnik — `_shared/` (2026-09-03)

Zadnja neopravljena postavka iz §7/§8 (`edge-functions-prod-arhitektura.md`):
`callerUserId()`, `corsHeaders` in `json()` so bili podvojeni v treh
kopijah (`gemini-analyze`, `delete-account`, in `_to_delete`-jeva
`product-catalogue-publish`). Zdaj živijo v `supabase/functions/_shared/`
(`auth.ts`, `cors.ts`, `json.ts`) — Supabase CLI mapo `_shared` prepozna in
jo zapakira z vsako funkcijo. `gemini-analyze` in `delete-account` ju
uvažata; obe stari kopiji odstranjeni.

Pripete verzije `jsr:`/`npm:` uvozov (druga polovica iste postavke) ni bilo
treba dodajati: nobena od dveh funkcij ne uvaža `@supabase/supabase-js` ali
katerekoli druge zunanje odvisnosti — obe govorita s PostgREST/Auth/Storage
prek golega `fetch`, kar je bil namerna odločitev v `gemini-analyze` (glej
komentar na vrhu datoteke) že prej.

Preverjeno: `flutter analyze` po spremembi še vedno 0 napak, 48 opozoril/info
(nespremenjeno proti stanju pred to sejo — spremembe so izključno v
`supabase/functions/`, brez Deno na voljo za typecheck teh datotek, zato
ostaja ročni pregled edino preverjanje).
