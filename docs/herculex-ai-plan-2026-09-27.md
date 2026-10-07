# Herculex AI — načrt (amandma k v2.0)

Datum: 2026-09-27
Amandma k: [`training-programs-physique-gamification-plan-2026-09-10.md`](training-programs-physique-gamification-plan-2026-09-10.md)
Pokriva: GSD faze 26–29 in razširitev faze 23 (PHYS-05–08)

---

## 1. Odločitev

Priprava programov dobi **drugo pot**. Uporabnik lahko program še naprej sestavi ročno,
ali pa ga pripravi **Herculex AI** na podlagi "učbenika" — korpusa mentalitete, po katerem
aplikacija programira. Isti korpus grounda tudi AI sloj nasvetov in tedensko poročilo.

Poleg tega ta amandma doda štiri stvari, ki jih danes ni:

1. Dream Physique **progress screen** — v kateri fazi sem, kako daleč sem, grafi teže,
   moči in training levela.
2. **Tedenska progress slika** (največ 1 na 7 dni) z AI oceno smeri.
3. **Nedeljsko tedensko poročilo** (opt-in).
4. **Adaptivni TDEE** — aplikacija meri namesto da uporabnik ugiba activity level.

In eno pravilo za znamko: vsak uporabniku viden "Gemini" postane **Herculex AI**.

### Hišno pravilo, ki se ne spremeni

`06-AI-SPEC.md` je postavil vzorec, ki velja za vse spodaj:

> Deterministični del je primaren. AI je omejen. AI nikoli ne piše neposredno v bazo.
> Uporabnik potrdi.

Jedro projekta je "varno, deterministično in razložljivo" generiranje programov — faza 17
se dobesedno imenuje *Deterministic* Program Planner. Herculex AI ne sme te lastnosti
izničiti. Zato AI **predlaga zasnovo**, `SmartProgramPlanner` pa še naprej izbere vsako
posamezno vajo. Vsi guardraili iz faz 16–21 ostanejo v veljavi in jih model ne more
pregovoriti.

Ta seam je že dokumentiran v kodi, `smart_program_planner.dart:109`:

> *"Deterministic local planner used by both Smart and Guided builder modes. Gemini may
> provide muscle priorities, but final exercise selection remains here where equipment,
> preferences and safety rules are enforceable."*

Faza 27 to razširi z zasnove na celoten brief, ne spremeni pa pravila.

---

## 2. Faza 26 — Knowledge base in znamka

### 2.1 Kje živi učbenik

Poleg `supabase/functions/gemini-analyze/prompts.ts`, torej **server-side**. Trije razlogi:

- Klient nikoli ne sme imeti `GEMINI_API_KEY` (RB-01,
  [`rb01-gemini-secret-remediation.md`](rb01-gemini-secret-remediation.md)) — vsi AI klici
  tako ali tako že tečejo skozi Edge Function.
- Korpus se ne da izvleči iz APK-ja.
- Posodobitev je `supabase functions deploy`, ne nova verzija aplikacije.

### 2.2 Pogodba korpusa

Korpus je **verzioniran** in razdeljen po namenu, tako da vsak `kind` dobi samo svoj del —
ne celotnega učbenika v vsak prompt:

| Segment | Dobijo ga | Vsebina |
|---|---|---|
| `core` | vsi grounded kinds | temeljna mentaliteta, prioritete, česa nikoli ne priporočamo |
| `programming` | `program_brief` | periodizacija, splits, volumen, progresija |
| `nutrition` | `weekly_report`, `physique_checkin` | faze, tempo, adherenca |
| `recovery` | `weekly_report`, `hercul_advice` | spanje, CNS, deload |

`knowledgeVersion` je semantična oznaka korpusa (npr. `kb-2026.10-1`). Vsak AI odgovor jo
vrne skupaj z `modelVersion`, in oboje se shrani ob rezultatu (KB-02). Brez tega čez pol
leta ni mogoče ugotoviti, kateri korpus je proizvedel kakšno priporočilo.

Vzorec za to že obstaja: `PhysiqueProgrammingProfiles` ima `modelVersion` in `source`.

### 2.3 Kvote

Danes je ena sama skupna kvota `GEMINI_DAILY_LIMIT ?? 50` na uporabnika na dan, čez vse
kinds, prek `ai_usage_bump` RPC — in ob napaki RPC-ja **fails open**, torej pusti klic
skozi. To je bilo sprejemljivo, dokler je bil AI samo foto hrane. Z generiranjem programov,
tedenskimi poročili in tedenskimi physique ocenami ni več.

