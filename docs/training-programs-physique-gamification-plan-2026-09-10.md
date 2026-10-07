# Herculex: načrt prenove programov, Dream Physique in gamifikacije

**Datum:** 2026-09-10  
**Status:** predlog za izvedbo  
**Obseg:** generator trening programov, urejanje programov in workoutov, koledar, Dream Physique, prehranska usmeritev ter 15-stopenjski XP sistem

## 1. Povzetek odločitve

Zahteve niso en sam popravek. Gre za tri povezane produkte:

1. varen in razložljiv generator programov;
2. pravi urejevalnik programa in zanesljiv workout/koledarski tok;
3. trajen physique cilj z načrtom prehranskih faz in gamifikacijo.

Priporočen vrstni red je:

1. takoj odpraviti dokazljive regresije (zahtevnost, Dynamic Effort, prosojen popup, tipkovnica, napačen calendar Start/Resume);
2. katalogu dodati zahtevnost, običajnost, disciplino in prerequisite podatke;
3. uvesti enotni vhod in hard guardraile generatorja;
4. poenotiti recept, čas treninga, warmupe in napredne set metode;
5. zgraditi week/wave editor in razložljivo periodizacijo;
6. šele nato dodati CrossFit/GPP in strength specialization;
7. ločeno zgraditi trajen Dream Physique in prehranski načrt;
8. na preverjenih podatkih zgraditi XP ledger in 15 Herculex rankov.

CrossFit, specializacija in gamifikacija ne smejo biti dodani kot dodatni `if` stavki v obstoječi builder. Vsak potrebuje svoj domenski model in testirano politiko.

## 2. Kako aplikacija trenutno sestavi program

Sedanji tok je:

1. `BlockBuilderView` zbere cilj, izkušenost, split, dneve, periodizacijo, rotacijo, opremo, preference in physique prioritete.
2. `ProgramsRepository.createProgramFromSplit()` ustvari program, tedne in dneve kot osnutek.
3. `SmartProgramPlanner.populate()` določi stabilne slote, poišče kandidate, jih razvrsti ter materializira `ProgramExerciseSlots`, `RotationAssignments` in `ProgramDayExercises`.
4. `ProgramReviewView` pokaže predvsem prvi teden in ločen povzetek rotacij.
5. Ob zagonu treninga `PlannedSessionResolver` recept ponovno razreši in ga zamrzne v `WorkoutExercises` ter `SetEntries`.

Dobri obstoječi temelji, ki jih je treba ohraniti:

- stabilen slot čez celoten blok;
- ločene naloge rotacije po tednih;
- `prescriptionJson` in planirana polja seta;
- zamrznjen snapshot že začetega workouta;
- set tipi AMRAP, EMOM, For Time, drop, myo in rest-pause;
- circuit sistem;
- effective-load in E1RM analitika;
- potrjene Dream Physique mišične prioritete.

## 3. Dokazljivi vzroki opaženih napak

### 3.1 Začetnik dobi napredne calisthenics vaje

`ExperienceLevel` trenutno ne filtrira kataloga. V `exercises.json`, `movements.json` in `ExerciseCatalog` ni zanesljivega polja za:

- minimalno zahtevnost;
- tehnične prerequisites;
- dovoljeno stopnjo uporabnika;
- scaling oziroma lažjo predhodno vajo.

Začetniški loading preference celo daje prednost bodyweight vajam. Ker ni trdega difficulty filtra, lahko napredna planche ali muscle-up varianta prejme bonus in prehiti običajno osnovno vajo.

### 3.2 Spoto Press, SSB, Swiss bar in podobne variante se pojavljajo prepogosto

Katalog ne loči med:

- osnovno vajo;
- pogosto varianto;
- specialistično varianto;
- coach/manual-only varianto.

Zato ima Spoto Press v običajnem programu praktično isti status kot Bench Press. Profil »Basic weights« še ne obstaja, `allEquipment` pa specialty opremo dovoljuje brez dodatnega vprašanja.

### 3.3 Zakaj se pojavi 8 serij

Obstajata dva legitimna recepta z osmimi vrsticami:

- **Dynamic Effort:** 8 delovnih serij × 3 ponovitve pri približno 55 %, 60 sekund počitka;
- **Max Effort:** 4 warmup + 1 top set + 3 back-off sete.

Konkretna napaka je v izbiri metode. Tretji Full Body/ABC dan in Full Body dan v nekaterih splitih dobita `dynamicTechnique` ne glede na izbrano periodizacijo ali izkušenost. Vsak heavy slot na tem dnevu nato postane `dynamicEffort`. Zato lahko tudi začetnik z linearnim Full Body programom nepričakovano dobi 8×3.

Dodatna težava je dvojni vir resnice: review lahko pokaže `targetSets = 3`, resolver ob začetku treninga pa iz metode naredi 8×3.

### 3.4 Menjava vaje spremeni vse waves

`ProgramsRepository.replaceProgramExerciseSlot()` namenoma:

- spremeni vse `ProgramDayExercises` istega stabilnega slota;
- zaklene cel slot;
- pripne izbrano vajo v pool;
- spremeni vse `RotationAssignments` tega slota.

UI ne vpraša po obsegu spremembe. To ni naključna UI napaka, ampak trenutno repository vedenje.

