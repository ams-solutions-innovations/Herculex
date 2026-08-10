
# Herculex — globoka analiza povezave telefon ↔ Wear OS ura in izvedbeni plan

**Datum analize:** 2026-08-08  
**Status:** analiza zaključena, plan pripravljen za izvedbo  
**Obseg:** workout sync, sets/reps/set types, Samsung rotating bezel, ongoing notifications, fasting sync in start/stop kontrola, reconnect/offline vedenje, testiranje

## 1. Kratek zaključek

Trenutne težave imajo več različnih vzrokov, ki se med seboj ojačujejo:

1. Aplikacija uporablja hkrati stare Flutter → native metode in nove native DataClient/MessageClient managerje. Zato je lahko isti dogodek dostavljen večkrat, po različnih poteh in v napačnem vrstnem redu.
2. Workout payload ni dovolj bogat in ni versioniran. Pri template syncu se izgubijo podatki iz TemplateSets; pri active-session syncu se izgubijo vsaj targetSets, isWarmup, setTypeMetaJson, bodyweightKg, chainsKg in completedAt.
3. Watch model planirane sete obravnava kot že obstoječe LoggedSet zapise. Ko uporabnik na uri izpolni planirani set, ga logSet() doda na konec namesto da bi posodobil naslednji nedokončani set.
4. Set-type semantika ni enotna: phone uporablja canonical ID-je in ločeno isWarmup, watch pa uporablja tudi vrednost warmup kot setType in privzeto vrednost Normal.
5. Ongoing workout service se zažene ob vsakem remote update-u, ob startu pa se v eni poti zažene dvakrat. Na phone strani se “Workout Started on Watch” notification ponovno objavi tudi ob durable update-u. To je glavni kandidat za konstantne notifikacije.
6. Fasting se na uro pošlje samo kot že formatiran tekst. Ura nima startedAt, targetSeconds, active flag-a ali ukaza za start/stop, zato elapsed čas ne more biti zanesljivo lokalen in stran je read-only.
7. Rotary input je nameščen na focusable Column znotraj nested pagerjev, medtem ko child Picker in pager lahko prevzameta focus. Implementacija nima robustnega single-focus modela za kg/reps in nima avtomatiziranega UI testa.

Glavni cilj izvedbe je zato: **en versioniran snapshot model, en authoritative sync transport, jasna ločitev durable state / realtime commandov, lokalno računanje časa na uri in determinističen input focus.**

## 2. Trenutna arhitektura

### Phone / Flutter

- lib/features/workouts/data/wear_workout_sync_service.dart
  - serializira template in active workout podatke;
  - sprejema watch workout dogodke;
  - inbound podatke zapisuje v Drift;
  - outbound sync sprožijo Riverpod listenerji v workouts_providers.dart.
- lib/features/nutrition/data/wear_sync_service.dart
  - MethodChannel com.example.herculex/wear;
  - pošilja macro/fasting string, templates, catalog in active session;
  - ima zgodnji event buffer za watch → phone workout dogodke.
- lib/features/fasting/data/fasting_repository.dart
  - phone-side source of truth za FastingSessions;
  - start/stop delujeta lokalno v Drift bazi.
- lib/features/nutrition/presentation/nutrition_providers.dart
  - fasting trenutno pretvori v string in ga pošlje skupaj z macro payloadom.

### Phone / native Android

- android/app/.../MainActivity.kt
  - sprejme Flutter MethodChannel klice;
  - stare sync poti pišejo neposredno na Data Layer paths.
- android/app/.../sync/MobileWearSyncManager.kt
  - novejši manager za active session, macro targets, user token in queued realtime messages.
- android/app/.../PhoneWearListenerService.kt
  - sprejema watch DataClient in MessageClient dogodke;
  - hrani pending workout JSON;
  - objavlja phone notification.
- android/app/.../sync/WearSyncPaths.kt
  - vsebuje podvojene legacy, durable in fast paths.

### Watch / native Wear OS

- android/wear/.../sync/SyncService.kt
  - sprejema phone Data Layer in Message Layer dogodke;
  - hrani active workout prek WorkoutStore in WearDataLayerSyncManager.
- android/wear/.../sync/WearDataLayerSyncManager.kt
  - persistent active-session snapshot in queued realtime messages.
- android/wear/.../workout/WorkoutStore.kt
  - JSON parser/serializer za template, exercise in logged sets.
- android/wear/.../workout/WorkoutViewModel.kt
  - session state, timer, set logging in watch → phone broadcasting.
