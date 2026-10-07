# Edge Functions — priporočena produkcijska arhitektura

Datum: 2026-09-02
Velja za: Supabase projekt `ldzgyzigvbwofbswitrv`

Kratek odgovor na vprašanje "koliko in katere funkcije za prod": **dve.**
Trenutno jih imaš tri, in ena od njih ne bi smela obstajati.

Ta dokument pove, po katerem pravilu se to odloča, zakaj je ravno ta nabor
pravi za Herculex, in kaj postaviš namesto tega, kar odpade.

---

## 1. Pravilo odločanja

Edge Function je upravičena natanko takrat, ko je **vsaj eno** od tega res:

1. **Nosi skrivnost, ki je klient ne sme nikoli imeti** — Gemini ključ,
   service-role ključ, webhook signing secret.
2. **Potrebuje pooblastila, ki jih RLS ne more podeliti** — brisanje iz
   `auth.users`, dostop do Admin API.
3. **Govori s tretjo osebo** — sprejema webhook, pošilja push, kliče
   plačilni sistem.

Če ni nobeno od tega res, **stvar spada v Postgres**: RLS plus
`SECURITY DEFINER` RPC. To ni stvar okusa — je razlika v treh merljivih
stvareh:

| | Edge Function | Postgres RPC |
|---|---|---|
| Hladen zagon | 200–500 ms | ni ga |
| Round-tripi za read-modify-write | 2+ (in dirka vmes) | 1, atomarno pod `for update` |
| Kdo vsili lastništvo | tvoja koda | `auth.uid()` + RLS |
| Kaj se zgodi ob napaki na pol poti | delno zapisano stanje | rollback |
| Površina za IDOR | service-role ključ obide RLS pri **vsaki** poizvedbi | ni je |

Zadnja vrstica je najpomembnejša. Vsaka funkcija, ki dela s service-role
ključem, je potencialna IDOR luknja: RLS je izklopljen, in edino, kar
preprečuje, da bi uporabnik A pisal podatke uporabnika B, je pravilnost
tvojega TypeScripta. Vsaka taka funkcija manj je en razred napak manj.

Ta projekt to že zna — `0011_buddy_sessions.sql` je natanko ta vzorec:
`buddy_create_session()`, `buddy_join_session()`, `buddy_append_event()` so
`SECURITY DEFINER` z `set search_path = ''`, berejo `auth.uid()` same in so
`grant execute ... to authenticated`. Nobene Edge Functiona ni v tej poti in
ravno zato je varna in hitra.

---

## 2. Priporočen produkcijski nabor

| Funkcija | Zakaj obstaja | `verify_jwt` | Status |
|---|---|---|---|
| `gemini-analyze` | Nosi `GEMINI_API_KEY`. Pravilo 1. | `true` | **obdrži** |
| `delete-account` | Rabi Admin API za `auth.users`. Pravilo 2. | `true` | **obdrži, nespremenjena** |
| ~~`product-catalogue-publish`~~ | Nič od naštetega. | — | **izbriši** |

To je vse. Dve funkciji za celotno aplikacijo z 40 sinhroniziranimi
tabelami, deljenim katalogom, buddy sejami in AI analizo.

---

## 3. `product-catalogue-publish` → RPC

### Zakaj odpade

`0012` v komentarju pravi, da je Edge Function "edina pisalna pot po
zasnovi". To je bilo pravilno takrat, ker `product_catalogue` nima
insert/update politike — a sklep je bil narejen, preden je `0011` pokazal
boljši vzorec. Funkcija ne nosi nobene skrivnosti, ki bi bila njena; rabi
service-role ključ **samo zato, da obide RLS**, kar `SECURITY DEFINER` RPC
naredi bolj varno in brez hladnega zagona.

Konkretno, kar pridobiš:

- **Ni več `p_user_id` kot argumenta.** Trenutni podpis v `0018` sprejme
  uporabnikov id kot parameter — kar je varno samo, dokler je edini
  klicatelj funkcija s service-role ključem. RPC, ki bere `auth.uid()` sam,
  te predpostavke ne rabi: identitete ni mogoče ponarediti, tudi če bi
  kdo klical RPC neposredno.
- **Ena poteza po žici namesto dveh.** Klient → PostgREST → funkcija, konec.
  Zdaj je klient → Edge Function (hladen zagon) → PostgREST → funkcija.
- **Ni ključa, ki bi lahko ušel.** Service-role ključ v tej poti preprosto
  ne nastopa več.

### Kaj spremeniti

`0018` **še ni applied**, zato ga smeš urediti neposredno — pravilo o
nedotakljivosti migracij velja šele, ko se ime pojavi v `migration list`
tudi v Remote stolpcu.

```sql
-- namesto (p_user_id uuid, p_barcode text, ...)
create or replace function public.product_catalogue_submit(
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
  v_uid uuid := auth.uid();
  ...
begin
  if v_uid is null then
    raise exception 'not authenticated' using errcode = '42501';
  end if;
  -- naprej isto; povsod, kjer je bil p_user_id, je zdaj v_uid
```

in namesto `revoke execute ... from authenticated`:

```sql
grant execute on function public.product_catalogue_submit(text, jsonb, text, double precision)
  to authenticated;
```

Rate limit (30 oddaj/uro) v telesu funkcije s tem **ni več opcijski** — je
edina obramba pred zlorabo, ker je funkcija zdaj neposredno dosegljiva. Že
je notri; ne odstranjuj je.

Na Dart strani `ProductCatalogueRepository.publish()` zamenja
`functions.invoke('product-catalogue-publish', ...)` z:

```dart
await Supabase.instance.client.rpc('product_catalogue_submit', params: {
  'p_barcode': barcode,
  'p_payload': { /* isti jsonb kot doslej */ },
  'p_source': 'gemini',
  'p_confidence': confidence,
});
```

Nato iz `config.toml` odstrani `[functions.product-catalogue-publish]`,
izbriši mapo, in `npx supabase functions delete product-catalogue-publish`.

### Isto velja za `ai_usage_bump` — ampak obratno

`ai_usage_bump` **mora** ostati revoked in klican samo s service-role
ključem iz `gemini-analyze`. Razlog je razlika, ki jo velja razumeti:
`product_catalogue_submit` odloča o *uporabnikovih lastnih* podatkih in mu
lahko zaupamo identiteto; `ai_usage_bump` odloča o *njegovi kvoti* in
sprejme `p_daily_limit` kot argument. Če bi ga smel klicati klient, bi si
kvoto nastavil sam. Zato je tam `p_user_id` kot parameter pravilen — kliče
ga samo strežnik.

---

## 4. `gemini-analyze` v produkcijski obliki

To je edina funkcija, ki nosi resnično tveganje (denar in latenca), zato je
vredna več pozornosti kot ostalo skupaj.

**Ostane ena funkcija z več `kind`-i, ne osem funkcij.** Delitev po `kind`
bi pomnožila hladne zagone in podvojila skupno infrastrukturo (prompt
gradnja, validacija slik, kvota) — brez kakršne koli koristi, ker je
skrivnost ista in deploy je tako ali tako en.

**Kataloga vanjo ne dodajaj.** Predlagani `kind: "product_catalogue_submit"`
zmeša AI proxy s pisalno potjo v deljene podatke: en deploy ogrozi oboje, in
funkcija, ki je bila upravičena po pravilu 1, nenadoma dela stvari po
pravilu 2. Po §3 ta pot itak izgine.

Kar mora imeti pred produkcijo:

- [x] `verify_jwt = true` — je.
- [x] Dnevna kvota na uporabnika (`ai_usage`) — v `0018`.
- [x] Meja velikosti in števila slik — 2,6 MB base64, max 4.
- [ ] **Sledenje stroška, ne samo klicev.** `ai_usage.calls` pove, koliko
      klicev; ne pove, koliko tokenov. Gemini vrne `usageMetadata` z
      `promptTokenCount` / `candidatesTokenCount` — shrani ju v dodatna
      stolpca in šele takrat veš, kateri `kind` je drag.
- [ ] **Fallback model.** Ob `429`/`503` z Googla trenutno vrneš 502. En
      retry na `gemini-2.0-flash-lite` (ali karkoli je takrat cenejša
      varianta) je razlika med "AI ne dela" in "AI je počasnejši".
- [ ] **Ožji CORS.** `Access-Control-Allow-Origin: "*"` na mobilni
      aplikaciji ni potreben. Pri `verify_jwt = true` ni luknja, je pa
      nepotrebna površina.
- [ ] **Prompti v ločene datoteke.** `index.ts` je ~800 vrstic, od tega
      večina prompt besedila. `supabase/functions/gemini-analyze/prompts.ts`
      naredi diff berljiv in prepreči, da bi kdo "počistil" prompt in s tem
      tiho pokvaril parsanje na Dart strani — kar se je pri
      `supplementPhotoPrompt` že skoraj zgodilo (našteti ključi hranil so
      pogodba z `nutrient_definitions.dart`, ne okras).

---

## 5. `delete-account` — pusti pri miru

Edini upravičeni service-role primer v projektu in edini, ki ga RPC ne more
nadomestiti: `auth.users` ni dosegljiv iz `authenticated` role in brisanje
gre skozi Admin API, ne skozi SQL.

Zasnova je že pravilna — id se bere izključno iz preverjenega JWT (nikoli iz
telesa zahtevka), brisanje je remote-first, in storage se pospravi pred točko
brez vrnitve. Ne spreminjaj.

Ena stvar, ki jo velja preveriti pred oddajo v trgovino: `0008` je bil ena od
migracij, ki so prvotno šle v napačen projekt. Potrdi, da `user-photos`
bucket res obstaja na `ldzgyzigvbwofbswitrv`, sicer `deleteUserPhotos()` tiho
ne naredi ničesar.

---

## 6. Kar boš rabil kasneje (in kdaj)

Nobene od teh ne gradi vnaprej. Vsaka pride, ko pride njena funkcionalnost.

| Funkcija | Sproži jo | Pravilo | Opomba |
|---|---|---|---|
| `send-push` | Strežniško sprožena obvestila (konec posta, buddy povabilo) | 3 | `ONESIGNAL_APP_ID` je v `Env` deklariran, a **neuporabljen** — obvestila so danes lokalna. Ko bo to potrebno, gre par `pg_cron` → `net.http_post` → ta funkcija. |
| `payments-webhook` | Naročnina / Pro tier | 1 + 3 | `verify_jwt = **false**` (webhook nima uporabnikovega JWT), namesto tega preveri podpis pošiljatelja. To je edina funkcija v tem projektu, ki sme imeti `verify_jwt = false`, in razlog mora biti zapisan v `config.toml`, kot je pri `delete-account`. |
| `export-my-data` | GDPR člen 20 (prenosljivost) | — | **Ne rabi biti funkcija.** RPC, ki vrne `jsonb` z uporabnikovimi vrsticami, je enostavnejši in teče pod RLS. Funkcijo rabiš šele, če hočeš ZIP z datotekami iz storagea. |

### Česa ne delaj kot Edge Function

- **Agregacije za Insights** (tedenski volumen, PR-ji, korelacije) →
  materialized view + `pg_cron` refresh, ali navaden view. Funkcija, ki to
  računa, je počasnejša in obide RLS.