### 3.5 Week in exercise wave sta pomešana

`PlannedSessionResolver` trenutno uporablja `weekIndex` kot `waveIndex`. Posledično workout in block detail kažeta »Wave 2/8«, čeprav je dejanski exercise wave morda »Wave 1, Weeks 1–2«.

### 3.6 Popup za menjavo vaje je brez ozadja

Modal je transparenten, notranji container pa uporablja `theme.scaffoldBackgroundColor`. Herculex tema ima `scaffoldBackgroundColor: Colors.transparent`, zato je transparentna tudi vsebina popupa. Pravilen obstoječi vzorec je `HxSheet` s `surfaceContainer`.

### 3.7 Active workout tipkovnica ne skrije vseh kontrol

`MainScaffold` in `ActiveWorkoutView` ločeno računata `MediaQuery.viewInsets`. Navbar in floating gumba Finish/Add zato nimajo enega vira resnice. Premik gumba izven zaslona tudi sam po sebi ne zagotovi odstranitve iz hit-testinga in semantike.

### 3.8 Koledarski popup lahko odpre oziroma zažene napačen workout

Koledar med potjo zavrže konkretni `ScheduledWorkoutRow` in obdrži samo datum. `DayDetailSheet._start()` nato pokliče `todaysWorkout()`, ki uporablja `limit(1)`. Drugi workout istega dne zato ne more zanesljivo zagnati pravega sessiona. Resume lahko ponovno materializira workout namesto samo odpreti obstoječega.

### 3.9 Dream Physique ni trajen cilj

Celoten rezultat analize ostane v lokalnem stanju zaslona. Trajno se shrani samo potrjen seznam mišičnih prioritet v `PhysiqueProgrammingProfiles`. Uporabnik zato v Settings/Profile nima evidence cilja, zgodovine analiz ali zbirke.

### 3.10 Gamifikacija še nima vira resnice

Tabela `Achievements` vsebuje samo `id` in `unlockedAt` ter nima prave uporabe. Ne obstaja idempotenten XP ledger, verzija pravil, dokazila za nagrado ali varen sync tok.

## 4. Ciljna arhitektura

### 4.1 Enotni vhod generatorja

`ProgramGenerationRequest` naj postane edini javni vhod v generator. Vsebovati mora najmanj:

- training goal;
- dejansko training experience;
- training style profile;
- dovoljene discipline;
- specialty-equipment opt-in;
- razpoložljivo opremo;
- dneve in ciljno trajanje workouta;
- periodizacijo in rotacijo;
- warmup policy;
- dovoljene intensity techniques;
- injury/pain omejitve;
- physique oziroma strength specialization goal.

Predlagani `TrainingStyleProfile`:

- `calisthenics`;
- `weights`;
- `basicWeights`;
- `crossFit`;
- `mixedCalisthenicsWeights`;
- `fullBodyTwoPlusGpp`.

### 4.2 Hard filtri pred scoringom

Vaja mora biti odstranjena iz kandidatov, preden dobi score, če ne prestane:

1. uporabnikovega »Never«;
2. pain/injury omejitve;
3. opreme;
4. training-style profila;
5. experience ceilinga;
6. prerequisites;
7. specialty opt-ina;
8. pravil konkretne metode.

Scoring odloča samo med že dovoljenimi vajami. Hard filtra se ne sme relaksirati zato, da se zapolni slot; v tem primeru mora planner vrniti razložljiv »no safe candidate« rezultat.

### 4.3 En recept od previewja do workouta

`SlotPrescription` mora dobiti verzioniran JSON codec. Razrešeni recept se shrani v program in je isti objekt, ki ga:

- vidi review;
- vidi week editor;
- uporabi `PlannedSessionResolver`;
- zamrzne začet workout.

S tem izgine razlika med »3 sets« v programu in »8×3« v aktivnem workoutu.

### 4.4 Ločitev week, wave in workout occurrence

- **Week** je koledarski teden programa.
- **Exercise wave** je zaporedni segment tednov z isto rotacijsko izbiro.
- **Occurrence** je konkreten koledarski workout, ki lahko ima enkratni override.

Ti pojmi morajo imeti ločene tipe in oznake v repository snapshotih ter UI-ju.

## 5. Izvedbeni načrt

## Faza 0 — nujni popravki obstoječih regresij

**Cilj:** odpraviti napake, ki trenutno povzročajo napačen program ali napačno interakcijo, še preden se doda nova funkcionalnost.

### Spremembe

- Omeji `dynamicTechnique → dynamicEffort` na ustrezen Concurrent/Westside profil ali izrecno izbiro; linear novice Full Body ga ne sme dobiti.
- V reviewju in workoutu pokaži razlago recepta:
  - `8 speed sets × 3 @ 55 %, 60 s — Dynamic Effort`;
  - ali `4 warm-up + 1 top + 3 back-off — Max Effort`.
- Replacement popup prestavi na `HxSheet` oziroma neprosojni `surfaceContainer`.
- Uvedi skupni keyboard-visible signal za shell in active workout; navbar, Finish in Add Exercise skupaj skrij z `AnimatedSlide`, `AnimatedOpacity`, `IgnorePointer` in izključitvijo semantike.
- Koledarski tok naj nosi konkretni `scheduleId`; dodaj `startScheduledWorkoutById(scheduleId)` in loči Start od Resume.
- Center datum in Start/Resume; dodaj `View workout`, ki samo razreši preview in ne ustvari sessiona.