- android/wear/.../workout/SetLoggerScreen.kt in RotaryHelper.kt
  - kg/reps picker, type picker, accessory picker in rotary routing.
- android/wear/.../workout/WorkoutOngoingService.kt
  - foreground service + Ongoing Activity + persistent notification.
- android/wear/.../nutrition/FastingScreen.kt
  - trenutno prikazuje samo MacroStore.fasting; nima start/stop akcije.
- android/wear/.../sync/MacroStore.kt
  - fasting shrani samo kot string.

## 3. Ugotovitve in vzroki

### P0 — Workout template izgublja planned sets

V syncTemplatesToWatch() se v exJsonList doda samo targetSets. Phone ima pa za vsak template exercise ločene TemplateSets, ki vsebujejo setType, setTypeMetaJson, targetReps, targetWeightKg in isWarmup.

**Posledica:** ura lahko pravilno prikaže vajo, ne pa pravilnega števila, tipa ali targeta posameznih setov. templateExerciseSetsProvider obstaja, vendar trenutno ni del watch sync payloada.

**Lokacije:**

- lib/features/workouts/data/wear_workout_sync_service.dart:51-78
- lib/features/workouts/data/templates_repository.dart:84-120
- lib/data/local/tables.dart: TemplateSets

### P0 — Active-session payload izgublja workout fidelity

_templateJson() namerno pošilja samo identity fields, zato active-session payload nima targetSets, targetReps ali planiranih setov. Set payload pošilja le weight, reps, setType, completed in opcijsko rpe.

Manjkajo pomembna phone polja:

- isWarmup;
- setTypeMetaJson;
- bodyweightKg;
- chainsKg;
- completedAt;
- stabilen setId/wireId;
- target podatki za nedokončane sete.

**Posledica:** phone in ura lahko kažeta isto vajo, vendar različne planned/actual sete, tipe in effective-load podatke.

**Lokacije:**

- lib/features/workouts/data/wear_workout_sync_service.dart:236-258
- lib/data/local/tables.dart:170-202
- android/wear/.../workout/WorkoutStore.kt:135-170

### P0 — Watch nedokončanih setov ne izpolni, ampak jih podvoji

WorkoutStore.parseAndUpdateSession() vse prejete sete pretvori v LoggedSet. Nato WorkoutViewModel.logSet() vedno naredi exercise.sets + LoggedSet(...).

Če phone pošlje planirane nedokončane sete, bo watch pri prvem logiranju dodal nov set na konec. completedSets sicer pravilno šteje samo completed sete, vendar payload od takrat vsebuje podvojene planirane/izvedene sete.

**Rešitev:** model mora eksplicitno ločiti planned set in completed set ali pa mora logSet() zamenjati prvi completed == false set. Pri syncu mora ostati enaka set pozicija.

**Lokacije:**

- android/wear/.../workout/WorkoutViewModel.kt:219-252
- android/wear/.../workout/WorkoutStore.kt:135-170

### P0 — Set type ni canonical čez obe aplikaciji

Phone canonical model ima setType ID in ločen isWarmup. Watch uporablja WatchSetType("warmup", "Warm up"), medtem ko phone inbound kodo warmup prevede v setType = standard in isWarmup = true.

Dodatne težave:

- watch LoggedSet privzeto uporablja "Normal", phone pa "standard";
- watch UI pri vstopu v SetLoggerScreen vedno začne s prvim type-om, ne s planned/current set type-om;
- rpe se na uri parsira v Int, zato se npr. 8.5 zmanjša na 8;
- accessory se shrani v setTypeMetaJson kot neformalni watchAccessory blob, kar ni enako phone accessory/band modelu.

**Rešitev:** canonical wire IDs, ločen boolean isWarmup, normalized parser, Double za RPE in eksplicitna politika za unsupported metadata.

**Lokacije:**

- lib/features/workouts/domain/set_type.dart
- lib/features/workouts/data/wear_workout_sync_service.dart:313-335
- android/wear/.../workout/WorkoutModels.kt:31-43
- android/wear/.../workout/SetLoggerScreen.kt:61-71,107-108

### P0 — Ongoing notification/service se ob update-u ponovno objavlja

Na watch strani SyncService.handleSessionUpdate() vedno kliče startOngoingServiceIfNeeded(). Ob startu handleSessionStart() najprej pokliče handleSessionUpdate() in nato service zažene še enkrat z isNewStart = true.

Na phone strani PhoneWearListenerService.onDataChanged() pri vsakem durable active workout update-u kliče showWorkoutNotification(sessionJson), čeprav bi morala notification nastati samo ob prehodu idle → active.

