# Fazni načrt: odprava "race condition" napak v Phone↔WearOS sinhronizaciji (Herculex)

## Kontekst

Audit (`docs/app-audit-report-2026-08-10.md`) je izpostavil, da je sinhronizacija med telefonom in Wear OS uro arhitekturno krhka na štirih med seboj povezanih področjih (ENG-06 do ENG-19). Namen tega načrta je te napake odpraviti sistematično, brez lokalnega oblaka — gre izključno za popravke Dart (Flutter, telefon) in Kotlin (Wear OS + phone-native) kode.

Raziskava (branje kode, ne samo audit poročila) je potrdila **18 konkretnih napak** na točnih lokacijah v kodi, na obeh platformah. Ключne ugotovitve, ki jih ta načrt naslavlja:

- **Identiteta seje (ENG-08, ENG-09):** Sporočila med uro in telefonom nimajo stabilnega session UUID-ja, ki bi se preverjal ob uporabi (apply-time). `_handleWatchWorkoutUpdated` (`wear_workout_sync_service.dart:150-193`) posodobi *karkoli trenutno je* `activeSession` na telefonu, ne glede na to, na katero sejo se je nanašalo sporočilo z ure. `_handleWatchWorkoutEnded` (linije 195-211) sploh ne prejme identitete seje — konča *karkoli* `watchActiveSession()` trenutno vrne. Enak vzorec na Kotlin strani (`PhoneWearListenerService.savePendingWorkout`, linije 261-268: en sam SharedPreferences slot, brez preverjanja kolizije).
- **Kaskadno sesutje (ENG-06, ENG-19):** `_enqueueRemoteApply` (`wear_workout_sync_service.dart:213-216`) uporablja `Future.then()` brez `onError` — ko en `apply()` vrže izjemo, `_remoteApplyQueue` postane trajno "errored" future in **vse nadaljnje** posodobitve z ure so tiho zavržene do ponovnega zagona aplikacije. Na Kotlin strani je še huje: `flushPendingRealtimeMessages()` (`WearDataLayerSyncManager.kt:80-111`, `MobileWearSyncManager.kt:139-170`) ob prvi neuspešni dostavi naredi `break` na celotni vrsti, ta vrsta pa je persistirana v SharedPreferences — torej blokada **preživi tudi ponovni zagon**. Dodatno, `onPeerConnected` (`PhoneWearListenerService.kt:252-259`) zaporedoma kliče `replayPersistentState()` in nato `flushPendingRealtimeMessages()` brez izolacije — če prvi durable "put" pade, se niti flush ne izvede.
- **Transakcije in izguba podatkov (ENG-07, ENG-10, ENG-12):** Na obeh platformah se "dedupe/revision" oznaka zapiše **pred** uspešnim durable zapisom, ne po njem. Dart: `WearDedupeState.shouldAccept` (`wear_sync_contract.dart:119-139`) zapiše revizijo kot stranski učinek preverjanja, **preden** `_syncSessionStateToDrift` (linije 274-456) sploh poskusi zapisati v bazo. Kotlin: `AppliedRevisionStore.shouldAccept` (`WearSyncContract.kt:92-108`) enako zapiše SharedPreferences oznako **pred** `persistSession`/`WorkoutStore.parseAndUpdateSession` (`SyncService.kt:315-324`). Enak vzorec (in slabši, ker sploh ni retry-varen) je v `nutrition_providers.dart` pri hitrem dodajanju obrokov/postu (linije 292-360) — komentar v kodi trdi "obdrži za retry", a dejanska logika to onemogoča. Poleg tega `_syncSessionStateToDrift` sploh ni ovita v `_db.transaction(...)`, čeprav ta vzorec v repozitoriju že obstaja (`workouts_repository.dart`, `setMachineConfig`, `reorderWorkoutExercises`).
- **Wear "Lifecycle" UX (ENG-14, ENG-15, ENG-16):** `WorkoutOngoingService` se ustavi izključno preko `activeViewModel?.endSessionFromPhone()` (`SyncService.kt:347-364`) — nullable singleton, ki je `null`, kadar je Wear aplikacija v ozadju/reciklirana. Ko je `null`, obvestilo/foreground servis ostane trajno prižgan. Klik na obvestilo ne naredi ničesar, ker Wear `MainActivity.kt` sploh ne bere `open_active_workout` extra-ja, njegov `LaunchedEffect(intent)` pa se ne re-sproži ob `onNewIntent`. Poleg tega `WorkoutViewModel.kt` (linije 315-382) zaporedoma čaka na durable "put" preden pošlje hitro "message" — brez izolacije, torej padec durable puta ubije tudi hitro pot.