KB-05: kvote po `kind`, in ob izčrpanju **fail closed** z jasnim sporočilom. Fail-open je
treba popraviti v istem prehodu — to ni feature, to je napaka pri nadzoru stroškov.

### 2.4 Hercul ostane Hercul

`lib/features/hercul/` je namenoma **ni AI**: avtorirana pravila iz `hercul_rules.json`,
deterministična izbira, dela offline, stane nič, nikoli si ne izmisli številke, in vsak
stavek se da izslediti do vrstice v JSON-u.

To ostane nedotaknjeno. Herculex AI doda **drugi kanal** nasvetov ob njem:

- `HerculSignals.all` in test, ki zavrne pravilo z neznanim signalom, se ne spremenita.
  AI kanal ne sme tihotapiti novih signalov v rule engine.
- Vsak nasvet v UI je označen z virom — pravilo ali Herculex AI.
- Brez omrežja ali brez privolitve se pokaže samo deterministični kanal, in aplikacija
  deluje enako kot danes.

### 2.5 Preimenovanje v "Herculex AI"

Približno 40 uporabniku vidnih nizov v 20 datotekah. Spremenijo se **samo vidni nizi**.
Imena razredov (`GeminiBackend`, `SupabaseGeminiBackend`, `GeminiFoodAnalyzerService`),
vrednosti `kind`, ime Edge Functiona in dokumentacija ostanejo — preimenovanje teh je
churn z migracijskim tveganjem in brez koristi za uporabnika.

Dve pasti:

- **`dream_physique_view.dart:819`** je privolitveni niz: *"I agree to send these photos to
  Google Gemini"*. Tu je imenovanje dejanskega obdelovalca bistvo privolitve, ne detajl.
  Obdelovalec mora ostati imenovan — npr. "Herculex AI (powered by Google Gemini)" — in
  pred spremembo je treba preveriti [`PRIVACY_POLICY.md`](PRIVACY_POLICY.md) in
  [`GDPR_ARTICLE_9_COMPLIANCE.md`](GDPR_ARTICLE_9_COMPLIANCE.md), ker so physique fotografije
  podatki po členu 9.
- **`gemini_food_analyzer_service.dart:24/40/52`** uporablja `'Gemini AI'` kot **podatkovno
  vrednost** — shranjeno znamko/vir na vnosu hrane, ne kot oznako v UI. Sprememba spremeni,
  kaj zapišejo nove vrstice. Odločiti se je treba, ali se zgodovinske vrstice migrirajo ali
  pustijo.

Nizi so danes mešano angleški in slovenski. Prehod ne sme tiho spremeniti jezika niza.

---

## 3. Faza 27 — Generiranje programov s Herculex AI

### 3.1 Kaj AI sme vrniti

`ProgramBuildMode` dobi četrto vrednost (danes `smart` / `guided` / `manual`).

AI vrne **program design brief** — zasnovo, ne programa:

```jsonc
{
  "knowledgeVersion": "kb-2026.10-1",
  "splitType": "upperLower",           // iz obstoječega SplitType enuma
  "daysPerWeek": 4,
  "periodizationModel": "linear",      // iz obstoječega PeriodizationModel
  "weeks": 8,
  "dayRoles": [                        // iz obstoječega DayStressRole
    {"dayIndex": 0, "role": "heavy",   "focus": "upper"},
    {"dayIndex": 1, "role": "moderate","focus": "lower"}
  ],
  "musclePriorities": [                // ista oblika kot Dream Physique
    {"muscle": "Rear Delts", "priority": "high", "why": "..."}
  ],
  "phaseIntent": "hypertrophy",        // iz obstoječega TrainingGoal
  "rationale": "..."                   // prikazano uporabniku v review gate
}
```

### 3.2 Česa AI ne sme vrniti

Eksplicitno prepovedano, in validator to zavrne:

- **imen ali id-jev ali slugov vaj** — izbira vaj je izključno stvar planerja;
- **serij, ponovitev, teže, RPE, tempa** — to je `SlotPrescriptionCodec` (faza 18);
- **časovnih capov za metcone** — to je `CrossfitScalingPolicy` (faza 21);
- **karkoli, kar zaobide prerequisite, injury, equipment ali difficulty filter.**