WorkoutOngoingService vsakič naredi startForeground() in OngoingActivity.apply(). To povzroča re-postanje iste ongoing surface-a in lahko izgleda kot konstantna notifikacija/alert. isNewStart je tudi service-state flag, ne enkratni event.

**Rešitev:**

- start service samo pri novem active sessionu ali restore-u;
- update naj uporabi dedicated UPDATE action oziroma OngoingActivity.update();
- isNewStart naj bo enkratni event, brez setFullScreenIntent pri običajnem update-u;
- phone “Workout Started on Watch” naj se objavi samo pri prvem startu;
- channel naj bo tiho ongoing obnašanje, brez alertiranja ob vsakem snapshotu;
- ob koncu vedno prekliči notification in Ongoing Activity.

**Lokacije:**

- android/wear/.../sync/SyncService.kt:182-245
- android/wear/.../workout/WorkoutOngoingService.kt:42-124
- android/app/.../PhoneWearListenerService.kt:63-84,124-147

### P0 — Fasting je samo string, zato ni realnega elapsed synca

Phone pošilja formattedFastingProvider kot tekst v obliki “14h 22m”. Watch MacroStore shrani ta string in ga izrisuje. Ni pa poslanih:

- hasActiveFast;
- startedAtEpochMs;
- targetSeconds;
- phoneSessionId;
- revision/updatedAt;
- endedAt/completed;
- connection/sync status.

FastingScreen ima samo Back gumb, zato na uri ni mogoče startati ali končati fasta. onRequestSync v workouts_providers.dart:258-287 pošlje macro sync brez fasting argumenta, kar lahko manual sync prepiše fasting na privzeti 0h 0m.

**Rešitev:** fasting postane ločen versioniran durable state + watch → phone commands. Ura iz startedAtEpochMs lokalno računa elapsed, zato ne potrebuje synca vsako sekundo.

**Lokacije:**

- lib/features/nutrition/presentation/nutrition_providers.dart:205-264
- lib/features/fasting/data/fasting_repository.dart:12-43
- android/wear/.../nutrition/FastingScreen.kt:20-82
- android/wear/.../sync/MacroStore.kt:11-46,89-94

### P1 — Dva transporta in dva tipa dogodkov nista še enoten protokol

Trenutno obstajajo:

- legacy MethodChannel → raw DataClient poti za macro/template/catalog;
- MobileWearSyncManager/WearDataLayerSyncManager za active session;
- fast MessageClient snapshot delivery;
- durable DataClient snapshot delivery;
- native pending SharedPreferences;
- Dart pending event queue.

To je uporabno kot prehodna združljivost, vendar ni še enoten source of truth. MessageClient je best-effort in nima persistence/retry, DataClient pa persistent state; zato mora biti MessageClient samo low-latency hint, DataClient pa zadnji znani snapshot.

**Lokacije:**

- docs/wear-sync-smoke-test.md
- android/app/.../MainActivity.kt:409-469
- android/app/.../sync/MobileWearSyncManager.kt
- android/wear/.../sync/WearDataLayerSyncManager.kt

### P1 — Manjka revision/dedupe/conflict policy

Snapshoti nimajo schemaVersion, sessionId, revision, origin, eventId ali updatedAtEpochMs na nivoju workout kontrakta. Zato lahko fast MessageClient in durable DataClient isti snapshot uporabita dvakrat, reconnect pa lahko prinese starejši snapshot za novejšim.

Dart _isApplyingRemoteSession in 500 ms suppression window zmanjšujeta echo, vendar ne rešita vrstnega reda. Poleg tega _deliver() pokliče async handler brez serializacije await, zato se lahko dve async inbound operaciji prekrivata.

**Rešitev:** latest-snapshot-wins po monotoničnem revision + serializiran inbound apply queue. Starejše payload-e ignoriraj, ne popravljaj baze z njimi.

### P1 — Rotary input nima jasnega focus ownershipa

SetLoggerScreen ima nested VerticalPager → HorizontalPager → focusable Column → child Picker komponenti. RotaryHelper poskuša focus dobiti s 15 ponovitvami requestFocus(), hkrati pa uporablja onPreRotaryScrollEvent in onRotaryScrollEvent na parentu.

To je občutljivo na:

- pager, ki focus prevzame nazaj;
- child Picker, ki dogodek porabi ali spremeni scroll;
- premajhen/neenoten pixel threshold;
- razliko med RSB, physical bezel in touch bezel;
- focusedCol spremembo samo prek tap-a.