### Glavne datoteke

- `lib/features/programs/data/smart_program_planner.dart`
- `lib/features/programs/presentation/views/program_review_view.dart`
- `lib/features/workouts/presentation/views/active_workout_view.dart`
- `lib/features/shell/main_scaffold.dart`
- `lib/features/programs/presentation/sheets/day_detail_sheet.dart`
- `lib/features/workouts/data/scheduled_workout_service.dart`
- `lib/features/programs/presentation/views/training_blocks_view.dart`
- `lib/features/programs/presentation/widgets/week_board.dart`
- `lib/design_system/components/hx_sheet.dart`

### Acceptance criteria

- Novice + linear + Full Body nikoli ne materializira Dynamic Effort 8×3 brez izrecne uporabnikove izbire.
- Preview in aktivni workout prikažeta isto število in tipe setov.
- Replacement sheet je neprosojen v light in dark temi.
- Ob fokusu na weight ali reps niso vidni ali klikljivi navbar, Finish in Add Exercise; po zaprtju tipkovnice se vsi vrnejo.
- Drugi od dveh workoutov istega dne odpre in zažene prav svoj `scheduleId`.
- Resume ne ustvari novega sessiona in ne prepiše povezave obstoječega.
- `View workout` ne spremeni števila workout sessionov.

## Faza 1 — katalog zahtevnosti, običajnosti in disciplin

**Cilj:** generator dobi podatke, s katerimi lahko zanesljivo spoštuje Beginner, Basic in izbrano vrsto treninga.

### Novi podatki

Na `ExerciseCatalog` oziroma izvornem assetu dodaj:

- `difficultyLevel`: novice, intermediate, advanced;
- `commonnessTier`: basic, common, specialty, manualOnly;
- `disciplines`: weights, calisthenics, crossFit, olympic, gpp;
- `prerequisiteSlugs`;
- `scalingGroup` in `scalingOrder`;
- `competitionAnchor`;
- `specializationTags`, npr. squat-bottom, squat-mid, squat-lockout;
- `technicalComplexity` in po potrebi `impactLevel`.

`basicWeights` mora biti trd profil: običajni barbell, dumbbell, cable in machine gibi; brez SSB, Swiss/football bar, Spoto, board/pin press in podobnih specialty variant, razen če jih uporabnik naknadno izrecno dovoli.

### Glavne datoteke

- `assets/data/exercises.json`
- `assets/data/movements.json`
- `tool/build_exercises.py`
- `tool/derive_movements.py`
- `tool/catalog_cleanup.py`
- `lib/data/local/tables.dart`
- `lib/data/local/exercise_importer.dart`
- `lib/data/local/database.dart`
- Drift schema dump/generator in Supabase migracija

### Acceptance criteria

- Vsaka generabilna vaja ima veljaven difficulty, commonness in vsaj eno discipline oznako.
- Noben manual-only exercise se ne pojavi brez ročne izbire.
- Beginner calisthenics ne vsebuje full planche, Hefesta ali muscle-upa brez izpolnjenih prerequisites.
- Basic weights ne vsebuje specialty bara ali specialistične press/squat variante.
- Import, migracija in reimport ohranijo nove oznake.

## Faza 2 — deterministični planner in guardraili

**Cilj:** združiti vse builder inpute v eno pogodbo ter preprečiti, da scorer obide uporabnikovo izbiro.

### Spremembe

- Razširi `ProgramGenerationRequest` in odstrani vzporedne, delno podvojene konfiguracije.
- Uvedi `ExerciseEligibilityPolicy` za hard filtre.
- `ExerciseScorer` naj prejme dejanske:
  - recent picks;
  - weeks since last performed;
  - logged sessions;
  - stagnation exposures;
  - recovery map;
  - CNS budget.
- Upoštevaj `ExercisePreferences.allowedRolesJson`.
- Core/anchor lift naj bo prava garancija, ne samo affinity bonus.
- Block periodization naj ponovno razreši pool ob prehodu accumulation → intensification → realization; realization zaklene anchor lift.
- Planner naj vrne `SelectionExplanation` z dovoljeno/izločeno logiko in razlogom končne izbire.

### Glavne datoteke

- `lib/features/programs/domain/programming_models.dart`
- `lib/features/programs/domain/program_guardrails.dart`
- `lib/features/programs/domain/exercise_scorer.dart`
- `lib/features/programs/domain/rotation_policy.dart`
- `lib/features/programs/data/smart_program_planner.dart`
- `lib/features/programs/data/exercise_preferences_repository.dart`
- `lib/features/programs/presentation/views/block_builder_view.dart`

### Acceptance criteria

- Matrika experience × goal × profile × periodization je deterministična pri istem inputu.
- Hard »Never«, pain, equipment, difficulty in profile filtri niso nikoli relaksirani.
- Beginner ne dobi advanced vaje; Basic ne dobi specialty vaje.
- Linear novice ne dobi Dynamic Effort.
- Core lift ostane v vseh zahtevanih tednih.
- Faze Block periodizacije uporabljajo svojo fazno politiko, ne začetnega round-robin poola.
- Vsaka izbrana vaja ima uporabniku berljiv razlog.