Razlog je preprost: vsako od teh polj ima za sabo determinističen sistem z varnostnimi
vrati, zgrajen skozi faze 16–21. Če bi jih smel nastaviti model, bi bila ta vrata odvisna
od tega, kaj je model tisti dan vrnil.

### 3.3 Validacija in zavrnitev

Brief gre skozi strogo shemo, nato pa še skozi obstoječa pravila:

- vsaka enum vrednost mora obstajati v svojem Dart enumu (neznana vrednost = zavrnitev,
  ne tiho privzeta vrednost);
- `ProgramGuardrails`;
- pravilo največ 2 Max Effort vzorca na teden in prepoved Max Effort + 6-dnevni PPL, ki se
  danes vržeta inline v `block_builder_view.dart:3232` in `:3237` — ti dve preverjanji je
  treba izvleči v domenski validator, da veljata za obe poti;
- `ExerciseProgrammingEligibility` posredno, ker planner tako ali tako filtrira.

Ob zavrnitvi: fallback na obstoječo deterministično priporočilo (`ExperienceRecommendation`),
z vidnim pojasnilom. Nikoli tiha degradacija.

### 3.4 Pot skozi aplikacijo

Ista kot obstoječa, ker je že pravilna:

```
brief → validator → SmartProgramConfiguration → SmartProgramPlanner.populate()
      → ProgramReviewView (archived: true, activate: false) → uporabnik potrdi → _confirm()
```

`program_review_view.dart:287` `_confirm()` je edina točka, kjer program postane resničen.
AI ne dobi bližnjice mimo nje (AIP-04).

Degradacija (AIP-05): brez omrežja, brez Supabase konfiguracije ali čez kvoto se ponudi
obstoječa Smart/Guided pot, ne prazna napaka.

### 3.5 Dolžina datoteke

`block_builder_view.dart` ima **3398 vrstic**. Pravilo je 600. Dodajanje četrtega načina
vanj to dodatno poslabša, zato je razbitje na `part`/`part of` v podmapi z imenom datoteke
**prvi plan te faze**, ne čiščenje na koncu.

---

## 4. Faza 28 — Adaptivni TDEE

### 4.1 Zakaj se sploh spremeni

Danes: `MacroTargets.fromProfile` (`macro_targets.dart:21`) = Mifflin-St Jeor × **ročno
izbran** activity multiplier (1.2 / 1.375 / 1.55 / 1.725), plus goal adjustment. Uporabnik
izbere activity level v onboardingu in ga skoraj nikoli ne popravi. Napaka tega pristopa je
tipično ±15 %, in ne ve za to, da je nekdo ta mesec začel hoditi 12000 korakov na dan.

### 4.2 Primarna metoda — izmerjena poraba

Energijska bilanca čez drseče okno:

```
TDEE ≈ povprečen dnevni vnos − (sprememba teže v kg × 7700 kcal/kg) / število dni
```

To ni ocena, to je **izmerjena poraba**, in uporablja podatke, ki jih aplikacija že ima:
dnevnik hrane in zapise teže. To je metoda, ki jo uporablja MacroFactor.

Pogoji, da se uporabi:

- dovolj dni z logirano hrano v oknu (prag se zapiše v fazni kontekst, ne tu);
- dovolj zapisov teže za smiseln trend;
- trend teže se računa z glajenjem, ne iz dveh točk — dnevna nihanja vode so večja od
  tedenske spremembe maščobe.

### 4.3 Fallback — klasifikacija aktivnosti

Kadar adherenca ne zadošča, se activity level **izpelje** namesto izbere, iz drift tabele
`HealthSamples` (`steps`, `sleep_hours`, `active_kcal`, `resting_hr`, ena vrstica na metriko
na dan) plus logiranih treningov. Rezultat je isti multiplier kot danes, samo da ga ne
ugiba uporabnik.

Obstoječi `ActivityBasedAdjuster` (`health/domain/activity_adjuster.dart`) tega **ne** dela
— vrne volume factor za trening, ne TDEE multiplierja. Je pa vzorec za obliko.

### 4.4 Kadenca

TDEE-03: aplikacija sama izbere okno in kadenco ponovne kalibracije glede na gostoto
podatkov. Uporabnik ne izbira "meri en mesec". Ponovna kalibracija se sproži ob:

- pretečenem intervalu od zadnje ocene;
- materialnem premiku trenda teže;
- opazni spremembi vzorca aktivnosti.