**Rešitev:** na logger strani imeti en aktiven rotary target (WEIGHT ali REPS), eksplicitno focus requester stanje, en handler in haptic/visual feedback. Pri multi-value controlu naj tap zamenja aktivno polje, bezel pa spreminja samo izbrano polje.

**Lokacije:**

- android/wear/.../workout/RotaryHelper.kt:85-132
- android/wear/.../workout/SetLoggerScreen.kt:152-180,215-291

### P1 — Offline/reconnect lahko ustvari zastarele ali preštevilne dogodke

Realtime queues hranijo vsak message kot ločen element. Pri workout snapshotih je to nepotrebno: offline obdobje lahko ustvari veliko zastarelih snapshotov, ki se po reconnectu pošljejo zaporedoma. Za state je boljši samo zadnji snapshot; commandi (fast start/stop, finish) pa morajo imeti svoj command ID in ACK.

### P2 — Testna pokritost ne pokriva native watch kritičnih poti

Dart testi pokrivajo event buffer in exercise resolver, ni pa JVM/native testa za:

- workout JSON round-trip;
- canonical set type mapping;
- planned-set replacement;
- fasting payload in command ACK;
- notification transition policy;
- rotary step accumulator/focus state.

## 4. Ciljna arhitektura

### 4.1 Enoten versioniran envelope

Za vse domain state payload-e uvedi enako osnovo:

~~~json
{
  "schemaVersion": 1,
  "entity": "active_workout | fasting",
  "entityId": "stable-local-or-session-id",
  "revision": 42,
  "origin": "phone | watch",
  "updatedAtEpochMs": 1780000000000,
  "payload": {}
}
~~~

Za workout payload vsebuje:

~~~json
{
  "startedAtEpochMs": 1780000000000,
  "currentExerciseIndex": 0,
  "currentSetIndex": 1,
  "template": { "id": "...", "name": "..." },
  "exercises": [
    {
      "wireId": "exercise-0",
      "template": {
        "catalogExerciseId": 1,
        "slug": "barbell-bench-press",
        "name": "Barbell Bench Press",
        "targetSets": 4,
        "plannedSets": [
          {
            "wireId": "set-0",
            "setIndex": 1,
            "setType": "standard",
            "isWarmup": false,
            "targetReps": 8,
            "targetWeightKg": 80.0,
            "targetRepsMin": 8,
            "targetRepsMax": 10,
            "setTypeMetaJson": null
          }
        ]
      },
      "sets": [
        {
          "wireId": "set-0",
          "setIndex": 1,
          "weight": 80.0,
          "reps": 8,
          "rpe": 8.5,
          "setType": "standard",
          "isWarmup": false,
          "setTypeMetaJson": null,
          "completed": true,
          "completedAtEpochMs": 1780000010000
        }
      ]
    }
  ]
}
~~~

Ne pošiljaj že formatiranega elapsed teksta kot source of truth. Tekst je lahko samo derived UI field.

### 4.2 Transport policy

- DataClient: durable latest state; vedno z setUrgent() samo za user-visible active state, ne za nepotrebne ponavljajoče se ticke.
- MessageClient: fast delivery istega snapshot-a ali command RPC-ja; nikoli ni edina kopija.
- Workout snapshot: coalesced latest snapshot, revision guard.
- Fasting start/stop: command z commandId, lokalna queue na uri, phone ACK in nato phone → watch authoritative state.
- Templates/catalog/macros/fasting naj gredo skozi en native manager; Flutter MethodChannel naj ostane samo API façade.

### 4.3 Source of truth

- Phone Drift ostane authoritative za workout history in fasting history.
- Watch ima lokalni durable cache za active workout in active fasting state, da lahko UI/timer deluje brez povezave.
- Pri simultanem editiranju istega active workouta uporabi deterministično pravilo: višji revision zmaga; če sta revisiona enaka, zmaga zadnji updatedAtEpochMs. Vsak sprejeti snapshot se zapiše v diagnostics log.

## 5. Izvedbeni plan

### Faza 0 — Baseline, observability in reproducibility

**Odvisnosti:** nobene.

1. Dodaj docs/wear-sync-debugging.md z matriko smeri, transporta, revisiona, node ID-ja, časa in resulta.
2. Dodaj strukturiran log prefix na obeh straneh: entity, revision, origin, eventId, path, delivery=message|data, apply=accepted|ignored|failed.
3. Izvedi baseline na vsaj:
   - phone-started workout;
   - watch-started workout;
   - phone edit med connected/disconnected stanjem;
   - watch edit med connected/disconnected stanjem;
   - active → finish na obeh straneh;
   - fasting start/stop na phone strani;
   - Samsung physical bezel.