## Faza 3 — čas treninga, warmupi in napredne set metode

**Cilj:** sestaviti program, ki dejansko ustreza razpoložljivemu času in uporablja enoten set prescription.

### Builder inputi

- ciljno trajanje: 30/45/60/75/90 minut ali lastna vrednost;
- warmup: Auto / None / Custom;
- dovoljene tehnike: straight, last-set-to-failure, 2-to-failure, myo, drop, rest-pause;
- ali naj app časovno varčne tehnike uporablja samodejno;
- maksimalno število tehnik na workout in na mišično skupino.

### Domenska logika

- `SlotPrescriptionCodec` za verzioniran JSON.
- `WorkoutDurationEstimator`, ki upošteva set, reps, počitek, warmup, unilateral delo, prehode in circuit time cap.
- `WarmupResolver`, ki upošteva:
  - ali je to prva težka vaja istega vzorca;
  - planirano intenzivnost ali težo;
  - prejšnje podobne vaje;
  - izkušenost;
  - training method.
- `IntensityTechniquePolicy` z omejitvami, da planner ne daje failure/drop/myo na neprimerne tehnične ali visoko utrujajoče glavne dvige.
- Planner naj najprej ohrani glavno delo, nato zmanjša accessory volumen, šele ob uporabnikovem opt-inu pa uporabi časovno varčno tehniko.

### Glavne datoteke

- `lib/features/programs/domain/slot_prescription.dart`
- `lib/features/programs/domain/prescription_resolver.dart`
- novi `workout_duration_estimator.dart`
- novi `warmup_resolver.dart`
- novi `intensity_technique_policy.dart`
- `lib/features/programs/data/programs_repository.dart`
- `lib/features/workouts/data/planned_session_resolver.dart`
- `lib/features/programs/presentation/views/block_builder_view.dart`

### Acceptance criteria

- Preview, week editor in materializiran workout vsebujejo byte-equivalenten razrešeni prescription JSON.
- `2 sets to failure` ustvari natanko dva delovna seta z jasno failure oznako.
- Auto warmup doda več ogrevalnih setov pred težkim prvim compoundom ter manj ali nič pred že ogretim podobnim gibanjem.
- 45-minutni program ostane znotraj dogovorjene tolerance, npr. ±10 %, ali pred potrditvijo jasno opozori, da cilj ni dosegljiv.
- Drop/myo/rest-pause se ne uporabijo brez opt-ina.

## Faza 4 — razložljiva periodizacija, rotation waves in program editor

**Cilj:** uporabnik razume metodo in lahko varno ureja vsak teden oziroma wave.

### Builder UX

- Linear, Concurrent, Westside/Max Effort in Block dobijo celo kartico.
- Priporočena kartica ima rob in majhno oznako `Recommended`.
- Priporočilo je čista funkcija `goal + experience + trainingStyle + daysPerWeek`.
- Na koncu vsake kartice je `?`, ki odpre namensko razlagalno stran:
  - kako se spreminjajo volumen, intenzivnost in vaje;
  - kako pogosto se rotira;
  - komu je metoda namenjena;
  - primer osmih tednov;
  - zakaj jo app priporoča ali odsvetuje.
- Back vrne uporabnika na isti builder korak z ohranjenim draftom.
- Exercise rotation je jasno izpostavljena že ob periodizaciji in pri končnem pregledu.

### Program editor

- Namesto dolge liste uporabi Week dropdown: Week 1, Week 2 …
- Dodaj dejanski wave selector oziroma strip: `Exercise wave 1 · Weeks 1–2`.
- Vsak dan in exercise je interaktiven; omogočeno je urejanje vaje, vrstnega reda, setov in prescriptiona.
- Po menjavi vaje pokaži scope:
  - This wave;
  - This and future waves;
  - Entire block.
- Privzeta priporočena možnost je `This wave`.
- Že začet workout ostane nespremenjen.

### Repository pogodba

- Dodaj `ProgramWeekEditorSnapshot` z week/day/exercise/slot/assignment identitetami.
- Dodaj `ProgramExerciseReplacementScope`.
- `thisWave` posodobi samo zaporedni segment assignmentov istega wave-a.
- `thisAndFutureWaves` ohrani pretekle assignmentse.
- `entireBlock` ohrani trenutno globalno pin/lock vedenje.
- Substitucije iz aktivnega workouta centraliziraj v isti programski servis; »today only« ostane occurrence-level override.

### Glavne datoteke

- `lib/features/programs/presentation/views/block_builder_view.dart`
- novi `program_method_guide_view.dart`
- `lib/features/programs/presentation/views/program_review_view.dart`
- `lib/features/programs/presentation/views/block_detail_view.dart`
- novi ali razširjeni `program_editor_view.dart`
- `lib/features/programs/data/programs_repository.dart`
- `lib/features/programs/application/programs_providers.dart`
- `lib/app/router/routes.dart`
- `lib/app/router/router.dart`

### Acceptance criteria

- Osem tednov programa kaže samo en izbran week naenkrat.
- `A,A,B,B` z menjavo drugega tedna in scope `This wave` postane `C,C,B,B`.
- Scope `Entire block` postane `C,C,C,C`.
- UI ločeno kaže `Week 2 of 8` in `Exercise wave 1 of 4 · Weeks 1–2`.
- Back z guide strani ohrani vse builder izbire.
- Program editor nikoli ne spremeni že materializiranega workouta.