### 4.5 Kam se priključi

Točno ena točka. `baselineTargetsProvider`
(`nutrition/application/nutrition_providers.dart:69`) je danes edini vir baseline vrednosti
in gre naravnost v `DietPhaseCalculator.apply(baselineKcal:)`. Adaptivni TDEE postane vir
te številke; fazna matematika, pace preseti in macro razdelitev se ne dotaknejo.

Ročno vnesena "Maintenance calories" v `nutrition_targets_view.dart` ostane **nadrejena**
(TDEE-04). Aplikacija ne prepiše številke, ki jo je uporabnik vnesel sam.

`nutrition_targets_view.dart` ima čez 1450 vrstic — isti problem kot builder.

### 4.6 Varovalke

- Vsaka ocena nosi metodo, zaupanje, okno in vhodne podatke, in je vidna uporabniku.
- PHYS-04 (mladoletniki, prepoved agresivnih deficitov) velja tudi tu. Adaptivni TDEE ne
  sme postati pot mimo varnostnih vrat.
- Materialen premik gre v tedensko poročilo (TDEE-05), ne v tiho spremembo potrjenih ciljev.

---

## 5. Faza 29 — Tedensko poročilo

### 5.1 Oblika

Ena vrstica na ISO teden, **persistirana** (RPT-01). Opt-in.

Danes ne obstaja noben tedenski artefakt — vse se računa živo ob odprtju pogleda. To za
poročilo ne zadošča: poročilo mora biti stabilno, pregledno nazaj po zgodovini, in ne sme
ob vsakem odprtju vrniti drugačnega besedila (RPT-04). Zraven je tudi stroškovno vprašanje
— AI narativ se generira enkrat, ne ob vsakem ogledu.

### 5.2 Izmerjeni del — vse iz obstoječih virov

| Sekcija | Vir |
|---|---|
| Prehranska adherenca, pogoste hrane | dnevnik + `effectiveTargetsProvider`, `MacroTrendView` logika |
| Volumen in moč | `AnalyticsRepository.weeklyTonnage`, `topOneRms` |
| Okrevanje | `CnsTrends`, `MuscleRecoveryV3` (vključno z `warnings()`, ki se danes računa in nikjer ne prikaže) |
| Spanje / aktivnost proti učinku | `sleepVsRpeProvider`, `hrVsTonnageProvider` |
| Physique napredek | faza 23 |
| Premik TDEE | faza 28 |

### 5.3 AI del

Herculex AI doda narativ in predloge za izboljšave, grounded na korpusu, **vizualno ločeno**
od izmerjenih številk (RPT-02). Model ne sme popravljati številk — dobi jih kot dejstva in
jih interpretira.

RPT-05: povezave med okrevanjem, spanjem, aktivnostjo in učinkom se navedejo kot
**korelacija**, ne vzročnost. Obstoječi correlation providerji vračajo korelacije; poročilo
jih ne sme prevesti v "ker si premalo spal, si bil šibkejši".

### 5.4 Nedeljska notifikacija

`flutter_local_notifications` ob sprožitvi **ne more pognati Dart kode**, in projekt nima
`workmanager` ne `android_alarm_manager`. Zato:

- notifikacija samo deep-linka v poročilo;
- poročilo se generira ob odprtju, ne v callbacku (RPT-03).

Nobeden od obstoječih schedulerjev ne ponavlja tedensko — vsi uporabljajo
`DateTimeComponents.time`. Tu je potreben `DateTimeComponents.dayOfWeekAndTime`. Vzorec za
prepisati je `daily_log_notification_scheduler.dart` (id 4001); nov blok id-jev, npr. 5001,
dve polji v `NotificationSettings`, ena veja v `NotificationSyncService`.

---

## 6. Faza 23 — razširitev (PHYS-05–08)

Faza 23 že pokriva persistenco ciljev, zasebno hrambo fotografij in večfazne prehranske
načrte. Amandma doda pogled na napredek.

### 6.1 Izhodišče

Dream Physique danes shranjuje povzetek v **SharedPreferences**, omejen na 20 vnosov
(`dream_physique_summary_repository.dart`), fotografije pa so v tabeli `ProgressPhotos`, ki
je local-only in nima FK na cilj. PHYS-01/02 to preneseta v drift. **PHYS-05–08 se ne sme
planirati pred tem** — sicer se gradi na začasni hrambi.