4. Vse teste izvajaj z obema sveže zgrajenima APK-jema. flutter run sam po sebi ne zagotovi novega :wear APK-ja.

**Exit criteria:** za vsak simptom obstaja reproducibilen test case in log, ki pokaže, ali je težava v serialization, transportu, apply layerju, UI-ju ali notification layerju.

### Faza 1 — Canonical sync contract in en transport

**Odvisnosti:** Faza 0.

**Predlagane datoteke:**

- lib/features/workouts/data/wear_workout_sync_service.dart
- lib/features/nutrition/data/wear_sync_service.dart
- android/app/.../sync/WearSyncPaths.kt
- android/app/.../sync/MobileWearSyncManager.kt
- android/wear/.../sync/WearSyncPaths.kt
- android/wear/.../sync/WearDataLayerSyncManager.kt
- nova Dart contract/codec datoteka in nova Kotlin contract/codec datoteka

**Naloge:**

1. Definiraj schemaVersion, canonical set type ID-je, envelope fields in backward-compatible parser.
2. Razširi managerje tako, da templates, catalog, macros, active workout in fasting uporabljajo enotne named paths.
3. Legacy raw DataClient metode obdrži samo začasno za fallback; dodaj migration flag/log, nato jih odstrani, ko smoke testi preidejo.
4. Dodaj revision allocator na obeh straneh in lastAppliedRevision persistence.
5. Dodaj serializiran inbound apply queue v Dart in native dedupe pred parseAndUpdateSession().
6. Snapshot queue coalesce: pri active state hrani samo najnovejši pending snapshot; command queue ostane FIFO z ACK.

**Exit criteria:** isti snapshot, prejet po MessageClient in DataClient poti, se v bazo/UI uporabi največ enkrat; starejši snapshot ne more prepisati novejšega.

### Faza 2 — Workout fidelity: templates, planned sets in actual sets

**Odvisnosti:** Faza 1.

**Predlagane datoteke:**

- lib/features/workouts/data/wear_workout_sync_service.dart
- lib/features/workouts/presentation/workouts_providers.dart
- lib/features/workouts/data/templates_repository.dart
- lib/data/local/tables.dart samo, če so potrebne dodatne wire oznake
- android/wear/.../workout/WorkoutModels.kt
- android/wear/.../workout/WorkoutStore.kt
- android/wear/.../workout/WorkoutViewModel.kt
- android/wear/.../workout/SetLoggerScreen.kt

**Naloge:**

1. syncTemplatesToWatch() naj prejme TemplateSetData po exercise-u in pošlje vse planned fields.
2. Active-session payload naj pošlje targetSets, planned sets in vsa podprta actual-set polja.
3. Uvedi canonical LoggedSet.setType = standard, ločen isWarmup, Double rpe in explicit metadata.
4. Watch parser naj normalizira stare payload-e (Normal, manjkajoč isWarmup, warmup) brez izgube podatkov.
5. logSet() naj posodobi prvi nedokončani planned set; samo če ga ni, naj doda nov set.
6. Set logger naj za trenutno pozicijo uporabi planned/current set weight, reps in set type; ne sme vedno začeti iz exercise.template.prevWeight/prevReps ali standard.
7. Določi unsupported-field policy:
   - ali watch podpira setTypeMetaJson, bodyweight, chains in accessories v celoti;
   - ali jih samo prikaže/round-trippa;
   - ali jih označi kot unsupported, vendar jih ne zavrže.
8. Ohraniti exercise identity ladder: catalogExerciseId → slug → exact name → normalized name → alias.

**Exit criteria:** template s 4 seti, različnimi target reps/weights in različnimi set tipi je na uri identičen; phone-started active workout se na uri lahko nadaljuje brez dupliciranja setov; watch-started workout ohrani type/warmup/RPE pri zapisu v Drift.

### Faza 3 — Notification in ongoing activity lifecycle

**Odvisnosti:** Faza 1; lahko se razvija vzporedno s Fazo 2.

**Predlagane datoteke:**

- android/wear/.../sync/SyncService.kt
- android/wear/.../workout/WorkoutOngoingService.kt
- android/wear/.../MainActivity.kt
- android/app/.../PhoneWearListenerService.kt
- android/app/src/main/AndroidManifest.xml
- android/wear/src/main/AndroidManifest.xml

**Naloge:**