## Faza 5 — dokončanje active workout in koledarskega toka

**Cilj:** zaključiti UI popravke iz Faze 0 z namenskimi modeli in regresijskimi testi.

### Spremembe

- En `KeyboardObstructionScope` oziroma enakovreden shell signal.
- `DayDetailSheet.show(initialScheduleId: ...)`.
- Week in month calendar posredujeta konkreten schedule, ne le datum.
- `PlannedWorkoutPreviewView` uporabi resolver brez materializacije.
- Statusno routanje:
  - planned/moved → preview + Start;
  - in progress → Resume obstoječi workout;
  - done → workout history detail.
- `HxSheet` dobi opt-in `centerHeader`, brez spremembe vseh obstoječih sheetov.

### Acceptance criteria

- Keyboard test preveri vidnost, hit testing in semantiko vseh treh spodnjih kontrol.
- Calendar popup odpre točno izbrani workout tudi pri več workoutih na dan.
- Datum in primarni CTA sta centrirana.
- `View workout` pokaže exercise/set podatke brez DB write-a.
- Start in Resume imata ločeni, idempotentni poti.

## Faza 6 — CrossFit in Full Body 2× + GPP

**Cilj:** CrossFit ni le filter vaj, ampak strukturiran program za beginner, intermediate in advanced.

### Session blueprint

CrossFit workout vsebuje segmente:

1. warm-up;
2. skill ali strength;
3. metcon;
4. optional accessory/cooldown.

Segment lahko nosi circuit, AMRAP, EMOM ali For Time prescription ter time cap.

### Level politika

CrossFit level določa:

- dovoljene skill vaje in prerequisites;
- scaling varianto;
- kompleksnost olimpijskih dvigov;
- volumen in intenzivnost;
- time cap;
- kompleksnost kombinacij;
- zahtevano recovery rezervo.

Beginner brez prerequisite dokazila ne dobi muscle-upa, handstand walka ali naprednega snatch kompleksa. Namesto tega dobi scaling iz istega scaling groupa.

### Full Body 2× + GPP

Dodaj namenski preset:

- Full Body A;
- Full Body B;
- GPP/conditioning dan ali krajši GPP dodatek po dogovoru.

GPP dan ne sme avtomatsko postati tretji Dynamic Effort strength dan.

### Glavne datoteke

- `lib/features/programs/domain/split_template.dart`
- `lib/features/programs/domain/programming_models.dart`
- novi `crossfit_program_planner.dart`
- novi `crossfit_scaling_policy.dart`
- novi `gpp_program_planner.dart`
- `lib/features/workouts/data/circuits_repository.dart`
- `lib/features/workouts/data/planned_session_resolver.dart`
- potrebne program segment tabele/migracije
- builder, review in editor UI

### Acceptance criteria

- Vsak CrossFit workout ima veljaven segmentni blueprint.
- Beginner/intermediate/advanced generirajo različne, testirano dovoljene skill/scaling kombinacije.
- AMRAP/EMOM/For Time se pravilno materializirajo in ohranijo time cap.
- Full Body 2× + GPP vsebuje dva strength workouta in GPP vsebino brez neželenega 8×3.
- Time estimator vključuje celoten metcon oziroma time cap.

## Faza 7 — strength specialization program

**Cilj:** uporabnik vnese npr. cilj 140 kg squat, app pa pripravi razložljiv, realističen program s počepom kot središčem in vzdrževanjem ostalih mišičnih skupin.

### Vprašalnik

- ciljni lift;
- trenutni 1RM ali rep test z datumom;
- ciljna teža;
- ciljni datum oziroma razpoložljiv čas;
- izkušenost;
- sticking point: bottom, mid-range, lockout/top;
- bracing/tehnična težava;
- pain/injury omejitve;
- dnevi, trajanje in oprema;
- pripravljenost na testne tedne/deload.

### Novi tipi

- `StrengthSpecializationGoal`;
- `LiftAssessment`;
- `StickingPoint`;
- `SpecializationRecommendation`;
- `SpecializationPlanner`.

### Vedenje

- Izračun je projekcija z razponom, ne garancija.
- App priporoči model, trajanje, frekvenco glavnega lifta in vmesne teste.
- Sticking point izbira samo dovoljene variante z ustreznimi transfer tagi.
- Anchor lift ostane prisoten skozi blok.
- Vse ostale mišične skupine ostanejo nad določeno maintenance mejo.
- Nerealen rok sproži daljši predlagan horizont, ne agresivnejšega programa.
- Pain signal izloči neprimerne variante in poda opozorilo, ne diagnoze.

### Acceptance criteria

- Bottom/mid/top squat se preslikajo v različne, katalogsko avtorizirane variacije.
- 140 kg cilj z nerealnim rokom vrne razložljivo opozorilo in realnejši razpon.
- Squat anchor se ne izgubi zaradi novelty ali rotation scoringa.
- Nobena glavna mišična skupina ne pade pod maintenance volume.
- Manjkajoča oprema in pain omejitve so hard filtri.