### 6.2 Progress screen (PHYS-05, PHYS-08)

- Katera faza je aktivna (`cut` / `recomp` / `maingain` / `bulk` / `maintain`), kje v
  večfaznem roadmapu smo, koliko časa v fazi, in kakšna so izhodna merila.
- Grafi (`fl_chart`, že v projektu): trend teže, trend moči (e1RM na kanonskih dvigih),
  training level, in ciljni pas faze čez horizont cilja.

**Opozorilo:** "training level" **ni** XP rank. Blueprint je glede tega izrecen — `Novice I–V`
in naprej so *Herculex ranki* iz faze 24, ne trening izkušenost, in nikoli ne odklenejo vaj.
Graf mora risati `ExperienceLevel` in strength standarde, ne ranka.

### 6.3 Tedenska slika (PHYS-06, PHYS-07)

- Največ ena check-in slika na 7 dni na cilj, omejeno **v repozitoriju**, ne v widgetu —
  sicer se omejitev obide z drugo potjo do iste metode.
- Naslednji dovoljeni datum viden v UI, ne skrita napaka ob poskusu.
- AI vrne **smer** (na pravi poti / ni na pravi poti / ni mogoče oceniti) kot razpon z
  zaupanjem, ne odstotek. Vizualna primerjava dveh fotografij v razmaku enega tedna ne nosi
  informacije za "napredoval si 3,2 %", in taka številka je izmišljena natančnost.
- Ocena **nikoli sama ne spremeni kalorij**. Ujema se z obstoječim vzorcem:
  `DreamPhysiqueNutritionRecommender` že danes samo deep-linka v urejevalnik ciljev,
  prednastavljen na fazo, in ne piše ciljev sam.

---

## 7. Tveganja, ki jih je treba prenesti v fazne kontekste

1. **Migraciji 0015 in 0016 sta napisani, a neuporabljeni** (`CLAUDE.md`). Tri nove faze
   dodajajo tabele. Uporabiti ju je treba po vrsti, preden se doda karkoli novega — sicer
   se razkorak med drift in Postgres poveča in `SyncService` karantenira vrstice (PGRST204).

2. **Vsak schema bump je pet opravil.** Lokalni drift je na **v44**. Faza 23 doda physique
   tabele iz blueprinta, 28 doda `tdee_estimates`, 29 doda `weekly_reports` — okvirno
   v45–v47. Vsaka: `schemaVersion` + varovan `onUpgrade`, schema dump, generirane migracije,
   popravljeni `migration_test.dart` in `schema_v2*.dart`, in ujemajoča
   `supabase/migrations/NNNN_*.sql`. `addColumn` korake varovati s `pragma_table_info`.

3. **Predolge datoteke pred začetkom.** `block_builder_view.dart` 3398 vrstic (faza 27),
   `nutrition_targets_view.dart` čez 1450 (faza 28). Razbitje je prvi plan, ne zadnji.

4. **Kvota fails open.** Ena skupna kvota 50/dan, ob napaki RPC-ja spusti klic skozi.
   KB-05 mora pristati pred 27 in 29.

5. **Nič AI odgovorov se ne cachira.** Tedenska poročila in program briefi morajo biti
   persistirani.

6. **Notifikacije ne morejo računati.** Od tod deep-link pristop v RPT-03.

7. **PHYS-04 velja povsod.** Mladoletniki in nizko zaupanje: niti adaptivni TDEE niti AI
   brief ne smeta biti pot mimo te varovalke.

8. **Hercul zaprt besednjak.** Test zavrne pravilo s signalom izven `HerculSignals.all`.
   AI kanal je ločena pot z lastno oznako vira, ne novi signali v rule engine.

---

## 8. Vrstni red izvedbe

```
26 → 28 → 27 → 22 → 23 → 29 → 24 → 25
```

- **26** je edina nova faza brez predhodnika, in 27, 29 ter PHYS-07 vsi uporabljajo njeno
  pogodbo o korpusu.
- **28** nima AI odvisnosti in hrani 23 in 29.
- **25** ostane zadnja, da pokrije vse tabele, ki jih dodajo 23, 28 in 29.

Učbenika uporabnik še ni dostavil. To ničesar ne blokira: faza 26 lahko postavi pogodbo,
verzioniranje in injekcijsko pot proti nadomestnemu korpusu, pravi vsebina pa pride kasneje
kot deploy, brez spremembe kode.