1. Loči state transitions START, UPDATE, END in RESTORE.
2. START naj foreground service zažene samo enkrat; odstrani double-start iz handleSessionStart().
3. UPDATE naj ne kliče startForegroundService() kot nov start. Uporabi update action ali recover/update obstoječega Ongoing Activity.
4. isNewStart naj se resetira po prvem startu in se ne prenaša na update.
5. Odstrani setFullScreenIntent za običajne sync update-e; uporabi ga samo, če je to zavestno zahtevano za pravi user-initiated start.
6. Phone notification “Workout Started on Watch” naj se objavi samo pri novem prehodu v active state. Durable update naj ne povzroča novega alert-a.
7. Preveri notification channel importance, setOnlyAlertOnce, setSilent in behavior na Samsung Wear OS.
8. Pri END prekliči foreground service, notification in Ongoing Activity na obeh straneh; po koncu ne sme biti restart-a zaradi stale DataItem-a.
9. Dodaj state machine test za idle → start → update* → end, reconnect in process restore.

**Exit criteria:** med 20 zaporednimi set updates je največ ena ongoing površina in noben ponavljajoči se alert; po finish/discard notification izgine in se po reconnectu ne vrne.

### Faza 4 — Fasting end-to-end

**Odvisnosti:** Faza 1; lahko se razvija vzporedno s Fazama 2–3.

**Predlagane datoteke:**

- lib/features/fasting/data/fasting_repository.dart
- lib/features/fasting/presentation/fasting_providers.dart
- lib/features/nutrition/presentation/nutrition_providers.dart
- lib/features/nutrition/data/wear_sync_service.dart
- android/app/.../PhoneWearListenerService.kt
- android/app/.../MainActivity.kt
- android/wear/.../sync/WearSyncPaths.kt
- android/wear/.../sync/WearDataLayerSyncManager.kt
- android/wear/.../sync/MacroStore.kt ali nov FastingStore.kt
- android/wear/.../nutrition/NutritionViewModel.kt
- android/wear/.../nutrition/FastingScreen.kt
- android/wear/.../complication/FastingComplicationService.kt

**Naloge:**

1. Uvedi FastingSnapshot z hasActiveFast, startedAtEpochMs, targetSeconds, phoneSessionId, endedAtEpochMs, completed, revision, updatedAtEpochMs.
2. Phone naj snapshot pošlje ob startu, stopu, app resume-u in manual syncu. Elapsed string naj bo derived.
3. Watch naj elapsed računa lokalno iz epoch časa in System.currentTimeMillis(), z zaščito pred negativnim časom/clock changes.
4. Fasting screen naj prikaže stanje, elapsed, target/progress in Start fast/Stop fast akcijo.
5. Watch start/stop naj pošljeta command z commandId; če povezave ni, naj se command varno shrani v FIFO queue in pošlje ob onPeerConnected.
6. Phone naj command aplicira prek FastingRepository, pošlje ACK in nato authoritative snapshot nazaj na uro.
7. Če pride do konflikta (phone in watch skoraj hkrati), naj zmaga phone-side transaction/revision; watch naj se popravi s snapshotom.
8. Manual onRequestSync mora vključevati fasting snapshot; nikoli ne sme resetirati active fasting state samo zato, ker macro totals niso pripravljeni.
9. Komplikacija naj uporablja persisted fasting state in pravilno tap action; preveri omejitve refresh intervala in po potrebi prikaži zadnji znani elapsed snapshot.

**Exit criteria:** start na telefonu se na uri pokaže z realnim elapsed časom; start/stop na uri spremeni phone Drift session; vse deluje po reconnectu; manual sync ne resetira active fasta.

### Faza 5 — Samsung rotating bezel in rotary UX

**Odvisnosti:** Faza 2.

**Predlagane datoteke:**

- android/wear/.../workout/RotaryHelper.kt
- android/wear/.../workout/SetLoggerScreen.kt
- po potrebi android/wear/build.gradle.kts za uskladitev Compose/Wear/Horologist verzij

**Naloge:**

1. Uvedi RotaryTarget { WEIGHT, REPS } in samo en aktiven target na logger strani.
2. Focus requester naj se aktivira ob vstopu na page 0 in po spremembi pager page; ne uporabljaj samo časovno omejenega retry loop-a.
3. Parent pager naj ne prestreza rotary eventa, ko je logger v value-edit načinu. Child picker naj dobi event samo za aktivno polje.
4. Uporabi en threshold/accumulator, ki podpira majhne in velike delta evente; vsak accepted step naj ima visual update in optional haptic feedback.
5. Tap na kg/reps naj zamenja target; jasno obarvaj trenutno polje. Bezel clockwise naj poveča, counter-clockwise zmanjša vrednost.
6. Preveri boundary behavior: 0 kg, max kg, 1 rep, max reps, hitri obrati in en detent.
7. RPE dialog in set-type list naj imata ločen, jasen rotary owner.
8. Dodaj pure unit test za step accumulator in manual matrix test za:
   - Galaxy Watch Classic s physical rotating bezel;
   - Galaxy Watch brez physical bezel/RSB;
   - touch bezel oziroma emulator;
   - page 0, page 1, page 2 in RPE dialog.