Cilj: fazni pristop, kjer se protokol-lomljive spremembe (session UUID + revizija) izvedejo enkrat, skupaj, čim prej — vse ostalo pa se lahko izvaja neodvisno na eni platformi hkrati.

## Priporočilo: Session UUID + monotona revizija = en skupni `schemaVersion: 2` premik

Obe spremembi (stabilen session UUID in monotona/Lamport revizija namesto `System.currentTimeMillis()`) spreminjata isti wire-envelope na obeh platformah (`WearSyncEnvelope`/`SyncEnvelope`). Ločeni izvedbi bi pomenili dve ločeni "stari peer / novi peer" prehodni okni namesto enega, poleg tega je kolizijska logika v Fazi 4 (#11) odvisna od **obeh** polj hkrati (kateri od dveh trčečih sej zmaga). Zato: **ena sama, skupna sprememba protokola v Fazi 1**, z `schemaVersion` iz 1 na 2.

**Izven obsega:** `lib/data/sync/sync_engine.dart` — trenutno v delu (uncommitted), audit finding #2 (lažen cloud sync). Ne dotikaj se tega v okviru tega načrta.

---

## Faza 0 — Testna osnova (majhna, naredi prva)

**Namen:** Pred spremembo protokola postaviti cross-decoder contract teste, da ima Faza 1 varnostno mrežo od začetka.

**Pristop:**
- Razširi `test/wear_sync_contract_test.dart` s fixturami trenutne (v1) oblike envelope-a (encode/decode round-trip, `WearDedupeState.shouldAccept` primeri, legacy-fallback primer).
- Dodaj Kotlin ekvivalent (nova datoteka, npr. `android/wear/src/test/java/com/ams/herculex/sync/WearSyncContractTest.kt`), ki preverja `WearSyncContract.decodeEnvelope`/`AppliedRevisionStore.shouldAccept` po istih scenarijih.

**Datoteke:** `test/wear_sync_contract_test.dart`, `android/wear/src/test/java/com/ams/herculex/sync/WearSyncContractTest.kt` (nova)

**Koordinacija:** samo testi, brez spremembe protokola.

**Verifikacija:** `flutter test test/wear_sync_contract_test.dart` in `./gradlew :wear:test` zeleno na trenutni kodi.

---

## Faza 1 — Protokol v2: stabilen session UUID + Lamport/monotona revizija (usklajeno, lomljivo)

**Namen:** Rešiti oba strukturna predpogoja: session UUID, ki preživi celoten življenjski cikel seje (start → update → end), in revizijo, ki ne more iti nazaj ali trčiti med restarti/urnim zamikom.

**Rešuje:** ENG-08/ENG-09 (identiteta seje, konec seje brez identitete) + osnovo za ENG-06/07/10/12/19.

### 1a. Stabilen session UUID
- Ob nastanku seje (`WorkoutsRepository.startSession()` v `lib/features/workouts/data/workouts_repository.dart`) generiraj UUID (`package:uuid`) in ga persistiraj kot nov stolpec na `WorkoutSessions` Drift tabeli (migracija v `lib/data/local/database.dart`).
- Vsak odhodni envelope (`pushActiveSessionToWatch`, `wear_workout_sync_service.dart:678-685`, in nova `notifySessionEnded()` pot) nastavi `entityId` na ta UUID — namesto trenutnega `'phone_session_${session.id}'`, ki je lokalni auto-increment ID, nikoli poslan ob koncu seje.
- Zrcali na Wear strani: `WorkoutSession` (Kotlin) dobi `sessionId: String`, generiran z `UUID.randomUUID()` ob `startWorkout()` ali prevzet iz vhodnega envelope-a ob `updateSessionFromRemote()`.
- **Apply-time gating (dejanski popravek ENG-08/09):** `_handleWatchWorkoutUpdated` mora primerjati `envelope.entityId` s trenutno aktivno sejo na telefonu in aplicirati samo ob ujemanju (ali če telefon nima aktivne seje — "adopt" primer). Neujemajoč UUID = zavrzi, ne aplicira se na napačno sejo.
- **Konec seje z identiteto:** `notifySessionEnded()` in `_handleWatchWorkoutEnded` (nov podpis: `_handleWatchWorkoutEnded(String? envelopeJson, [bool isDiscard = false])`) preverita `entityId` pred brisanjem/končanjem — to neposredno zapre scenarij "konča se napačna seja po reconnect/restartu".
- Kotlin zrcaljenje: `handleSessionEnd()` (`SyncService.kt:347-364`) in `MESSAGE_ACTIVE_SESSION_END`/`MESSAGE_WATCH_SESSION_END` (trenutno prazen payload, `MobileWearSyncManager.kt:54`, `WorkoutViewModel.kt:362-382`) nosita pravi enkodiran `SyncEnvelope` z `entityId`.

### 1b. Lamport/monotona revizija
- Zamenjaj `WearRevisionAllocator` (`wear_sync_contract.dart:102-114`) s shemo, ki je monotona **čez restart procesa**: persistiraj zadnjo izdano revizijo (SharedPreferences) in ob `next()` vrni `max(persisted_last + 1, DateTime.now().millisecondsSinceEpoch)`, nato persistiraj novo vrednost. Enako na Kotlin strani (`WorkoutStore.kt:227`, `WearSyncContract.kt:68`).
- `updatedAtEpochMs` ostane pravi wall-clock timestamp (samo tie-breaker/debug) — spremeni se le `revision`.
- `WearDedupeState.shouldAccept`/`AppliedRevisionStore.shouldAccept` primerjalna logika ostaja — hrošč je v alokatorju, ne v komparatorju.

### 1c. Strožja validacija envelope-a (ENG povezano z ENG-19 razširljivostjo)
- Validiraj `origin` proti znanim konstantam, `entityId` proti prazni/napačni obliki (zdaj load-bearing za apply-time gating).
- **Odstrani legacy-fallback dedupe bypass** (`schemaVersion==0 && revision==0 && updatedAtEpochMs==0` → trenutno vedno sprejeto) — ob usklajenem `schemaVersion: 2` premiku na obeh straneh ni več potrebe po tem fallbacku; če obstaja še kakšna stara nameščena watch aplikacija v produkciji, naj fallback raje "fail closed" (zavrne) kot "vedno sprejme".

**Datoteke (Dart):** `lib/features/nutrition/data/wear_sync_contract.dart`, `lib/features/workouts/data/wear_workout_sync_service.dart`, `lib/features/workouts/data/workouts_repository.dart`, `lib/data/local/database.dart`, `pubspec.yaml`

**Datoteke (Kotlin):** `android/wear/src/main/java/com/ams/herculex/sync/WearSyncContract.kt`, `.../workout/WorkoutStore.kt`, `.../workout/WorkoutViewModel.kt`, `.../sync/SyncService.kt`, `android/app/src/main/kotlin/com/ams/herculex/sync/MobileWearSyncManager.kt`, `android/app/src/main/kotlin/com/ams/herculex/PhoneWearListenerService.kt`

**Koordinacija:** protokol-lomljivo, telefon in ura morata iti ven usklajeno (ali z eno-smerno tolerantnostjo do v1 med prehodom, ki samo zavrne s čistim logom, brez polnega interopa).

**Verifikacija:**
- Razširjeni testi v `test/wear_sync_contract_test.dart` + Kotlin ekvivalent: monotona revizija čez simuliran restart, dedupe pravilno zavrne isto-revizijski replay, `entityId` neujemanje prepreči apply.
- Integracijski test `WearWorkoutSyncService` z lažnim repozitorijem: update za sejo B med aktivno sejo A se zavrže brez mutacije A.
- Ročni scenarij: začni trening na telefonu, nato na uri (letalski način vmes) — preveri, da se seje ne pomešajo.
- Ročni scenarij: force-kill telefonske app med treningom, nato update z ure — revizija se ne sme "resetirati" pod prejšnjo vrednostjo.

---

## Faza 2 — Dart: apply-after-dedupe vrstni red + transakcijski zapis + popravek vrste

**Namen:** Popraviti "označi-pa-šele-nato-zapiši" napako in netransakcijski multi-write apply, po vzoru že pravilnega vzorca za treninge (`_syncSessionStateToDrift` + `markWatchWorkoutApplied()` po uspehu).

**Rešuje:** ENG-07/10/12 (dedupe/apply vrstni red, transakcije), ENG-06 (poisoning vrste).

**Pristop:**
- **Dedupe-after-success (ENG-07/10/12):** V `nutrition_providers.dart` (`onWatchFastingCommand` linije 292-322, `onWatchQuickAddCommand` linije 324-360) premakni `appliedFastingCommands.add(commandId)`/`appliedQuickAddCommands.add(commandId)` na **po** uspešnem Drift zapisu, po vzoru `wear_workout_sync_service.dart:128-133`. Enako razdeli `WearDedupeState.shouldAccept` na `wouldAccept()` (čisto preverjanje) in `commit()` (mutacija), klicano šele po uspešnem `_syncSessionStateToDrift` + `markWatchWorkoutApplied()`.
- **Transakcijski apply:** ovij celotno telo `_syncSessionStateToDrift` (`wear_workout_sync_service.dart:274-456`) v `_db.transaction(() async { ... })`, po vzoru že obstoječega v `workouts_repository.dart` (`setMachineConfig`, `reorderWorkoutExercises`). Preveri, da retry-logika za `createCustomExercise` (unique constraint, linije 316-336) ostane transaction-safe.
- **Popravek vrste (ENG-06/19, Dart stran):** `_enqueueRemoteApply` (linije 213-216) trenutno `_remoteApplyQueue = _remoteApplyQueue.then((_) => apply());` brez `onError` — en padec zastrupi vse nadaljnje klice do restarta. Popravi tako, da veriga vedno "reset-a" na uspešen future ne glede na prejšnji izid, npr. `_remoteApplyQueue = _remoteApplyQueue.catchError((_) {}).then((_) => apply());`.

**Datoteke:** `lib/features/workouts/data/wear_workout_sync_service.dart`, `lib/features/nutrition/data/wear_sync_contract.dart`, `lib/features/nutrition/presentation/nutrition_providers.dart`

**Koordinacija:** samo Dart, brez spremembe wire formata. Logično sledi Fazi 1 (ista funkcija se dotika obeh), a ni tehnično blokirana z njo.

**Verifikacija:**
- Unit test: `addSet` vrže izjemo sredi multi-exercise payload-a → baza ostane nespremenjena (rollback), dedupe ni commitan (retry deluje).
- Unit test: `repo.startSession` vrže izjemo → `appliedFastingCommands` NE vsebuje `commandId`, ponovna dostava se ponovno poskusi.
- Unit test: dva zaporedna `_enqueueRemoteApply` klica, prvi vrže izjemo → drugi se še vedno izvede (trenutno se ne bi).

---

## Faza 3 — Dart: rekonciliacija vaj/setov po stabilnem ID-ju namesto pozicije

**Namen:** Zamenjati pozicijsko (index) ujemanje z ujemanjem po wire ID-jih (`exercise_${id}`, `set_${id}`), ki že obstajajo v payloadu.

**Rešuje:** ENG-08/09 razširjeno na vsebino seje (ne le identiteto same seje) — audit finding "Snapshot reconciliation is positional despite wire IDs".

**Pristop:**
- V `_syncSessionStateToDrift` zgradi `Map<wireId, existingRow>` pred zanko namesto `existingExercises[i]`/`existingSets[j]` pozicijskega dostopa (linije 341, 400-402).
- Brisanje "odvečnih" vrstic izračunaj kot množično razliko (`existingIds - incomingIds`), ne kot "index nad dolžino payload-a" (trenutno linije 448-455).
- Novi seti/vaje brez znanega wireId (uro-generirani, npr. `watch_planned_${millis}`) se naravno obravnavajo kot vstavitve, ker jih mapa ne najde.
- Ohrani obstoječo "substitucijo vaje" (ista pozicija/slot, druga vaja) — a preveri, da jo shema po novem eksplicitno signalizira (stabilen slot ID ločen od "katera vaja je v slotu"), ne le pozicijsko sovpadanje.

**Datoteke:** `lib/features/workouts/data/wear_workout_sync_service.dart`, `lib/features/workouts/data/workouts_repository.dart` (morda nov `wireId` stolpec — lahko v isti migraciji kot Faza 1), `lib/data/local/database.dart`

**Koordinacija:** samo Dart — ura že pošilja wire ID-je, telefon jih le ne uporablja.

**Verifikacija:**
- Unit test: brisanje prve vaje v seznamu treh → preostali dve pravilno prepoznani (ne "zamenjava identitete").
- Unit test: vstavitev seta sredi seznama.
- Ročni scenarij: na uri izbriši drugo vajo sredi treninga z že vpisanimi seti na 1. in 3. vaji → po sinhronizaciji sta 1. in 3. vaja pravilno prepoznani.

---

## Faza 4 — Kotlin: kolizijsko varno shranjevanje, izolacija replay/flush, nezastoječa vrsta

**Namen:** Popraviti Kotlin ustreznice "en padec ustavi vse ostalo" — single-slot overwrite, zaporedna replay+flush sklopitev, in queue-blocking hrošč (hujši od Dart različice, ker preživi restart).

**Rešuje:** ENG-06/19 (Kotlin stran kaskadnega sesutja).

**Pristop:**
- **Kolizijsko varno shranjevanje (single-slot overwrite):** `PhoneWearListenerService.savePendingWorkout()` (linije 261-268) trenutno brez preverjanja prepiše en sam SharedPreferences ključ. S Fazo 1 (zanesljiv `entityId`+`revision`) dodaj preverjanje: če obstoječi pending payload še ni potrjen (`markWatchWorkoutApplied` ni bil klican) in ima drugačen `entityId`, gre za pravo kolizijo — glasno loguj in prednostno obdrži envelope z višjo (zdaj zaupanja vredno) revizijo namesto tihega "zadnji zmaga".
- **Izolacija replay/flush:** `onPeerConnected()` (`PhoneWearListenerService.kt:252-259`, `SyncService.kt:375-382`) ovij vsak od štirih zaporednih durable `putState()` klicev v `replayPersistentState()` (`MobileWearSyncManager.kt:128-137`, `WearDataLayerSyncManager.kt:74-78`) v ločen `runCatching`/`try-catch`, tako da padec enega polja (npr. macro targets) ne prepreči replaya ostalih. Ločeno ovij tudi `replayPersistentState()` in `flushPendingRealtimeMessages()` v `onPeerConnected` telesu vsakega v svoj try/catch.
- **Nezastoječa vrsta:** `flushPendingRealtimeMessages()` (`WearDataLayerSyncManager.kt:80-111`, `MobileWearSyncManager.kt:139-170`) — zamenjaj `if (!deliveredToAllNodes) break` s pristopom "best-effort vsak element, odstrani samo uspešne", tako da en trajno nedostavljiv element ne blokira elementov za njim. Dodaj varnostno omejitev (max starost/št. poskusov na sporočilo), da vrsta ne raste v neskončnost.

**Datoteke:** `android/app/src/main/kotlin/com/ams/herculex/PhoneWearListenerService.kt`, `android/app/src/main/kotlin/com/ams/herculex/sync/MobileWearSyncManager.kt`, `android/wear/src/main/java/com/ams/herculex/sync/SyncService.kt`, `android/wear/src/main/java/com/ams/herculex/sync/WearDataLayerSyncManager.kt`

**Koordinacija:** samo Kotlin, brez spremembe wire formata (kolizijska detekcija v Fazi 4 pa se logično naslanja na zanesljiv `entityId`/`revision` iz Faze 1).

**Verifikacija:**
- Kotlin unit testi (JUnit + fake `MessageClient`): vrsta treh sporočil, srednje pade → sporočili 1 in 3 se odstranita, 2 ostane za retry (trenutno bi se vsa tri zataknila).
- Unit test: eden od štirih `putState` klicev v `replayPersistentState` vrže izjemo → ostali trije se še vedno izvedejo.
- Ročni scenarij: zataknjeno/nedostavljivo sporočilo na čelu vrste + 2 legitimni sporočili za njim → po reconnectu legitimni prispeta.

---

## Faza 5 — Echo-guard robustnost (Dart) + Wear lifecycle/UX popravki (Kotlin) — neodvisno, nižje tveganje

**Namen:** Preostale napake, ki niso protokolsko odvisne in lahko gredo v poljubnem vrstnem redu glede druga na drugo.

**Rešuje:** ENG-14, ENG-15, ENG-16 (Wear lifecycle/UX), plus echo-guard race in manjkajoča nutrition sinhronizacija.

**Pristop:**
- **Echo-guard race (Dart):** `_isApplyingRemoteSession` (linija 23) se nastavi znotraj queued closure, a resetira v *zunanjem* `finally`, kar ni zanesljivo ob prekrivajočih klicih. Prenesi lastništvo zastavice na samo vrsto iz Faze 2 (`_enqueueRemoteApply`) — inkrementiraj/dekrementiraj znotraj verige, ne v klicateljevem `finally`.
- **Sticky foreground service (ENG-14):** `SyncService.kt` (`handleSessionEnd()` linije 347-364, `MESSAGE_FINISH_WORKOUT` linije 189-191) trenutno ustavita `WorkoutOngoingService` izključno preko `activeViewModel?.endSessionFromPhone()` — `null`-varno, a `null` kadar je ViewModel reciklirana. Dodaj neposreden `ACTION_STOP` klic na `WorkoutOngoingService`, ki ne potrebuje žive ViewModel instance (po vzoru `WorkoutViewModel.kt:419-422`).
- **Notification tap no-op (ENG-15):** Wear `MainActivity.kt` mora dejansko prebrati `open_active_workout` extra (po vzoru phone-side `MainActivity.kt:376-395`). Popravi `onNewIntent` da neposredno sproži navigacijo (npr. preko `MutableStateFlow`, ki ga Compose dejansko opazi — ne golega `intent` polja, ki se ne re-komponira), in razširi `LaunchedEffect(activeSession != null)` da se sproži tudi ob svežem tap-signalu, ne le ob false→true prehodu.
- **Durable put blokira fast send (ENG-16):** `WorkoutViewModel.kt` (`broadcastSessionToPhone` linije 315-334, `broadcastSessionEndToPhone`, `broadcastSessionDiscardToPhone`) — ovij durable `pushActiveWorkoutSession()` v `runCatching` **znotraj** `viewModelScope.launch` bloka, tako da padec durable puta ne prepreči poskusa `sendMessageToAllNodes()`.
- **Manjkajoča nutrition sinhronizacija:** `NutritionViewModel.kt` (`addCalories`, `addWater`, `logFood`, linije 93-106) trenutno spreminjajo samo lokalni `MacroStore`, brez klica `syncManager`. Dodaj enak vzorec kot `logQuickAdd`/`startFast`/`stopFast` — nova, dodajoča (ne-lomljiva) sporočilna pot + ustrezen phone-side handler v `nutrition_providers.dart`. Uporabi "mark-applied-after-success" vrstni red iz Faze 2 že od začetka.

**Datoteke:** `lib/features/workouts/data/wear_workout_sync_service.dart`, `android/wear/src/main/java/com/ams/herculex/sync/SyncService.kt`, `android/wear/src/main/java/com/ams/herculex/MainActivity.kt`, `android/wear/src/main/java/com/ams/herculex/workout/WorkoutViewModel.kt`, `android/wear/src/main/java/com/ams/herculex/nutrition/NutritionViewModel.kt`, `android/wear/src/main/java/com/ams/herculex/sync/WearDataLayerSyncManager.kt`, `lib/features/nutrition/presentation/nutrition_providers.dart`

**Koordinacija:** večinoma eno-stranska (Kotlin). Nova nutrition sporočila zahtevajo majhen usklajen (a ne-lomljiv, aditiven) dodatek na Dart strani.

**Verifikacija:**
- Ročno: začni trening na telefonu, ko Wear app ni v ospredju (torej `activeViewModel == null`), končaj na telefonu → preveri, da se obvestilo/servis na uri ugasneta.
- Ročno: aktivna seja na uri, uporabnik odnavigira stran, tapne obvestilo → preveri navigacijo nazaj na aktivni trening.
- Unit/ročno: simuliraj padec `pushActiveWorkoutSession` (letalski način) → preveri, da se `sendMessageToAllNodes` še vedno poskusi.
- Ročno: "+200 kcal" / "+500ml vode" / ročni vnos hrane na uri → preveri, da se pojavi na telefonu po sinhronizaciji.

---

## Povzetek

| Faza | Tema | ENG # | Koordinacija | Odvisnost |
|---|---|---|---|---|
| 0 | Testna osnova | — | samo testi | — |
| 1 | Protokol v2: session UUID + monotona revizija | ENG-08, ENG-09 | **usklajeno, lomljivo** | Faza 0 |
| 2 | Dart: dedupe-after-success + transakcije + vrsta | ENG-07, ENG-10, ENG-12, ENG-06 (Dart) | samo Dart | Faza 1 (priporočeno) |
| 3 | Dart: rekonciliacija po stabilnem ID-ju | (razširitev ENG-08/09) | samo Dart | Faza 1 (migracija) |
| 4 | Kotlin: kolizije, izolacija, vrsta | ENG-06, ENG-19 (Kotlin) | samo Kotlin | Faza 1 (za #11) |
| 5 | Lifecycle/UX + echo-guard + manjkajoča sinhronizacija | ENG-14, ENG-15, ENG-16 | večinoma eno-stranska | Faza 2 (echo-guard) |

**Izven obsega:** `lib/data/sync/sync_engine.dart` (že v delu, ločeno od tega načrta).