## Faza 8 — trajen Dream Physique, zbirka in prehranski načrt

**Cilj:** Dream Physique postane trajen cilj z zgodovino, check-ini, slikami in uporabniško potrjenim nutrition roadmapom.

### Podatkovni model

Predlagane sinhronizirane tabele:

- `dream_physique_goals`
  - title, status, user notes;
  - target aesthetic;
  - nullable target weight/BF;
  - created, activated, target, completed datumi;
  - schema/model version;
  - največ en aktiven cilj na uporabnika.
- `dream_physique_assessments`
  - goal FK;
  - baseline/check-in/completion;
  - snapshot meritev in odgovorov;
  - strukturiran AI rezultat;
  - confidence in uncertainty range.
- `physique_photo_assets`
  - goal/assessment FK;
  - current/target/progress role;
  - pose, trajna relativna pot, hash, datum;
  - optional cloud key.
- `body_composition_plans`
  - aktivni cilj, začetni/ciljni snapshot;
  - recommendation, confidence, rationale;
  - uporabniška potrditev.
- `body_composition_plan_phases`
  - maintain, recomp, maingain, cut, bulk;
  - vrstni red, trajanje, tempo, kcal delta, macro snapshot in exit criteria.

`PhysiqueProgrammingProfiles` ostane vir potrjenih mišičnih prioritet, dobi pa povezavo na goal/assessment in repository plast.

### Fotografije in zasebnost

- Slika se po izboru kopira v app documents; začasna picker pot ni vir resnice.
- Pred shranjevanjem se odstrani EXIF; crop/blur obraza je priporočena možnost.
- DB vrstica se zapiše šele po uspešnem kopiranju.
- Delete izbriše vrstico in datoteko.
- Lokalna hramba je privzeta; cloud backup je ločen opt-in.
- Export in account wipe morata vključiti oziroma izbrisati goal, assessment, XP in lokalne datoteke.

### Prehransko priporočilo

Odločitev naj bo deterministična, AI pa poda vizualne signale, negotovost in razlago. Upoštevati mora:

- glavni cilj;
- training tenure in zadnjo konsistentnost;
- 4–6 tedenski trend teže;
- zgodovino diet;
- trenutni vnos, če je znan;
- ciljni datum;
- kakovost in realističnost target fotografije.

Predlagana politika:

- cut, ko je primarni gap izguba maščobe;
- bulk, ko je uporabnik dovolj lean, trenira konsistentno in je glavni gap mišična masa;
- recomp za začetnika/povratnika ali zmeren sočasen fat-loss/muscle-gain cilj;
- maingain za lean in konsistentnega uporabnika, ki želi zelo počasen napredek;
- maintain pri nizki kakovosti podatkov ali po večji nedavni spremembi teže.

Če sta potrebna večji fat loss in muscle gain, app predlaga več faz, npr. `cut → maintain → maingain`. Rok je razpon iz varnega relativnega tempa. Uporabnik mora plan potrditi, preden se materializira v `NutritionTargets`.

### UI

Dream Physique hub:

- Active Goal;
- Progress / Check-in;
- Collection;
- New Dream Physique;
- Privacy & photo storage.

Profil pokaže aktivni cilj, začetek, naslednji check-in in progress range. Zaključen cilj dobi completion oznako in možnost novega cilja.

### Acceptance criteria

- Ponoven zagon povrne aktivni cilj, celotno analizo, prioritete in zbirko.
- Obstaja največ en aktiven cilj, zgodovina pa se ne prepisuje.
- Check-in lahko doda sliko in primerja napredek z baselineom kot razpon, ne lažno natančen odstotek.
- Delete odstrani DB vrstico in fizično datoteko.
- Low-confidence rezultat ne aktivira prehranskega plana.
- Recomp je prava faza, ne le ime maingain preseta.
- Nerealen rok se označi kot nerealen; kalorije se ne zaostrijo na silo.
- Mladoletnik ne dobi samodejnega agresivnega deficita ali surplus priporočila.

## Faza 9 — 15 Herculex rankov in XP ledger

**Cilj:** prikazati dolgoročen napredek skozi trening, moč, konsistentnost in physique brez manipulativnih ali znanstveno neutemeljenih primerjav.

### Pomembna ločitev

`Novice I–V`, `Intermediate I–V` in `Advanced I–V` so **Herculex ranki**, ne training experience. Rank nikoli ne odklene tehnično napredne vaje in ne spreminja experience limita generatorja.

### Vir resnice

- `xp_events`
  - unique `sourceKey`;
  - domain in reason code;
  - points;
  - evidence JSON;
  - awardedAt;
  - rulesVersion;
  - optional reversedAt.
- `gamification_profiles`
  - total XP cache;
  - current rank;
  - rules version.
- po potrebi `level_unlocks` za zgodovino promocij.

Ledger mora biti idempotenten: isti workout, PR ali assessment na isti ali drugi napravi ne sme prinesti XP dvakrat.

### Predlagani XP viri

- dokončan workout in tedenska konsistentnost, s tedensko kapico;
- potrjen osebni napredek v canonical movementu;
- strength milestone na effective-load/E1RM dokazilu;
- physique check-in;
- potrjen physique trend milestone največ enkrat na 28 dni.

Ne dodeljuj:

- negativnega XP;
- XP za ekstremno hitro izgubo teže ali prenizek BF;
- XP za samo količino logiranja hrane;
- strength XP iz warmup, assisted, drop, myo ali neprimerljivih machine setov;
- physique XP iz ene same AI ocene ali neprimerljive fotografije.

### Relativna moč in uporabniški kontekst

- Uporabi `TrainingSnapshot`, `EffectiveLoad` in `OneRepMax`.
- Canonical movement identificiraj z `movementSlug`, ne z imenom.
- Bodyweight vzemi iz najbližje meritve glede na datum workouta.
- Če bodyweight manjka, pokaži absolutni osebni napredek.
- Višina ni neposreden kazenski množitelj strength razmerja; lahko služi waist-to-height in ergonomskemu kontekstu.
- Starost se lahko uporabi le z validiranim band/coefficient pristopom, nikoli za odvzem XP.
- Za prvo verzijo naj največ šteje lasten potrjen napredek; populacijski percentili pridejo šele z zanesljivim referenčnim virom.

### Privzeta konfiguracija

Pragovi in točke morajo biti v verzioniranem rule assetu, ne hard-coded v UI. Za beta verzijo se določijo s simulacijo zgodovinskih workoutov in nato zamrznejo kot `rulesVersion = 1`. UI vedno pokaže:

- zakaj je uporabnik dobil XP;
- katera meritev je bila uporabljena;
- koliko XP je dobil;
- koliko manjka do naslednjega ranka;
- kako lahko legitimno napreduje.

### Profil UI

- rank in 15-stopenjska progress vrstica;
- total XP in XP do naslednje stopnje;
- zadnji trije dogodki;
- ločeni signali Training, Strength, Consistency in Physique;
- tap odpre evidence ledger in razlago pravil.

### Acceptance criteria

- Ponovljen callback ali sync istega dogodka ne spremeni total XP.
- Noben uporabnik ne izgubi ranka zaradi slabega tedna ali spremembe pravil.
- Strength variante in set tipi se ne mešajo v napačen milestone.
- Uporabi se zgodovinski bodyweight, ne današnji profilni podatek.
- Physique improvement zahteva primerljiv trend in najmanj 28 dni; sicer uporabnik dobi le check-in XP.
- Rules-version backfill ne podvoji dogodkov.
- Vsak XP dogodek je razložljiv iz evidence.

## Faza 10 — sync, zasebnost, migracije in rollout

**Cilj:** vse nove podatke varno sinhronizirati, izvoziti, izbrisati in postopno vključiti.

### Obvezna dela pri vsaki synced tabeli

1. Drift tabela in `schemaVersion`.
2. Guarded `onUpgrade` veja.
3. Drift schema dump.
4. Generated migration fixtures.
5. `migration_test.dart` in nova schema replay preverjanja.
6. Supabase migracija.
7. `syncedTableNames`.
8. `syncTableSpecs` v parent-before-child vrstnem redu.
9. UUID/unique indeksi, outbox triggerji in owner RLS.
10. `local_data_wipe.dart`.
11. Dejanski JSON export namesto trenutnega placeholder sporočila.

Za občutljive photo/assessment/XP podatke dodaj RLS isolation, account deletion in export teste. `Achievements` in `hercul_message_log` je treba vključiti v popolni wipe ali jih nadomestiti z novo jasno pogodbo.

### Rollout

- Feature flags ločeno za generator guardraile, CrossFit, specialization, Dream history in XP.
- Novi generator naj najprej teče v shadow validation načinu in beleži samo agregirane razloge zavrnitve, brez občutljivih fotografij ali prostega besedila.
- Obstoječi programi ostanejo veljavni; novi metadata atributi ne smejo tiho prepisati že materializiranih workoutov.
- XP backfill je enkraten, verzioniran in idempotenten.

## 6. Testna strategija

### Enotski testi

- eligibility in scoring matrike;
- Dynamic/Max Effort prescription razlaga;
- time estimator in warmup resolver;
- rotation wave segmentacija in replacement scope;
- CrossFit scaling;
- specialization feasibility/sticking point;
- diet-phase recommendation;
- XP idempotency, caps in evidence.

### Repository in migration testi

- week/wave snapshot;
- `A,A,B,B → C,C,B,B` in globalna menjava;
- materializiran workout ostane immutable;
- Dream goal/history/photo CRUD;
- točno en aktiven physique goal;
- parent-before-child sync;
- account wipe in export;
- vse schema replay poti.

### Widget/golden testi

- priporočena periodization kartica in `?` navigacija;
- week dropdown in pravi wave label;
- replacement scope sheet;
- replacement popup v light/dark temi;
- keyboard hide/show z viewInsets, hit testingom in semantiko;
- koledarski popup, centered header/CTA in View workout;
- Dream hub, zbirka, check-in in rank card.

### Integracijski scenariji

1. Beginner + Basic + 45 min + linear → samo osnovne vaje, brez specialty, brez Dynamic Effort, čas znotraj tolerance.
2. Intermediate mixed calisthenics/weights → dovoljene intermediate vaje, advanced skill samo z dokazanim prerequisiteom.
3. CrossFit beginner → scaled skill + strength + metcon z veljavnim time capom.
4. Full Body 2× + GPP → dva full-body dneva in ločen GPP, brez tretjega speed-strength dneva.
5. 140 kg squat specialization → realen horizon, anchor squat, sticking-point variacije, maintenance ostalih mišic.
6. Dream Physique baseline → restart → check-in → večfazno prehransko priporočilo → uporabniška potrditev.
7. Workout PR in physique milestone na dveh napravah → en sam XP dogodek na vir.