**Exit criteria:** na fizičnem Samsung rotating bezel-u lahko uporabnik z enim tapom izbere kg ali reps in nato brez izgube focusa spreminja samo izbrano vrednost; horizontal/vertical pager ne ukrade inputa.

### Faza 6 — Verification, regression in release checklist

**Odvisnosti:** Faze 1–5.

1. Dart testi:
   - contract encode/decode;
   - backward compatibility;
   - set type/warmup normalization;
   - revision/dedupe;
   - fasting snapshot formatting;
   - command queue semantics.
2. Kotlin/JVM testi:
   - WorkoutStore round-trip;
   - planned-set replacement;
   - FastingStore elapsed calculation;
   - notification transition reducer;
   - rotary step accumulator.
3. Native/instrumentation testi:
   - SyncService DataClient/MessageClient routing;
   - service start/update/end idempotence;
   - notification count and cancellation.
4. Device smoke test:
   - phone ↔ watch connected;
   - Bluetooth off/on;
   - phone app killed;
   - watch app/process recreated;
   - phone locked and watch locked;
   - watch battery saver/Doze kjer je mogoče;
   - both APKs installed from same build/version.
5. Run required verification:

~~~powershell
dart analyze lib test
flutter test
$env:JAVA_HOME='C:\Program Files\Android\Android Studio\jbr'
$env:Path="$env:JAVA_HOME\bin;$env:Path"
.\gradlew.bat :app:compileDebugKotlin :wear:compileDebugKotlin
~~~

6. Posodobi docs/wear-sync-smoke-test.md z novimi payload fields, expected notification behavior, fasting cases in rotary matrix.

**Release gate:** noben P0 simptom ni odprt; oba APK-ja sta zgrajena in nameščena; connected/offline/reconnect test je uspešen; 20 sequential workout updates ne ustvari dodatnih alertov; fasting state je pravilen po cold startu in manual syncu.

## 6. Acceptance matrix

| Področje | Sprejemni kriterij |
|---|---|
| Phone → watch workout | Vaja, planned set count, target reps/weight, set type in current cursor so enaki na obeh straneh. |
| Watch → phone workout | Novi/posodobljeni seti se zapišejo na isti poziciji; ni podvojenih planned setov. |
| Warmup/type | standard, drop, rest_pause, myo_reps, partials, negatives, pause in warmup se round-tripajo brez spremembe pomena. |
| RPE | 8.5 ostane 8.5. |
| Notification | Start ustvari eno ongoing površino; update je tih; end jo odstrani. |
| Reconnect | Zadnji snapshot zmaga; stale snapshot ga ne prepiše; commandi se pošljejo enkrat in dobijo ACK. |
| Fasting | Phone-started fast na uri računa elapsed lokalno iz start epoch-a. |
| Fasting controls | Watch start/stop spremeni phone Drift state in se po reconnectu reconcila. |
| Manual sync | Ne resetira active fasting state. |
| Rotary | Physical bezel spremeni samo trenutno izbrano kg/reps polje in deluje na vseh relevantnih screenih. |
| Process death | Po restore-u active workout in fasting timer nadaljujeta iz persisted epoch/state. |

## 7. Pomembne odločitve za izvedbo

1. Ne dodajaj sekundnega fasting sync ticka čez Data Layer; pošlji start epoch in računaj čas lokalno.
2. Ne uporabljaj MessageClient kot edinega vira resnice; vedno persistiraj snapshot v DataClient/local store.
3. Ne rešuj notification problema samo z večjim delay-em ali daljšim suppression windowom; težavo je treba rešiti z idempotentnim lifecycle/state machine.
4. Ne obravnavaj watch setType kot display label; po wire-u naj gredo stable IDs.
5. Ne uvajaj novega DB migrationa, dokler ni dokazano, da obstoječa Drift shema ne zadošča. Večina potrebnih sprememb je v wire contractu in watch cache modelu.
6. Legacy payload parser mora ostati vsaj eno release obdobje backward-compatible, ker se watch APK lahko posodobi ločeno od phone APK-ja.

## 8. Reference in uradne smernice