- **Lestvice / socialne primerjave** → view s security_invoker.
- **Čiščenje in retencija** → `pg_cron`, kot že delata `0006` in `0011`.
- **Karkoli, kar samo prebere ali zapiše uporabnikove lastne vrstice** →
  PostgREST z RLS. Ta projekt ima za to celoten sync sloj; ne obhajaj ga.

---

## 7. Skupna infrastruktura

Te štiri stvari veljajo za vse funkcije in jih je ceneje postaviti zdaj kot
kasneje.

**`supabase/functions/_shared/`.** ✅ Narejeno 2026-09-03: `callerUserId()`
(bil podvojen v treh datotekah), `corsHeaders` in `json()` zdaj živijo v
`_shared/auth.ts`, `_shared/cors.ts` in `_shared/json.ts`; `gemini-analyze`
in `delete-account` ju uvažata. Supabase CLI mapo `_shared` prepozna in jo
zapakira z vsako funkcijo.

**Pripni verzije uvozov.** `jsr:@supabase/supabase-js@2` se razreši na
karkoli je takrat najnovejše v major 2 — isti razred težave, kot ga
`docs/supabase-migrations.md` opisuje za `npx supabase@latest`. Uporabi
`jsr:@supabase/supabase-js@^2.48.0` ali `deno.json` z `imports`.

**Opazovanje.** Trenutno je `console.error` edina sled, kar pomeni, da v
produkciji ne boš vedel, ali AI pot sploh deluje, dokler se nekdo ne pritoži.
`Env.sentryDsn` je že deklariran in neuporabljen — priključi ga tako na
klientu kot v funkcijah, ali nastavi log drain. Brez tega je vsak od zgornjih
"fail-open" vzorcev slepa pega.

**Regija.** Baza je v eni regiji; funkcija, ki naredi dva klica na PostgREST,
plača latenco dvakrat, če teče drugje. Preveri, v kateri regiji je projekt in
kako se trenutna verzija platforme obnaša glede umeščanja funkcij — to je
pogosto največja neizkoriščena razlika v odzivnosti, in hkrati še en razlog,
zakaj je RPC boljši od funkcije, ki kliče RPC.

---

## 8. Vrstni red

1. ✅ Uredi `0018` — `product_catalogue_submit` naj bere `auth.uid()`, brez
   `p_user_id`, `grant execute ... to authenticated`. (Migracija še ni
   applied, zato je to urejanje in ne nova migracija.)
2. ✅ `ProductCatalogueRepository.publish()` → `rpc('product_catalogue_submit')`.
3. ✅ `gemini-analyze`: popravljen klic `ai_usage_bump` (`p_kind` dodan,
   preverjanje je `body?.allowed !== false`), polni prompti izločeni v
   `prompts.ts`, dodan fallback model in `usageMetadata` log.
4. ✅ `_shared/` (`auth.ts`, `cors.ts`, `json.ts`). Pripete verzije uvozov
   ni bilo treba dodajati — nobena od dveh funkcij ne uvaža
   `@supabase/supabase-js` ali kateregakoli drugega `jsr:`/`npm:` paketa,
   obe govorita s Postgresom/Auth/Storage prek golega `fetch`.
5. ✅ `product-catalogue-publish` premaknjena iz `supabase/functions/` v
   `supabase/_to_delete/product-catalogue-publish/` in odstranjena iz
   `config.toml` — pobriši mapo in poženi
   `npx supabase functions delete product-catalogue-publish` šele, ko je
   6. spodaj resnično opravljen (dokler prod še kliče staro funkcijo, jo
   pusti živo na strežniku).
6. Šele potem `db push` in `functions deploy`. **Ni bilo izvedeno v tej
   seji** — `0018` dotika RLS/RPC na produkcijski bazi in gre samo z eksplicitno
   človeško potrditvijo, enako kot `0015`/`0016`.
7. Sentry / log drain, preden gre prva javna verzija ven.
8. `usageMetadata` v `ai_usage`, ko boš hotel vedeti, kaj te AI dejansko stane.