## 7. Odvisnosti in izvedbeni waves

| Wave | Faze | Odvisnost | Rezultat |
|---|---|---|---|
| 1 | 0 | brez | varnostni in UX hotfixi |
| 2 | 1 | brez; lahko teče ob Fazi 0 | podatkovna taksonomija vaj |
| 3 | 2, 5 | Faza 2 zahteva 1; Faza 5 nadaljuje 0 | varen planner in stabilen workout/calendar UX |
| 4 | 3, 4 | Faza 2 | enotni recept, čas, warmupi, week/wave editor |
| 5 | 6, 7 | Faze 1–4 | CrossFit/GPP in specialization generatorja |
| 6 | 8 | lahko začne po podatkovnem načrtu; integracija s plannerjem po Fazi 2 | trajen physique in nutrition roadmap |
| 7 | 9 | Faza 8 ter zanesljiva analytics evidenca | 15 rankov in XP |
| 8 | 10 | spremlja vse schema faze, zaključni rollout po 9 | sync, privacy, export, wipe in rollout |

Praktično je smiselno Fazo 10 izvajati sproti pri vsaki schema spremembi, njen zaključni audit pa ostane zadnji gate.

## 8. Traceability vseh zahtev

| Uporabnikova zahteva | Pokrita v fazi |
|---|---|
| Beginner ne dobi advanced vaj | 1, 2 |
| Izbira calisthenics/weights/basic/CrossFit/mixed/Full Body 2× + GPP | 1, 2, 6 |
| CrossFit beginner/intermediate/advanced | 6 |
| Manj Spoto/specialty variant | 1, 2 |
| Izpostavljena exercise rotation | 4 |
| `?` pri Linear/Concurrent/Westside in detail stran z ohranjenim builder draftom | 4 |
| Recommended obrobljena kartica | 4 |
| Menjava samo za wave oziroma širši scope | 4 |
| Vaje pregledno prikazane po waves | 4 |
| Vnos časa workouta | 3 |
| Drop/myo in druge časovno varčne metode | 3 |
| Specialization za 140 kg squat, sticking point in priporočilo | 7 |
| Popup za menjavo vaje dobi pravo ozadje | 0 |
| Razlaga osmih serij in Dynamic Effort | 0, 3 |
| 2 sets to failure | 3 |
| Samodejni warmup seti | 3 |
| Urejanje workoutov po tednih | 4 |
| Week 1/2 dropdown namesto dolge liste | 4 |
| Tipkovnica skrije navbar, Finish in Add Exercise | 0, 5 |
| Calendar popup: View workout, centered Start/date | 0, 5 |
| Dream Physique se zapomni in ima evidence/zbirko/nov cilj | 8 |
| Dodaj progress sliko in oceni napredek | 8 |
| 5 novice + 5 intermediate + 5 advanced rankov | 9 |
| XP iz physique in številk glede na uporabniški kontekst | 9 |
| Rank v profilu in razlaga napredovanja | 9 |
| Recomp/maingain/cut/bulk priporočilo, cilji in roki | 8 |

## 9. Produktne odločitve, ki jih je treba potrditi pred implementacijo

Načrt uporablja naslednje priporočene privzete odločitve:

1. Training experience in Herculex rank sta popolnoma ločena.
2. `Basic weights` je hard filter; specialty je izrecni opt-in.
3. `This wave` je privzeti scope menjave.
4. CrossFit uporablja ločen segmentni planner, ne istega generičnega seznama vaj.
5. Fotografije so privzeto lokalne; cloud backup je opt-in.
6. Nutrition recommendation zahteva uporabniško potrditev in ne spreminja ciljev neposredno iz AI rezultata.
7. Ni negativnega XP in ni nagrad za ekstremne telesne spremembe.
8. Populacijski strength percentili niso del prve verzije; najprej se uporablja lasten potrjen napredek.

Pred začetkom Faze 6 je treba vsebinsko določiti CrossFit exercise/scaling matriko. Pred Fazo 9 je treba s simulacijo zgodovinskih podatkov umeriti XP pragove, tedenske kapice in čas do posameznega ranka.

## 10. Definition of done za celoten program

- Vse zahteve v traceability tabeli imajo avtomatiziran ali eksplicitni UAT dokaz.
- Generator nikoli ne obide difficulty, profile, equipment, pain ali user-avoid filtra.
- Preview, editor in aktivni workout uporabljajo isti prescription.
- Week, wave in occurrence so domensko in vizualno ločeni.
- CrossFit/GPP in specialization imata lastne testirane plannerje.
- Dream Physique, assessments, nutrition phases in photo collection preživijo restart in sync v skladu z uporabnikovim consentom.
- XP je idempotenten, razložljiv, verzioniran in ne vpliva na tehnično zahtevnost programa.
- Export in account deletion pokrivata vse nove občutljive podatke in datoteke.
- `flutter analyze`, celoten `flutter test` in strukturni checker so zeleni.