- Android Data Layer client types: https://developer.android.com/training/wearables/data/client-types
- Android Data Items in urgent sync: https://developer.android.com/training/wearables/data/data-items
- Wear OS rotary input with Compose: https://developer.android.com/training/wearables/compose/rotary-input
- Wear OS Ongoing Activity: https://developer.android.com/training/wearables/notifications/ongoing-activity
- Samsung bezel interaction principles: https://developer.samsung.com/one-ui-watch-tizen/interaction/bezel.html

Uradne smernice potrjujejo ključne arhitekturne odločitve: DataClient je persistent/offline-capable, MessageClient pa nima persistence/retry; rotary input zahteva pravilno focus ownership; Ongoing Activity je namenjen aktivnemu workoutu, vendar je treba ob update-u posodobiti obstoječo ongoing površino, ne ustvarjati nove.

## 9. Prompt za naslednji chat

Kopiraj celoten prompt iz naslednjega bloka v nov chat, skupaj z repo kontekstom:

~~~text
Delaj v repozitoriju C:\Users\marti\AMS d.o.o\Herculex.

Preberi in upoštevaj dokument:
docs/watch-phone-sync-analysis-and-plan.md

Tvoj cilj je IZVESTI plan iz dokumenta, ne samo opisati rešitev. Najprej preberi obstoječo kodo in preveri, ali so se medtem pojavile spremembe. Ne spreminjaj scope-a brez jasne utemeljitve. Ohrani backward compatibility za vsaj en release, ker se phone in Wear APK lahko posodobita ločeno.

Glavni cilj:
1. Stabiliziraj phone ↔ Samsung Wear OS sync.
2. Zagotovi popoln round-trip workout data: exercise identity, planned sets, target reps/weight, actual reps/weight, setType, isWarmup, RPE, metadata, cursor in session start time.
3. Odpravi podvajanje ali konstantno re-objavljanje workout notifikacij/ongoing activity.
4. Omogoči pravi fasting sync: startedAt epoch, target, active state, local elapsed timer in start/stop na uri.
5. Popravi physical Samsung rotating bezel za kg/reps picker z determinističnim focus ownershipom.

Obvezna pravila izvedbe:
- Najprej vzpostavi baseline/logging in test fixtures.
- Uvedi versioniran envelope z schemaVersion, entity, entityId, revision, origin, updatedAtEpochMs.
- DataClient naj bo durable latest state; MessageClient samo fast path/command, nikoli edini source of truth.
- Uporabi revision/dedupe in serializiran inbound apply queue; stare snapshot-e ignoriraj.
- Snapshot queue coalesce-aj na zadnji snapshot; command queue mora biti FIFO z commandId in ACK.
- Phone Drift je authoritative za workout/fasting history; watch ima durable active-state cache.
- V workout payload ne izgubi TemplateSets ali SetEntries polj. Canonical setType ID in ločen isWarmup.
- Watch logSet mora izpolniti prvi planned nedokončani set, ne vedno dodati novega.
- RPE naj ohrani half-points.
- Notification lifecycle mora biti idempotenten: START, UPDATE, RESTORE, END. Ne zaganjaj foreground service-a na vsak update in ne objavljaj phone start notification na vsak durable update.
- Fasting elapsed računaj lokalno iz startedAtEpochMs, ne iz formatiranega stringa.
- Rotary screen naj ima en aktiven target (WEIGHT ali REPS), jasen focus requester, tap za menjavo targeta, clockwise increase in counter-clockwise decrease.
- Ne uporabljaj destruktivnih git ukazov in ne prepiši nepovezanih user sprememb.

Predlagaj in nato izvedi po fazah:
Faza 0 observability/baseline → Faza 1 contract/transport → Faza 2 workout fidelity → Faza 3 notifications → Faza 4 fasting → Faza 5 rotary → Faza 6 verification.

Po vsaki fazi:
- navedi spremenjene datoteke;
- zaženi relevantne unit/static/native teste;
- preveri acceptance criteria iz dokumenta;
- popravi regresije, preden nadaljuješ.

Na koncu obvezno zaženi:
dart analyze lib test
flutter test
$env:JAVA_HOME='C:\Program Files\Android\Android Studio\jbr'
$env:Path="$env:JAVA_HOME\bin;$env:Path"
.\gradlew.bat :app:compileDebugKotlin :wear:compileDebugKotlin

Nato pripravi:
1. kratek povzetek implementacije;
2. seznam vseh spremenjenih datotek;
3. rezultate testov/buildov;
4. preostala tveganja ali omejitve, predvsem kar zahteva fizični Samsung rotating bezel in connected/offline device test;
5. posodobljen docs/wear-sync-smoke-test.md.
~~~

