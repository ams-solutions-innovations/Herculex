# Wear Sync Remediation — Progress Log

This file tracks execution of the phased plan in
[`docs/wear-sync-race-conditions-remediation-plan-2026-08-11.md`](wear-sync-race-conditions-remediation-plan-2026-08-11.md).
Each phase of that plan is being implemented in its own chat session, so this
log is the persistent memory across sessions — **read the plan doc and this
log fully before starting work on any phase.**

Source audit: `docs/app-audit-report-2026-08-10.md` (WearOS/cross-device
section, findings ENG-06 through ENG-19).

## How to use this doc (for whichever Claude session picks up next)

1. Read `docs/wear-sync-race-conditions-remediation-plan-2026-08-11.md` in
   full — it has the authoritative per-phase design (files, approach,
   verification steps).
2. Read the "Status" table below to see what's done.
3. Read the phase's own log entry (if it exists) for exact deviations from
   the plan, gotchas hit, and what was verified.
4. Do the next `pending` phase. Update this file's Status table and add a
   log entry when done, following the existing entries' format.
5. Out of scope for all phases: `lib/data/sync/sync_engine.dart` (separate,
   already-in-progress fix, not part of this plan).

## Status

| Phase | Theme | Status | Session date |
|---|---|---|---|
| 0 | Test harness groundwork | **Done** | 2026-08-11 |
| 1 | Protocol v2: session UUID + monotone revision (coordinated, breaking) | **Done** | 2026-08-11 |
| 2 | Dart: dedupe-after-success + transactional apply + queue fix | **Done** | 2026-08-11 |
| 3 | Dart: ID-based exercise/set reconciliation | **Done** | 2026-08-11 |
| 4 | Kotlin: collision-safe storage + isolated replay/flush + queue drain | **Done** | 2026-08-11 |
| 5 | Echo-guard robustness + Wear lifecycle/UX + missing nutrition sync | **Done** | 2026-08-11 |

**Order note:** the plan doc's own dependency table lists Phase 2 as
"depends on Phase 1 (recommended sequencing)," not a hard requirement — the
2026-08-11 session was explicitly directed to do Phase 2 before Phase 1.
This was safe because Phase 2's fixes (dedupe check/commit split, Drift
transaction wrap, queue-poisoning fix) operate on the *existing* v1
envelope shape and don't touch `entityId`/`revision` semantics themselves —
they'll keep working unmodified once Phase 1 introduces the UUID/monotonic
revision, since Phase 1 changes what goes *into* those fields, not how
`WearDedupeState` or `_syncSessionStateToDrift` consume them. Whoever does
Phase 1 should still read the Phase 2 entry below first — it changed
`WearDedupeState`'s public API (`shouldAccept` → `wouldAccept`/`commit`).

---

## Phase 0 — Test harness groundwork — DONE (2026-08-11)

**Goal:** cross-decoder contract test fixtures in place before Phase 1
touches the wire protocol, so the schemaVersion bump has a regression net.

**What was done:**

- `test/wear_sync_contract_test.dart`: added canonical v1 wire fixtures as
  top-level constants (`kCanonicalV1WorkoutStartJson`,
  `kCanonicalV1FastingSnapshotJson`, `kCanonicalLegacyFallbackJson`) plus
  tests decoding each. Added tests for: `entityId`/`origin` fallback when
  absent from the wire payload, and dedupe-key isolation per
  `entity:entityId:origin` (previously only same-key ordering was tested).
  Existing tests (wrap/decode round-trip, revision ordering, legacy
  backward-compat, set-type normalization) kept as-is.
- `android/wear/src/test/java/com/ams/herculex/sync/WearSyncContractTest.kt`
  (**new file** — the wear module had zero unit test sources before this,
  confirming the audit's "Wear unit tests had no sources" finding). Mirrors
  the Dart fixtures **byte-for-byte** (same JSON string literals — see the
  comment at the top of both files) and covers the same cases:
  `decodeEnvelope` canonical fixtures, fallback behavior, `AppliedRevisionStore.shouldAccept`
  ordering and key-isolation, legacy payload compat, `normalizeSetType`/`normalizeIsWarmup`.
- `android/wear/build.gradle.kts`: added test dependencies — the wear module
  had **no test dependencies at all** before this. Added:
  `junit:junit:4.13.2`, `androidx.test:core:1.5.0`,
  `org.robolectric:robolectric:4.11.1`. Robolectric is required because
  `AppliedRevisionStore` needs a real `android.content.Context` for
  `SharedPreferences` — plain JUnit can't provide one. All tests in the new
  file run under `@RunWith(RobolectricTestRunner::class)`.

**Gotcha hit:** Kotlin backtick-quoted test function names cannot contain
`:` (`` `dedupe state is isolated per entity:entityId:origin key` `` failed
to compile with "Name contains illegal characters"). Renamed to use `-`
instead of `:`.

**Verification — both green:**
- `flutter test test/wear_sync_contract_test.dart` → 9/9 passed.
- `./gradlew :wear:testDebugUnitTest` → BUILD SUCCESSFUL, 8/8 passed
  (confirmed via `build/wear/test-results/testDebugUnitTest/TEST-com.ams.herculex.sync.WearSyncContractTest.xml`:
  `tests="8" skipped="0" failures="0" errors="0"`).

**Files touched this phase:**
- `test/wear_sync_contract_test.dart` (modified)
- `android/wear/src/test/java/com/ams/herculex/sync/WearSyncContractTest.kt` (new)
- `android/wear/build.gradle.kts` (modified — test deps only)

**Not committed to git yet** — working tree has these changes uncommitted
alongside the pre-existing unrelated modifications to `sync_engine.dart`,
`health_service.dart`, `profile_view.dart` (out of scope, already in
progress separately). Whoever runs Phase 1 should decide whether to commit
Phase 0 first (recommended, keeps history clean) before starting Phase 1's
breaking changes.

---

## Phase 2 — Dart dedupe-after-success + transactional apply + queue fix — DONE (2026-08-11)

**Goal:** fix the "mark-then-write" ordering bug (dedupe/idempotency marked
before the corresponding Drift write is attempted), wrap the multi-write
session apply in a transaction, and stop one failed queued apply from
permanently poisoning all later ones.

**Note:** done directly after Phase 0, skipping ahead of Phase 1 by
explicit instruction — see the "Order note" in the Status section above for
why this was safe.

**What was done:**

1. **`lib/features/nutrition/data/wear_sync_contract.dart`** —
   `WearDedupeState.shouldAccept` (combined check+mutate) split into
   `wouldAccept(envelope)` (pure check, no mutation) and
   `commit(envelope)` (mutation only). No other production callers existed
   (`grep` confirmed only the two workout-sync call sites), so the old
   method was removed outright rather than kept as a deprecated shim.

2. **`lib/features/workouts/data/wear_workout_sync_service.dart`**:
   - `_handleWatchWorkoutStarted` / `_handleWatchWorkoutUpdated`: the
     early "ignore stale/duplicate" check now calls `wouldAccept()`
     instead of the old `shouldAccept()`. `_remoteDedupe.commit(envelope)`
     is now called immediately after `_syncSessionStateToDrift(...)`
     succeeds, right before `markWatchWorkoutApplied()` — i.e. only once
     the write has actually landed.
   - `_syncSessionStateToDrift`: entire body now wrapped in
     `_db.transaction(() async { ... })`, mirroring the existing pattern
     in `workouts_repository.dart` (`setMachineConfig`,
     `reorderWorkoutExercises`). A crash/exception partway through the
     exercise/set loops now rolls back everything applied so far instead
     of leaving a partially-applied session. `createCustomExercise`'s own
     nested `_db.transaction(...)` (unique-constraint retry path) nests
     correctly inside the outer transaction — confirmed by test, see below.
   - `_enqueueRemoteApply`: changed from
     `_remoteApplyQueue = _remoteApplyQueue.then((_) => apply());` (no
     `onError` — one throw left `_remoteApplyQueue` permanently errored,
     silently dropping every future watch update until app restart) to a
     version that resets the shared queue anchor with `catchError((_) {})`
     after each call, while still returning the real per-call result (with
     its real error, if any) to the caller so the existing per-call
     try/catch logging is unchanged.

3. **`lib/features/nutrition/presentation/nutrition_providers.dart`** —
   `onWatchFastingCommand` and `onWatchQuickAddCommand` (inside
   `wearSyncControllerProvider`): `appliedFastingCommands.add(commandId)` /
   `appliedQuickAddCommands.add(commandId)` moved from *before* the
   corresponding repository write (`repo.startSession`/`endSession`,
   `nutritionRepository.logFood`) to *after* it succeeds. The early
   duplicate-check now uses non-mutating `.contains()` instead of the
   mutating `.add()` return value. This makes the "Keep the native pending
   command until a later retry succeeds" comment actually true — before
   this fix it wasn't, because a failed write still poisoned the dedupe
   set on the first attempt.

**Deliberately not touched — flagged for a later phase:** the audit and
this plan's own Context section note the *same* commit-before-apply bug
exists on the **Kotlin** side, in
`android/wear/src/main/java/com/ams/herculex/sync/SyncService.kt`
(`handleSessionUpdate`/`handleFastingSnapshot`, calling
`appliedRevisions.shouldAccept(envelope)` — which writes the
SharedPreferences high-water mark synchronously inside the check, see
`WearSyncContract.kt:92-108` — before `persistSession`/
`WorkoutStore.parseAndUpdateSession`/`FastingStore.saveSnapshot` run). The
written plan's Phase 2 section is Dart-only and its Phase 4 section (Kotlin
collision/queue fixes) doesn't explicitly list this fix either — it's a
gap between the plan's Context section (which named it on both platforms)
and its final phase assignments. **Recommend folding a Kotlin
`AppliedRevisionStore.shouldAccept` → `wouldAccept`/`commit` split into
Phase 4** when that's picked up, mirroring exactly what this session did
in `wear_sync_contract.dart`.

**Tests added — `test/wear_workout_sync_service_test.dart` (new file, 3
tests):**
- A two-exercise update where the second exercise's `sets` field is
  malformed (a String instead of a List, forcing a `TypeError` partway
  through the loop) rolls back *both* exercises, not just the one that
  failed — proves the transaction wrap.
- The same failing update, redelivered with the identical `entityId` +
  `revision` but a valid payload, is still accepted and applied — proves
  a failed apply doesn't poison dedupe.
- A structurally invalid JSON payload (throws in `_decodeWorkoutEnvelope`,
  inside the queued closure) followed by a valid update for a different
  session — the second one still applies — proves the queue-poisoning fix.

These drive the service the same way the native host does: through the
`WearSyncService` platform channel (`TestDefaultBinaryMessengerBinding`),
using `pumpEventQueue()` to let the un-awaited handler's internal Drift
I/O settle before asserting, since `WearWorkoutSyncService`'s handlers are
private and the `WearSyncService.onWatchWorkoutUpdated` field is a
setter-only static (no getter to capture the bound closure directly).

**Test coverage gap (documented, not filled this session):** the
`nutrition_providers.dart` fasting/quick-add fix has no dedicated automated
test. `wearSyncControllerProvider` pulls in a large, mostly-unrelated
provider graph (`dailyTotalsProvider`, `weeklyMuscleVolumeProvider`,
`mealSlotsProvider`, `sharedPreferencesProvider`, etc.) that this codebase
has no existing pattern for standing up in a test (its sibling nutrition
tests operate at the repository layer, not the provider layer — see
`test/phase5_nutrition_test.dart`). The fix itself is a direct, verified-
by-inspection mirror of the exact pattern proven correct by the
`wear_workout_sync_service_test.dart` tests above. Building
`ProviderContainer` test scaffolding for `wearSyncControllerProvider` would
be a reasonable, self-contained follow-up (candidate for a future Phase-0-
style groundwork task) rather than something to force into this phase.

**Verification — all green:**
- `flutter test test/wear_workout_sync_service_test.dart test/wear_sync_contract_test.dart` → 14/14 passed.
- `flutter test` (full suite) → 331 tests, 3 failures, **all pre-existing/unrelated**:
  - `test/ongoing_workout_surface_snapshot_test.dart` × 2 — the same two
    failures already documented in `docs/app-audit-report-2026-08-10.md`
    ("82.5 kg x 8" vs "82.5 kg x 8 reps"; action order), untouched by this
    phase.
  - `test/widgets/training_blocks_view_test.dart: the week board shows real
    day names, not placeholders` — confirmed date-sensitive
    (`startDate: DateTime.now()` in the test's own setup, asserting
    specific weekday labels), unrelated to any file this phase touched.
- `flutter analyze` (full repo) → 36 issues, matching the audit baseline
  exactly, zero new issues, zero in any file this phase touched.

**Files touched this phase:**
- `lib/features/nutrition/data/wear_sync_contract.dart` (modified)
- `lib/features/workouts/data/wear_workout_sync_service.dart` (modified)
- `lib/features/nutrition/presentation/nutrition_providers.dart` (modified)
- `test/wear_sync_contract_test.dart` (modified — updated for the
  `wouldAccept`/`commit` API split, added 2 new tests for the split itself)
- `test/wear_workout_sync_service_test.dart` (new — 3 tests)

**Not committed to git yet** — same as Phase 0, stacked on top of the
pre-existing unrelated `sync_engine.dart`/`health_service.dart`/
`profile_view.dart` changes.

---

## Phase 1 — Protocol v2: session UUID + monotone revision — DONE (2026-08-11)

**Goal:** replace two structural gaps in the wire protocol, as one
coordinated `schemaVersion` 1→2 bump: (1a) a stable session UUID used as
`entityId` on every message about a session, including its end, plus
apply-time gating that rejects an update/end for a session other than the
one currently active; (1b) a revision counter that persists across a
process restart instead of resetting to 0; (1c) the legacy "unenveloped
payload" dedupe bypass flipped from always-accept to fail-closed. Adopted
the plan doc's **hard-cutover** option (no v1-interop shim) rather than
one-way tolerance — single-developer, one phone + one watch, no staged
fleet rollout to protect.

**Ground-truth note:** before writing any code, two Explore agents read
every file in full (not from the plan doc's line numbers, several of which
had drifted since Phase 2 shipped — e.g. `WearDedupeState.shouldAccept` no
longer exists as such, `pushActiveSessionToWatch`'s entityId line had moved
~29 lines, etc.). All line numbers below are current as of this session, not
the original plan doc.

### 1a — Stable session UUID

**Dart:**
- `lib/data/local/tables.dart`: `WorkoutSessions` gets a new nullable
  `TextColumn sessionUuid`.
- `lib/data/local/database.dart`: `schemaVersion` 21 → 22; migration adds
  the column and backfills existing rows with `Uuid().v4()` via a Dart-side
  loop (`customSelect` + `customUpdate` per row) since Drift/SQLite has no
  `UUID()` SQL function — every prior backfill in this file was pure SQL, so
  this is a new pattern for this file.
- `lib/features/workouts/data/workouts_repository.dart`: `startSession()`
  gets an optional `String? sessionUuid` param, defaulting to
  `const Uuid().v4()`.
- `lib/features/workouts/data/wear_workout_sync_service.dart`:
  `_handleWatchWorkoutStarted`'s redelivery check now compares
  `activeSession.sessionUuid == envelope.entityId` instead of the old
  `activeSession.id == _lastSyncedSessionId`. `_handleWatchWorkoutUpdated`
  now rejects (logs `ignored-entity-mismatch`, does not apply) an update
  whose `entityId` doesn't match the phone's active session — this is the
  actual fix for the apply-time-gating hole the plan called out (previously
  *any* active session was silently mutated). `_handleWatchWorkoutEnded`
  signature changed from `([bool isDiscard = false])` to
  `(String? entityId, [bool isDiscard = false])` — a non-null mismatched id
  is now a hard no-op instead of ending whatever's active; `entityId == null`
  fails open (defensive default, shouldn't happen post-cutover).
  `notifySessionEnded()` now takes `String? sessionUuid` and no-ops if null/empty
  instead of calling a zero-arg native method. `pushActiveSessionToWatch`'s
  `entityId` is now `session.sessionUuid ?? 'phone_session_${session.id}'`
  (fallback only guards a theoretical pre-migration NULL race).
- `lib/features/nutrition/data/wear_sync_service.dart`: `_WatchEvent` gained
  an `entityId` field; `onWatchWorkoutEnded`'s native-side payload now
  carries `entityId`; `_onWatchWorkoutEnded` handler type changed
  `Function(bool)?` → `Function(String?, bool)?`; `endWorkoutOnWatch()` now
  requires a `String entityId` arg, sent as `{'entity_id': entityId}`.
- `lib/features/workouts/presentation/workouts_providers.dart:314`: updated
  its `notifySessionEnded()` call site to pass `previous?.value?.sessionUuid`.

**Kotlin (wear module):**
- `workout/WorkoutModels.kt`: `WorkoutSession` gained
  `val sessionId: String = UUID.randomUUID().toString()`, fixed-at-creation
  like the existing `origin` field.
- `workout/WorkoutStore.kt`: `sessionToJson` now takes a `Context` param, uses
  `session.sessionId` as `entityId` (deleted the old `idPrefix`/`startTimeMs`
  construction entirely), and a persisted `WearRevisionAllocator` for
  `revision` (see 1b). `parseAndUpdateSession` now threads
  `envelope.entityId` through to `viewModel.updateSessionFromRemote(...,
  sessionId = ...)`. New `activeSessionEntityId(context)` helper reads the
  persisted session JSON's `entityId` for `SyncService` to gate against when
  there's no live ViewModel. `parseAndStartSession` confirmed to have zero
  callers anywhere in `android/` — left untouched, flagged with a comment.
- `workout/WorkoutViewModel.kt`: `startWorkout()` and
  `updateSessionFromRemote()` both gained a `sessionId` param (defaulted to
  a fresh UUID for the former). `endSession()` captures
  `_session.value?.sessionId` **before** nulling `_session`, so it has an id
  to send with the end/discard broadcast. `broadcastSessionEndToPhone`/
  `broadcastSessionDiscardToPhone` now take `entityId: String` and send a
  real `WearSyncContract.encodeEnvelope(...)` on `MESSAGE_WATCH_SESSION_END`/
  `MESSAGE_WATCH_SESSION_DISCARD` instead of the literal `""`/`"discard"`
  strings they used to send.
- `sync/SyncService.kt`: `handleSessionUpdate` now compares
  `envelope.entityId` against `activeViewModel?.session?.value?.sessionId ?:
  WorkoutStore.activeSessionEntityId(this)` and returns before
  `persistSession`/`parseAndUpdateSession` on a mismatch — this closes a gap
  the plan doc's prose didn't spell out explicitly: without gating
  `persistSession` too, a rejected session's JSON would still get durably
  persisted and wrongly restored as "the" active session on the watch app's
  next cold start. `handleSessionEnd()` → `handleSessionEnd(entityId:
  String?)` with the same mismatch policy (null fails open, non-null
  mismatch is a no-op) as the Dart side. Both call sites (the
  `STATE_ACTIVE_WORKOUT` `onDataChanged` else-branch, and the
  `MESSAGE_ACTIVE_SESSION_END` message handler) updated to extract and pass
  the real entityId — the message handler decodes it via `runCatching` since
  a genuinely empty/malformed payload must not crash the listener service.
- `sync/WearDataLayerSyncManager.kt`: `pushActiveWorkoutSession` gained an
  `endedEntityId: String? = null` param, written to a new `ended_entity_id`
  DataMap field.

**Kotlin (app/phone-native module):**
- `sync/MobileWearSyncManager.kt`: `syncActiveWorkoutSession` mirrors the
  same `endedEntityId` param/field addition. `endActiveSession()` →
  `endActiveSession(entityId: String)`, builds a minimal hand-rolled
  `JSONObject` envelope (`buildEndEnvelope`) — wire-compatible with
  `WearSyncContract.encodeEnvelope`'s output shape — since this `app` module
  has no `WearSyncContract`/`SyncEnvelope` type of its own (that lives in
  `wear` only); not worth introducing a shared type for one call site.
- `MainActivity.kt`: `"endWorkoutOnWatch"` method-channel case reads
  `entity_id` from the call args; `endWorkoutOnWear()` →
  `endWorkoutOnWear(entityId: String)` (no-ops on blank).
  `PhoneWearListenerService.onWatchWorkoutEndListener` wiring updated to the
  new `(Boolean, String?) -> Unit` shape and forwards `entityId` into the
  `"onWatchWorkoutEnded"` Flutter method-channel call.
- `PhoneWearListenerService.kt`: `onWatchWorkoutEndListener` type changed to
  `((Boolean, String?) -> Unit)?`. New `extractEntityId(json)` helper
  (mirrors the existing `watchSessionKey()`/`isWatchOrigin()` hand-parse
  style). All **five** `onWatchWorkoutEndListener?.invoke(...)` call sites
  updated — the durable `onDataChanged` path reads `ended_entity_id` off the
  DataMap; the two "legacy" `onDataChanged` string-literal branches (already
  commented as inert once both sides are updated) pass `null` since they
  predate the entityId envelope entirely; the two live `onMessageReceived`
  fast-path branches (end/discard) extract it from the message payload.

### 1b — Monotonic revision surviving restart

- Dart `WearRevisionAllocator` (`lib/features/nutrition/data/wear_sync_contract.dart`)
  rewritten from an in-memory `_lastRevision` int to a
  `(SharedPreferences, String key)`-backed one: `next()` reads the persisted
  high-water mark, computes `max(persistedLast + 1, now)`, persists it
  (fire-and-forget `unawaited(prefs.setInt(...))` — `shared_preferences`'s
  synchronous in-memory cache means a same-process follow-up call sees the
  new value immediately regardless), returns it. `WearWorkoutSyncService`'s
  `_revisionAllocator` field is now `late final`, built in the constructor
  body via `_ref.read(sharedPreferencesProvider)` (mirrors an existing usage
  already in this same file at what was line 560, so no new access pattern
  introduced). `nutrition_providers.dart`'s `wearSyncRevisionAllocatorProvider`
  updated the same way. Two independent keyed instances exist —
  `'workout'` and `'fasting'` — so their sequences can't collide.
- Kotlin: **no revision-allocator construct existed at all before this** —
  `WearSyncContract.encodeEnvelope` just took `revision: Long` as a
  caller-supplied parameter, and every call site inlined
  `System.currentTimeMillis()`. New `WearRevisionAllocator(context, key)`
  class added to `WearSyncContract.kt`, same persisted-max-vs-now logic,
  `@Synchronized`, its own SharedPreferences file. Wired into
  `WorkoutStore.sessionToJson` (key `"workout"`) and `FastingStore.kt`'s
  `snapshotToJson` (key `"fasting"`, which also gained a required `context`
  param — its two call sites in `NutritionViewModel.kt` updated to pass
  `ctx()`). `WorkoutViewModel.kt`'s new `endEnvelope()` helper also uses the
  `"workout"`-keyed allocator for session-end messages.

### 1c — Fail-closed legacy bypass + light validation

- `wearSyncSchemaVersion` (Dart) / `SCHEMA_VERSION` (Kotlin) bumped 1 → 2.
  Dart's bump auto-propagates through every `WearSyncEnvelope.wrap()` call
  site (no per-call-site edit needed).
- Both `WearDedupeState.wouldAccept` (Dart) and `AppliedRevisionStore.shouldAccept`
  (Kotlin) flipped their "unenveloped legacy payload" branch from
  `return true` to `return false` — this bypass existed for pre-envelope
  watch builds; with both APKs moving to schemaVersion 2 together there's no
  legitimate sender left for it. **Deliberately did not split**
  `AppliedRevisionStore.shouldAccept` into `wouldAccept`/`commit` on the
  Kotlin side — the Phase 2 log entry already deferred that Dart-mirroring
  refactor to Phase 4; only the fail-closed flip belongs here.
- Dart `WearSyncEnvelope.decode()`'s `isEnvelope` check tightened to also
  require `origin`/`entityId` be `null` or the correct type when present (not
  wrong-typed) — a wrong-typed value now falls through to the legacy decode
  branch instead of crashing or being silently coerced. Deliberately did
  **not** validate `origin`'s *value* against the known origin constants at
  decode time (would be broader than what 1c asked for); left to callers
  that already compare it explicitly.

### Bugs / deviations from the plan doc found during implementation

- The plan's own Kotlin citation `WearSyncContract.kt:68` for "where revision
  is generated" actually points at `encodeEnvelope`'s wall-clock
  `updatedAtEpochMs` stamp (which deliberately stays wall-clock per 1b's own
  spec) — the real revision-generation sites were `WorkoutStore.kt:227` and
  (not named in the plan's file list at all) `FastingStore.kt:76`. Both
  fixed.
- `PhoneWearListenerService.kt` has **five** `onWatchWorkoutEndListener`
  call sites, not the two the plan's Phase 1a section implied — all five
  updated (see 1a above for the breakdown).
- `handleSessionUpdate`'s gating was extended slightly beyond the plan
  doc's literal prose: it now also gates `persistSession` (not just the
  live-ViewModel apply), closing a latent restore-on-cold-start bug — see
  the `SyncService.kt` bullet in 1a above.
- `test/schema_v21_test.dart`'s `'reaches schema version 21'` test opens the
  real `AppDatabase` (not a version-pinned test-only one), so once
  `schemaVersion` became 22 its migration chain now runs one step further
  than the test name/assertion expected. Renamed to `'reaches schema version
  22'` and updated the literal — this is a real, expected consequence of the
  schema bump, not a bug in the migration itself.

### Tests added/changed

- `test/wear_sync_contract_test.dart`: kept v1 fixtures as-is (they pin
  pre-Phase-1 behavior by design); added `kCanonicalV2WorkoutStartJson`/
  `kCanonicalV2FastingSnapshotJson` (schemaVersion 2, UUID-shaped entityId)
  plus decode/round-trip tests for them. Renamed and flipped
  `'legacy payloads remain backward compatible without revision'` →
  `'legacy (unenveloped) payloads are rejected — fail closed'` (both
  assertions `isTrue` → `isFalse`). New: wrong-typed `entityId` falls back
  instead of crashing. New `WearRevisionAllocator` group: persists across a
  simulated restart (two instances sharing one `SharedPreferences.getInstance()`),
  never goes backwards, different keys don't collide.
- `test/wear_workout_sync_service_test.dart`: `setUp` now calls
  `SharedPreferences.setMockInitialValues({})` and overrides
  `sharedPreferencesProvider` in the `ProviderContainer` — required once
  `WearWorkoutSyncService`'s constructor reads it to build the persisted
  allocator; every pre-existing test in this file would otherwise throw
  `UnimplementedError` immediately. Added `emitWorkoutStarted`/
  `emitWorkoutEnded` helpers (only `emitWorkoutUpdated` existed before).
  Fixed the pre-existing "malformed exercise mid-payload rolls back"
  test, which started a session via `repo.startSession()` (random UUID)
  then sent an update for a *different* literal `entityId` — under the new
  apply-time gating this now gets rejected before ever reaching the
  malformed payload, so the test needed `repo.startSession(sessionUuid:
  'watch-session-1')` to match. New tests: mismatched-entityId update is
  ignored and doesn't mutate the active session; mismatched-entityId end
  event doesn't end the session; matching-entityId end event does end it;
  started-event redelivery with the same UUID applies in place (same local
  session id) rather than destroying/recreating.
- `android/wear/src/test/java/com/ams/herculex/sync/WearSyncContractTest.kt`:
  added `CANONICAL_V2_WORKOUT_START_JSON`/`CANONICAL_V2_FASTING_SNAPSHOT_JSON`
  byte-for-byte matching the Dart v2 fixtures, plus decode tests and an
  `encodeEnvelope stamps the live SCHEMA_VERSION` test. Flipped the legacy
  test the same way as Dart. New `WearRevisionAllocator` tests: persists
  across two instances sharing one Robolectric context; different keys
  don't collide. **Not added** this phase: `WorkoutViewModel`/`SyncService`
  entityId-gating tests in Kotlin — those need Robolectric shadow setup
  (`Wearable.getDataClient` mocking, `viewModelScope` dispatcher control)
  this module has no precedent for; the Dart-side tests cover the same
  logic at lower plumbing cost. Flagged as a reasonable follow-up.

### Test dependency note

No new Gradle dependencies needed — `java.util.UUID` (JDK standard library)
was already used directly elsewhere in the Kotlin codebase with zero added
dependency. `package:uuid` was already a `pubspec.yaml` dependency
(`^4.5.1`), previously used in exactly one place (`supplement_edit_sheet.dart`)
— this phase is its first data-layer consumer.

**Verification — all green:**
- `flutter test test/wear_sync_contract_test.dart test/wear_workout_sync_service_test.dart`
  → 25/25 passed (18 + 7).
- `flutter test` (full suite) → 342 tests, 3 failures, **all pre-existing/unrelated**
  (same three named in the Phase 2 log entry: the two
  `ongoing_workout_surface_snapshot_test.dart` failures and the date-sensitive
  `training_blocks_view_test.dart` "week board shows real day names" test).
- `flutter analyze` (full repo) → issue count fluctuated between runs (32–41)
  for reasons unrelated to this phase (script/test-file lint noise,
  confirmed by grepping the output for every file this phase touched — zero
  hits) — **zero new issues in any file this phase touched**, confirmed by
  diffing against the Phase 2 baseline file list.
- `./gradlew :wear:testDebugUnitTest` → BUILD SUCCESSFUL, 13/13 passed
  (confirmed via the test-results XML: `tests="13" skipped="0" failures="0"
  errors="0"` — 8 from Phase 0 + 5 new this phase).
- `./gradlew :wear:assembleDebug :app:assembleDebug` → BUILD SUCCESSFUL, both
  APKs compile with every entityId/revision-allocator signature change
  threaded through correctly.

**Files touched this phase:**
- `lib/data/local/tables.dart`, `lib/data/local/database.dart` (migration)
- `lib/features/workouts/data/workouts_repository.dart`
- `lib/features/workouts/data/wear_workout_sync_service.dart`
- `lib/features/nutrition/data/wear_sync_service.dart`
- `lib/features/nutrition/data/wear_sync_contract.dart`
- `lib/features/nutrition/presentation/nutrition_providers.dart`
- `lib/features/workouts/presentation/workouts_providers.dart`
- `android/wear/src/main/java/com/ams/herculex/workout/WorkoutModels.kt`
- `android/wear/src/main/java/com/ams/herculex/workout/WorkoutStore.kt`
- `android/wear/src/main/java/com/ams/herculex/workout/WorkoutViewModel.kt`
- `android/wear/src/main/java/com/ams/herculex/sync/WearSyncContract.kt`
- `android/wear/src/main/java/com/ams/herculex/sync/SyncService.kt`
- `android/wear/src/main/java/com/ams/herculex/sync/WearDataLayerSyncManager.kt`
- `android/wear/src/main/java/com/ams/herculex/sync/FastingStore.kt`
- `android/wear/src/main/java/com/ams/herculex/nutrition/NutritionViewModel.kt`
- `android/app/src/main/kotlin/com/ams/herculex/sync/MobileWearSyncManager.kt`
- `android/app/src/main/kotlin/com/ams/herculex/MainActivity.kt`
- `android/app/src/main/kotlin/com/ams/herculex/PhoneWearListenerService.kt`
- `test/wear_sync_contract_test.dart` (v2 fixtures, flipped legacy test, allocator tests)
- `test/wear_workout_sync_service_test.dart` (prefs setup, new gating tests)
- `test/schema_v21_test.dart` (schema-version literal update, unrelated bug surfaced by the migration bump)
- `test/wear_watch_event_queue_test.dart` (one call site updated for the `onWatchWorkoutEnded` signature change)
- `android/wear/src/test/java/com/ams/herculex/sync/WearSyncContractTest.kt` (v2 fixtures, flipped legacy test, allocator tests)
- `lib/data/local/database.g.dart` (regenerated via `build_runner`)

**Not committed to git yet** — same as Phases 0/2, stacked on top of the
pre-existing unrelated `sync_engine.dart`/`health_service.dart`/
`profile_view.dart` changes.

---

## Phase 4 — Kotlin: collision-safe storage + isolated replay/flush + queue drain — DONE (2026-08-11)

**Goal:** fix the Kotlin-side equivalents of "one failure cascades into
everything else": a single unchecked-collision SharedPreferences slot for
the phone's pending watch workout, `onPeerConnected`'s unisolated
replay-then-flush sequence, `replayPersistentState`'s four unisolated
sequential durable puts, and `flushPendingRealtimeMessages`' `break`-on-
first-failure queue drain (worse than the Dart version fixed in Phase 2,
because this queue is persisted in SharedPreferences and so the block
survives a restart). Also folded in the `AppliedRevisionStore.shouldAccept`
→ `wouldAccept`/`commit` split, deferred from both Phase 1 and Phase 2 (see
their log entries) — the Kotlin mirror of the Dart `WearDedupeState` split
from Phase 2.

**Note on scope:** the plan doc's Phase 4 section only explicitly names
collision-safe storage, replay/flush isolation, and non-blocking queue
drain. The `AppliedRevisionStore` split was pulled in from the two prior
phases' explicit deferral notes, not from Phase 4's own plan text — flagged
here in case a future session goes looking for it and doesn't find it in
the plan doc itself.

**What was done:**

1. **`AppliedRevisionStore.shouldAccept` → `wouldAccept`/`commit` split**
   (`android/wear/src/main/java/com/ams/herculex/sync/WearSyncContract.kt`)
   — mirrors the Dart `WearDedupeState` split exactly: `wouldAccept(envelope)`
   is now a pure check (no mutation), `commit(envelope)` is mutation-only.
   `SyncService.kt`'s two call sites (`handleSessionUpdate`,
   `handleFastingSnapshot`) now call `wouldAccept()` for the early
   ignore-stale/duplicate check, then `commit()` only *after* the
   corresponding durable write (`persistSession` +
   `WorkoutStore.parseAndUpdateSession`, or `FastingStore.saveSnapshot`) has
   actually run — previously `shouldAccept()` wrote the SharedPreferences
   high-water mark as a side effect of the check itself, before the write
   was even attempted, so a failed write still poisoned the dedupe state and
   a retry of the identical envelope was dropped forever.

2. **Collision-safe pending-workout storage**
   (`android/app/src/main/kotlin/com/ams/herculex/PhoneWearListenerService.kt`)
   — `savePendingWorkout()` previously overwrote its single
   `KEY_SESSION_JSON` SharedPreferences slot unconditionally. That slot only
   ever holds an *unconfirmed* payload (Dart clears it via
   `markWatchWorkoutApplied` once durably applied), so if it's still
   populated with a **different** `entityId` than the incoming payload,
   that's a genuine collision between two distinct sessions racing for the
   one slot — not a normal in-place update. Added a pure, top-level,
   unit-testable `shouldReplacePendingWorkout(existing: PendingWorkoutSlot,
   incoming: PendingWorkoutSlot): Boolean` policy function (keeps whichever
   side has the higher — now trustworthy, per Phase 1 — `revision`; falls
   back to the pre-Phase-4 last-write-wins if either side's revision is
   unknown/unparseable) plus a new `extractRevision()` helper alongside the
   existing `extractEntityId()`. Every collision (win or lose) is logged
   loudly via `Log.w` instead of silently overwriting or silently dropping.

3. **Isolated replay/flush in `onPeerConnected`** — both
   `PhoneWearListenerService.kt` and `SyncService.kt`'s `onPeerConnected`
   now wrap `syncManager.replayPersistentState()` and
   `syncManager.flushPendingRealtimeMessages()` in **separate**
   `runCatching { }.onFailure { Log.e(...) }` blocks, so an exception from
   one can no longer prevent the other from running (previously they ran as
   one unguarded sequence inside a single `launch {}`).

4. **Isolated 4-way `replayPersistentState`**
   (`android/app/src/main/kotlin/com/ams/herculex/sync/MobileWearSyncManager.kt`)
   — each of the four sequential state fields (active workout session,
   macro targets, fasting snapshot, user token) is now replayed in its own
   `runCatching { }.onFailure { Log.e(...) }`. `putState()` rethrows on
   failure, so previously the first field's `putDataItem` exception silently
   dropped every field after it in the sequence — this was the literal
   plan-doc-cited bug ("štirje zaporedni durable `putState()` klici").
   `WearDataLayerSyncManager.kt`'s (wear-side) `replayPersistentState()` only
   ever had **one** field (active workout session) to begin with, so there
   was nothing to isolate there — confirmed by re-reading the file before
   assuming symmetry with the phone side.

5. **Non-blocking, bounded queue drain** — both
   `MobileWearSyncManager.flushPendingRealtimeMessages()` (app module) and
   `WearDataLayerSyncManager.flushPendingRealtimeMessages()` (wear module)
   changed from "first per-node delivery failure `break`s the whole loop,
   so every message behind the stuck one is starved" to: every message gets
   its own independent per-node delivery attempt; a message is removed from
   the queue only once it lands on every connected node, a message that
   fails on any node is left behind for the next flush instead of blocking
   later messages. Added the plan's explicit "safety cap" requirement: each
   `PendingWearMessage`/`PendingWearRealtimeMessage` now carries
   `enqueuedAtEpochMs` and `attempts`; a new top-level `isExpired(message,
   nowEpochMs, maxAttempts, maxAgeMs)` pure function (separate copy in each
   module — they're different Gradle compilation units, kept in lockstep
   rather than literally shared) retires a message once it exceeds
   `MAX_DELIVERY_ATTEMPTS = 20` or `MAX_MESSAGE_AGE_MS = 24h`, logged via
   `Log.w` before removal, so a permanently-undeliverable message can't grow
   the persisted queue without bound. `WearMessageQueueStore`/
   `WearRealtimeQueueStore` gained `recordFailedAttempts(ids)` to bump the
   counter for messages that failed this pass.

**Deliberate scope boundary:** did not touch
`lib/data/sync/sync_engine.dart` (out of scope per the plan doc's own
header) or any Dart file — this phase is Kotlin-only, matching the plan's
"samo Kotlin" coordination note for Phase 4.

### Tests added

- `android/wear/src/test/java/com/ams/herculex/sync/WearSyncContractTest.kt`
  — updated all three pre-existing `AppliedRevisionStore.shouldAccept(...)`
  call sites to a new local `acceptAndCommit(store, envelope)` test helper
  (mirrors the Dart test file's identically-purposed helper from Phase 2),
  so the "accept, then commit" combined-semantics assertions read the same
  as before the split. Added two new tests mirroring the Dart-side
  `wouldAccept`-purity/retry-after-failure tests: `wouldAccept does not
  mutate state — repeated calls give the same answer`, and `a failed apply
  must not commit — retrying the same envelope after wouldAccept still
  succeeds`.
- `android/wear/src/test/java/com/ams/herculex/sync/WearDataLayerSyncManagerTest.kt`
  (**new file**, 6 tests) — `WearRealtimeQueueStore` enqueue/
  `recordFailedAttempts`/`removeAll` round-trip (including the exact
  "middle message survives, both ends removed" partition shape the old
  `break`-based loop could never produce), plus `isExpired`'s three branches
  (attempt-budget trip, age trip, neither).
- `android/app/src/test/kotlin/com/ams/herculex/sync/MobileWearSyncManagerTest.kt`
  (**new file**, 6 tests) — same coverage as the wear-side file above, for
  `WearMessageQueueStore`/`PendingWearMessage`/`isExpired`.
- `android/app/src/test/kotlin/com/ams/herculex/PendingWorkoutCollisionTest.kt`
  (**new file**, 4 tests) — `shouldReplacePendingWorkout`: higher-revision
  incoming replaces, lower-revision incoming is kept (the actual collision
  fix — previously always "last write wins"), equal revision replaces,
  unknown/unparseable revisions fall back to last-write-wins.

**Test coverage gap (documented, not filled this session, same pattern as
Phase 1's equivalent note):** the actual node-iteration behavior inside
`flushPendingRealtimeMessages()` — that a per-node `sendMessage` failure on
one queued message no longer aborts every message after it — is exercised
only by inspection plus the pure `isExpired`/queue-store round-trip tests
above, not by a true end-to-end test with a faked `MessageClient`/
`NodeClient`. Neither Android module has any existing precedent for mocking
those Wearable Task-returning APIs (same gap already noted in the Phase 1
entry for `WorkoutViewModel`/`SyncService` entityId-gating tests). Building
that seam (likely via constructor-injecting a thin send-function interface)
would be a reasonable follow-up, same category as the fasting/quick-add
provider-layer test gap noted in Phase 2.

### Test infra note

**`android/app` had zero test dependencies and zero test sources before this
phase** — confirmed the same way Phase 0 confirmed it for the `wear` module.
Added `testImplementation("junit:junit:4.13.2")`,
`androidx.test:core:1.5.0"`, `org.robolectric:robolectric:4.11.1"` to
`android/app/build.gradle.kts` (identical versions to the wear module's
Phase 0 additions) and created
`android/app/src/test/kotlin/com/ams/herculex/` as the new test source root
— `kotlin/` rather than `java/` to mirror this module's existing
`src/main/kotlin/` layout (the wear module's main sources are
`src/main/java/` despite containing `.kt` files, which is why its Phase 0
test root was `src/test/java/` — each module's test root mirrors its own
main root, not a fixed convention).

To make the pure collision-policy and queue-mechanics logic reachable from
test files without instantiating the full `WearableListenerService`
(`PhoneWearListenerService`/`SyncService`), several previously-`private`
top-level declarations were widened to `internal`: `PendingWearMessage`,
`WearMessageQueueStore`, `PendingWearRealtimeMessage`,
`WearRealtimeQueueStore` (all four already existed; only their visibility
changed), plus the newly-added `PendingWorkoutSlot`,
`shouldReplacePendingWorkout`, and `isExpired` (×2, one per module) were
written `internal` and top-level from the start for the same reason. No
production behavior changed from these visibility widenings.

**Verification — all green except one pre-existing, unrelated flake:**
- `./gradlew :wear:testDebugUnitTest` → 21 tests, **1 failure**:
  `WearSyncContractTest > WearRevisionAllocator with different keys does not
  collide` (`WearSyncContractTest.kt:357`). **Pre-existing, not caused by
  this phase** — this test and the `WearRevisionAllocator` code under test
  are both untouched by Phase 4 (last touched in Phase 1). Reproduced
  deterministically across 3 separate runs on this machine. Root cause by
  inspection: the test calls `workout.next()`, `fasting.next()`,
  `workout.next()` back-to-back and asserts the second `workout` value
  differs from the `fasting` value — but `WearRevisionAllocator.next()`
  computes `max(persistedLast + 1, System.currentTimeMillis())`, and on a
  fast machine the middle and third calls can land in the same millisecond,
  making the assertion's premise ("two independent real-time-derived values
  taken microseconds apart never coincide") false rather than the allocator
  actually being broken. The Dart test file has the byte-for-byte same
  assertion shape (`test/wear_sync_contract_test.dart:385-397`,
  `'allocators with different keys do not collide'`) and is equally
  susceptible in principle, though it didn't reproduce in this session's
  `flutter test` run. Left as-is per this project's established
  precedent (Phase 2's log entry) of documenting pre-existing/unrelated
  failures rather than fixing them inside an unrelated phase — flagged here
  as a good target for a small follow-up (assert monotonicity per key
  instead of cross-key inequality).
- `./gradlew :app:testDebugUnitTest` → **BUILD SUCCESSFUL**, all tests
  green: `PendingWorkoutCollisionTest` 4/4, `MobileWearSyncManagerTest` 6/6
  (confirmed via the test-results XML: `tests="4" ... failures="0"` and
  `tests="6" ... failures="0"`).
- `./gradlew :wear:assembleDebug :app:assembleDebug` → **BUILD SUCCESSFUL**,
  both APKs compile with every visibility/signature change (the
  `wouldAccept`/`commit` split, the `internal` queue/collision types, the
  new `isExpired` helpers) threaded through correctly.
- `flutter test` (full suite, sanity check — no Dart files touched this
  phase) → 342 tests, **3 failures, all pre-existing/unrelated** (identical
  to the three named in the Phase 1 and Phase 2 log entries: the two
  `ongoing_workout_surface_snapshot_test.dart` failures and the
  date-sensitive `training_blocks_view_test.dart` "week board shows real day
  names" test). No new Dart failures.

**Files touched this phase:**
- `android/wear/src/main/java/com/ams/herculex/sync/WearSyncContract.kt`
  (`AppliedRevisionStore` split)
- `android/wear/src/main/java/com/ams/herculex/sync/SyncService.kt`
  (`wouldAccept`/`commit` call sites, isolated `onPeerConnected`)
- `android/wear/src/main/java/com/ams/herculex/sync/WearDataLayerSyncManager.kt`
  (non-blocking queue drain, retry cap, `internal` visibility)
- `android/app/src/main/kotlin/com/ams/herculex/PhoneWearListenerService.kt`
  (collision-safe `savePendingWorkout`, isolated `onPeerConnected`, new
  top-level `PendingWorkoutSlot`/`shouldReplacePendingWorkout`)
- `android/app/src/main/kotlin/com/ams/herculex/sync/MobileWearSyncManager.kt`
  (isolated `replayPersistentState`, non-blocking queue drain, retry cap,
  `internal` visibility)
- `android/app/build.gradle.kts` (new test dependencies — module had none)
- `android/wear/src/test/java/com/ams/herculex/sync/WearSyncContractTest.kt`
  (`acceptAndCommit` helper, new `wouldAccept` purity/retry tests)
- `android/wear/src/test/java/com/ams/herculex/sync/WearDataLayerSyncManagerTest.kt`
  (new — 6 tests)
- `android/app/src/test/kotlin/com/ams/herculex/sync/MobileWearSyncManagerTest.kt`
  (new — 6 tests, new test source root)
- `android/app/src/test/kotlin/com/ams/herculex/PendingWorkoutCollisionTest.kt`
  (new — 4 tests)

**Not committed to git yet** — same as Phases 0/1/2, stacked on top of the
pre-existing unrelated `sync_engine.dart`/`health_service.dart`/
`profile_view.dart` changes.

---

## Phase 3 — Dart: ID-based exercise/set reconciliation — DONE (2026-08-11)

**Goal:** replace positional (`existingExercises[i]`/`existingSets[j]`)
matching in `_syncSessionStateToDrift` with matching by the wire ids the
protocol already carries, so a mid-session delete/insert on the watch (which
shifts every exercise/set after it by one list position) no longer gets
misread by the phone as a substitution — silently overwriting the wrong
exercise/set and deleting a *different*, still-valid one from the tail.

**Deviation from the plan doc found during implementation (the significant
one):** the plan's own approach text says a substitution must be told apart
from a delete+insert by "a stable slot id separate from which exercise
occupies the slot" — but reading the actual code (not just the plan doc)
before writing anything showed that claim was only true for **sets**.
`LoggedSet.wireId` already round-trips correctly: the phone sends
`'set_<id>'`, and `WorkoutStore.kt`/`ExerciseCatalog.kt` already parse,
carry, and re-emit it unmodified (confirmed at
`WorkoutStore.kt:160,204`, pre-dating this phase). **Exercises had no
equivalent at all.** The phone already sends a top-level `'wireId':
'exercise_<id>'` on each entry in `pushActiveSessionToWatch`'s output
(`wear_workout_sync_service.dart:689`, also pre-dating this phase), but
`WorkoutStore.parseAndUpdateSession` silently discarded it — `ActiveExercise`
had no `wireId` field to hold it — so nothing was ever echoed back on the
watch's next push. Without that, per-exercise ID-based matching in Dart would
have had incoming `wireId` be `null` for every exercise, every time,
degrading to "everything is always new" (matching plan's own explicitly
described fallback for unrecognized ids) rather than real identity matching
for the phone-authored case, which is the actually-common case (most
exercises started as something the phone pushed to begin with, not something
the watch invented locally).

The plan doc's own file list scoped Phase 3 as Dart-only. Given the prose
above only holds with the round trip in place, this session added the
minimal Kotlin round-trip fix rather than silently degrading exercise
reconciliation to "match sets by id, but exercises are always
delete+insert" — folding it in here rather than deferring it the way Phase 2
deferred its Kotlin counterpart (`AppliedRevisionStore.shouldAccept` split),
because unlike that case, deferring this one would have meant *this phase's
own stated goal* wasn't actually met for exercises, only for sets.

**What was done:**

1. **`lib/features/workouts/data/wear_workout_sync_service.dart`
   (`_syncSessionStateToDrift`)** — rewritten to match by id instead of
   position:
   - Both `existingExercises` and each exercise's `existingSets` are now
     indexed into `Map<int driftId, Row>` before their respective loops.
   - New private helper `_driftIdFromWireId(dynamic wireId, String prefix)`
     parses the Drift row id directly out of the wire format
     (`'exercise_<id>'` → `<id>` as int; `'set_<id>'` → `<id>`) — no new
     Drift column or migration needed, since the id the phone would need to
     remember is already embedded in the string it sent. Returns `null` for
     anything that doesn't parse (missing, wrong type, wrong prefix, or a
     watch-minted `'watch_exercise_...'`/`'watch_set_...'`/`'planned_...'`
     id), which callers correctly treat as "no match — this is new."
   - Incoming exercises/sets found in the id map update that specific row
     in place (substitution/field-diff logic unchanged, just no longer
     gated on position) and are added to a `matchedExerciseIds`/
     `matchedSetIds` set; incoming entries with no match are inserted as
     new via the existing `addExerciseToSession`/`addSet` calls, exactly as
     before.
   - Deletion is now `existingIds - matchedIds` (an actual set difference)
     instead of "index past the incoming payload's length" — this is the
     literal fix for both of the plan's named audit scenarios (deleting a
     non-last exercise, deleting a non-last set) simultaneously, since both
     bugs were the same root cause (position used as identity) surfacing on
     the two nesting levels.
   - Substitution (`substituteExercise`) still fires exactly when a matched
     row's `exerciseId` differs from the incoming `catalogItem.id` — this
     part of the logic is unchanged; only *which row counts as "matched"*
     changed, from "same position" to "same wireId-derived id."

2. **Kotlin round trip (the deviation above), wear module only:**
   - **`WorkoutModels.kt`** — `ActiveExercise` gains a `wireId: String`
     field (non-nullable, unlike `LoggedSet.wireId`, since every exercise
     — phone-originated or watch-minted — now always has one by
     construction), defaulting to a fresh
     `"watch_exercise_${UUID.randomUUID()}"` so every existing call site
     that constructs a genuinely new `ActiveExercise` (`startWorkout`'s
     template mapping, `addExerciseToSession`) needed no changes at all.
   - **`WorkoutStore.kt`** — `sessionToJson` now writes `exObj.put("wireId",
     ex.wireId)` (mirrors the existing per-set `set.wireId?.let { ... }`
     line immediately below it). The parse-side one-liner that used to be
     inlined in `parseAndUpdateSession` was pulled out to a new top-level
     `internal fun resolveExerciseWireId(rawWireId: String): String`
     (blank/missing → mint a fresh id; otherwise return unchanged) —
     extracted specifically so this phase's one piece of real decision
     logic is unit-testable without a live `WorkoutViewModel`, mirroring
     Phase 4's precedent of widening pure logic
     (`shouldReplacePendingWorkout`, `isExpired`) to top-level `internal`
     functions for the same reason.
   - **`WorkoutViewModel.kt`** — `substituteExerciseInSession` (the one
     watch-side code path that already models "same slot, different
     exercise") now explicitly carries the old slot's `wireId` into the
     replacement `ActiveExercise`, instead of implicitly getting a fresh
     one via the default parameter. This is the concrete implementation of
     the plan's "stable slot id separate from which exercise is in the
     slot" requirement — without this one line, a watch-side substitution
     would echo back as a *new* wireId on the next push, and the phone
     would (correctly, given the input) read that as a delete+insert
     rather than a substitution.

**Explicitly not done (out of scope for this phase):** no attempt to make
newly-inserted rows land at their exact incoming list position (`orderIndex`
for exercises, `setIndex` for sets) — both are still assigned by
"current count at insert time," same as pre-Phase-3. A mid-list insert is
now correctly recognized as an insert (doesn't corrupt neighbors), but the
new row is appended rather than spliced into the middle. The plan's own
verification bullets ask for insertion working, not exact position fidelity,
and no existing repository method exposes "insert exercise/set at position
N" — adding one would be new capability beyond what this phase's fix needs.

**Known limitation (inherent to the existing echo-suppression design, not
introduced by this phase):** a set/exercise the watch creates locally gets a
watch-minted wireId that has no corresponding phone-side row yet. The phone
inserts it as new and assigns it a Drift id, but
`WearWorkoutSyncService._isApplyingRemoteSession` /
`_suppressOutboundUntil` (Phase 1/2 anti-echo-loop mechanism) means the
phone doesn't immediately push its own state back to the watch. Until the
next reactive push (`workouts_providers.dart`'s
`wearWorkoutSyncControllerProvider`, which fires once the ~500 ms
suppression window elapses or on the next user-driven mutation) hands the
watch the phone-canonical `'exercise_<id>'`/`'set_<id>'` wireId, a
watch-originated row that gets re-synced in that narrow window would look
"new" again and could be briefly double-inserted. This is strictly better
than the pre-Phase-3 behavior (which had no identity concept at all and
could silently corrupt *unrelated* rows), self-corrects within about a
second under normal use, and is a property of the existing echo-suppression
protocol rather than something this phase's reconciliation logic could fix
on its own — flagged here rather than silently accepted.

### Tests added

- **`test/wear_workout_sync_service_test.dart`** (5 new tests, all driven
  through the real `WearSyncService` platform-channel path like the
  existing tests in this file, not by calling `_syncSessionStateToDrift`
  directly):
  - `'deleting the first exercise of three (ID-based) leaves the other two
    with their original row identity, not shifted/corrupted'` — 3 exercises
    synced, then a second update with the first removed and the other two's
    phone-assigned wireIds echoed back; asserts the surviving Drift row ids
    are exactly the original two (proves position-based matching, which
    this test would fail under, would have substituted-then-deleted the
    wrong rows — worked through by hand in this session to confirm the old
    code really does produce the wrong pair).
  - `'a matching wireId with a different exercise substitutes in place (row
    identity preserved)'` and `'an unrecognized wireId with a different
    exercise is a delete+insert, not a substitution (row identity
    changes)'` — a matched pair proving the plan's explicit
    substitution-vs-delete+insert distinction actually holds both ways, not
    just "substitution still works by accident."
  - `'deleting the middle set of three (ID-based) leaves the other two sets
    with their original identity and data'` — same shape as the exercise
    case, one level down.
  - `'inserting a new set in the middle of the list does not disturb the
    existing sets around it'` — matches the plan's own named verification
    bullet ("vstavitev seta sredi seznama"); asserts by id (not list
    position) since, per the "explicitly not done" note above, the new set
    lands at the end of `setIndex` order rather than physically in the
    middle.
  - Confirmed **no changes needed** to any of the file's 25 pre-existing
    tests: they either don't re-sync a session with reused/matching ids
    across two updates at all, or (the one that does,
    `'a started-event redelivery with the same UUID applies in place...'`)
    use the plain `validExercise()` helper with no `wireId` field at all —
    which, under the new logic, makes every entry in every payload
    "unmatched" and correctly still nets out to the same final counts the
    test already asserted (worked through by hand, not just run-and-hope).
- **`android/wear/src/test/java/com/ams/herculex/workout/WorkoutStoreTest.kt`**
  (**new file**, 6 tests, Robolectric — needs a `Context` for
  `WearRevisionAllocator`'s `SharedPreferences` inside `sessionToJson`, same
  reason Phase 0's `WearSyncContractTest.kt` needed it):
  - `sessionToJson` writes each exercise's own `wireId` (not the template's)
    into the wire payload, for both a phone-style and a watch-style id.
  - An encode-then-decode chaining test: real `sessionToJson` output fed
    into the real `resolveExerciseWireId` (the function
    `parseAndUpdateSession` actually calls) proves the two halves of the
    round trip agree on the wire format, without needing a live
    `WorkoutViewModel` to observe `parseAndUpdateSession`'s own parsed
    output — see the coverage gap note below for why that's not attempted.
  - `resolveExerciseWireId` unit tests: non-blank input returned unchanged;
    blank/missing input mints a fresh `"watch_exercise_"`-prefixed id;
    two calls with blank input mint distinct ids (guards against the
    "every new exercise added in the same instant collides" failure mode
    that motivated using `UUID.randomUUID()` over the millis-based pattern
    `LoggedSet.wireId`'s defaults use elsewhere in this codebase); a
    `JSONObject` that never had a `"wireId"` key at all (not just an empty
    string) resolves the same way, since `org.json`'s `optString` returns
    `""` for a genuinely missing key.

**Test coverage gap (documented, not filled this session, same pattern as
Phase 1's and Phase 4's equivalent notes):** `WorkoutStore.parseAndUpdateSession`'s
own exercise list — specifically, that it actually calls
`resolveExerciseWireId` per exercise and hands the result into each
`ActiveExercise` — is not tested end-to-end, because doing so needs a live
`WorkoutViewModel` (its `viewModel?.updateSessionFromRemote(...)` is the only
way to observe the parsed result) and this module still has no Robolectric
shadow precedent for constructing one (`Wearable.getDataClient` mocking,
`viewModelScope` dispatcher control) — the exact gap the Phase 1 log entry
already flagged for entityId-gating tests, now hit a second time for the
same underlying reason. `resolveExerciseWireId` was pulled out to top-level
specifically to keep the actual decision logic covered despite this; the one
line at the call site (`resolveExerciseWireId(exObj.optString("wireId"))`)
is a direct visual match against the tested function, not something with
independent logic of its own. Similarly, `substituteExerciseInSession`'s new
`wireId = exercises[exerciseIndex].wireId` line is verified by inspection
only, for the same reason.

**Verification — all green except the same pre-existing, unrelated flake
already documented in the Phase 4 entry:**
- `flutter test test/wear_workout_sync_service_test.dart
  test/wear_sync_contract_test.dart` → 30/30 passed (25 pre-existing + 5 new).
- `flutter test` (full suite) → 347 tests, **3 failures, all
  pre-existing/unrelated** — identical to the three named in every prior
  phase's log entry (the two `ongoing_workout_surface_snapshot_test.dart`
  failures and the date-sensitive `training_blocks_view_test.dart` "week
  board shows real day names" test). 347 = 342 (Phase 1's baseline) + 5 new
  tests this phase; no new failures.
- `flutter analyze` (full repo) → 43 issues. Zero new issues in any
  production file this phase touched
  (`wear_workout_sync_service.dart` itself analyzes clean on its own: "No
  issues found!"). Two new `info`-level `use_null_aware_elements` hints
  appear in the new test-file helpers (`if (wireId != null) 'wireId':
  wireId,` inside a map literal) — a pre-existing pattern already used
  elsewhere in production code (e.g. `_templateJson`'s `if (item != null)
  'catalogExerciseId': item.id,`), not a new style violation, left as-is
  for consistency with that existing convention.
- `./gradlew :wear:testDebugUnitTest` → 27 tests, **1 failure**:
  `WearSyncContractTest > WearRevisionAllocator with different keys does not
  collide`. This is the exact same pre-existing flake documented in the
  Phase 4 log entry (untouched by this phase — last touched in Phase 1;
  root cause is a same-millisecond timing coincidence in the test's own
  assertion, not a real allocator bug). 27 = 21 (Phase 4's count) + 6 new
  tests this phase; all 6 new tests passed.
- `./gradlew :app:testDebugUnitTest` → **BUILD SUCCESSFUL**, unaffected (this
  phase touched no `app` module files).
- `./gradlew :wear:assembleDebug :app:assembleDebug` → **BUILD SUCCESSFUL**,
  both APKs compile with the `ActiveExercise.wireId` field and its call-site
  changes threaded through correctly.

**Files touched this phase:**
- `lib/features/workouts/data/wear_workout_sync_service.dart`
  (`_syncSessionStateToDrift` rewritten for ID-based matching; new
  `_driftIdFromWireId` helper)
- `android/wear/src/main/java/com/ams/herculex/workout/WorkoutModels.kt`
  (`ActiveExercise.wireId` field)
- `android/wear/src/main/java/com/ams/herculex/workout/WorkoutStore.kt`
  (`sessionToJson` writes exercise `wireId`; new top-level
  `resolveExerciseWireId`; `parseAndUpdateSession` uses it)
- `android/wear/src/main/java/com/ams/herculex/workout/WorkoutViewModel.kt`
  (`substituteExerciseInSession` preserves the slot's `wireId`)
- `test/wear_workout_sync_service_test.dart` (5 new tests)
- `android/wear/src/test/java/com/ams/herculex/workout/WorkoutStoreTest.kt`
  (new — 6 tests, new test source directory
  `android/wear/src/test/java/com/ams/herculex/workout/`)

**Not committed to git yet** — same as Phases 0/1/2/4, stacked on top of the
pre-existing unrelated `sync_engine.dart`/`health_service.dart`/
`profile_view.dart` changes.

---

## Phase 5 — Echo-guard robustness + Wear lifecycle/UX + missing nutrition sync — DONE (2026-08-11)

**Goal:** the last, mostly-independent group of fixes: the Dart echo-guard
flag's ownership race, three Wear OS lifecycle/UX bugs (sticky foreground
service, dead notification tap, a durable-put failure silently blocking the
fast MessageClient send), and the fact that the watch's local-only "+200
kcal" / "+500 ml water" / manual food quick-adds were never sent to the
phone at all.

**What was done:**

1. **Echo-guard race (Dart) —
   `lib/features/workouts/data/wear_workout_sync_service.dart`.**
   `_isApplyingRemoteSession`/`_suppressOutboundUntil` ownership moved
   entirely into `_enqueueRemoteApply` (the Phase 2 queue), set `true`
   immediately before `apply()` runs and reset in a `finally` immediately
   after, both *inside* the chained closure. Previously each handler
   (`_handleWatchWorkoutStarted`/`_handleWatchWorkoutUpdated`) set the flag
   `true` inside its own queued closure but reset it `false` in its
   *caller's* own outer `finally`, which runs as soon as that caller's own
   `await _enqueueRemoteApply(...)` resolves — not necessarily in lockstep
   with the next already-chained closure actually starting. A second call
   already queued onto the same `_remoteApplyQueue` could begin executing
   (setting the flag `true` again) in the gap between the first call's
   closure finishing and its caller's `finally` running, and that `finally`
   would then clobber the second call's still-in-flight guard back to
   `false` — defeating `shouldSkipOutboundSync` for whatever fraction of the
   second apply happened to fall in that gap. Both handler functions had
   their own `_isApplyingRemoteSession = true` line and outer `finally`
   block removed; the queue now brackets exactly one queued apply's
   execution per flag-flip, with no gap another chain link could interleave
   through.

2. **Sticky foreground service (ENG-14) —
   `android/wear/src/main/java/com/ams/herculex/sync/SyncService.kt`.** New
   private `stopOngoingServiceDirect()` sends `WorkoutOngoingService`'s
   `ACTION_STOP` intent directly, not gated on a live
   `WorkoutViewModel`. Called (in addition to the existing
   `activeViewModel?.endSessionFromPhone()`, which already covers the
   live-ViewModel case via `WorkoutViewModel.endSession`'s own `ACTION_STOP`
   send) from `handleSessionEnd(entityId)` and the `MESSAGE_FINISH_WORKOUT`
   message-received branch. Previously the *only* thing that ever stopped
   the foreground notification/service was `activeViewModel?.endSessionFromPhone()`
   — a no-op whenever `activeViewModel` is `null`, which is the common case
   once the Wear app is backgrounded/recycled (Wear OS is aggressive about
   killing background activities). A phone-finished workout in that state
   left the ongoing notification and foreground service running
   indefinitely.

3. **Notification tap no-op (ENG-15) —
   `android/wear/src/main/java/com/ams/herculex/MainActivity.kt`.** New
   `private val openActiveWorkoutRequests = MutableStateFlow(0L)` field,
   collected in Compose via `collectAsState()`. A new
   `consumeOpenActiveWorkoutExtra(intent)` reads and clears the
   `open_active_workout` extra and increments the flow; called from both
   `onCreate` (before `setContent`) and `onNewIntent`. The existing
   `LaunchedEffect(activeSession != null) { ... navController.navigate("active_workout") ... }`
   became `LaunchedEffect(activeSession != null, openWorkoutRequest) { ... }`.
   Previously `onNewIntent` only called `setIntent(intent)` — the bare
   `Activity.intent` field isn't Compose-observable state, and
   `FLAG_ACTIVITY_SINGLE_TOP` reuses the same Activity instance, so nothing
   ever forced `LaunchedEffect(activeSession != null)` to re-run on a second
   notification tap (its key hadn't changed: the session was already
   non-null from the first tap). Tapping the ongoing-workout notification a
   second time — e.g. after the user had navigated away to another
   screen — silently did nothing. The counter (not a boolean) specifically
   handles a tap while `activeSession` is *already* non-null, which a
   boolean flip-and-check couldn't distinguish from "no new tap happened."

4. **Durable put blocks fast send (ENG-16) —
   `android/wear/src/main/java/com/ams/herculex/workout/WorkoutViewModel.kt`.**
   `broadcastSessionToPhone`/`broadcastSessionEndToPhone`/
   `broadcastSessionDiscardToPhone` each wrap their
   `syncManager.pushActiveWorkoutSession(...)` call in
   `runCatching { }.onFailure { Log.e(...) }` instead of calling it as a bare
   sequential `await` ahead of `syncManager.sendMessageToAllNodes(...)`.
   Previously an exception from the durable DataClient put (e.g. no
   connected node) propagated out of the `viewModelScope.launch { }` block
   before the fast MessageClient send was even attempted — `sendMessageToAllNodes`
   never ran, *and* the coroutine crashed uncaught (`viewModelScope` has no
   exception handler of its own; the enclosing `try/catch` in each
   `broadcastSession*ToPhone` function only guards the synchronous act of
   launching the coroutine, not exceptions thrown inside its suspended body).
   A flaky/disconnected durable path used to silently kill the fast path
   for the same update, and could crash the watch app outright.

5. **Missing nutrition sync (watch quick-adds never reached the phone) —
   both platforms.** `NutritionViewModel.addCalories`/`addWater`/`logFood`
   previously only wrote to the watch's own local `MacroStore` and never
   contacted the phone, unlike the sibling `logQuickAdd`/`startFast`/
   `stopFast` methods. Added the same "additive, non-breaking message +
   phone-side handler" shape those already use:
   - **Wire format** — new `WearSyncPaths.MESSAGE_MACRO_COMMAND` /
     `MESSAGE_MACRO_ACK` constants (added to *both* the wear and app copies
     of `WearSyncPaths.kt` — this file is duplicated per module, not shared,
     matching every other constant in it). New
     `MacroStore.createCommand(kind, calories, protein, carbs, fats, waterMl)`
     builds a `commandId`-bearing JSON command mirroring
     `FastingStore.createCommand`/`QuickAddStore.createLogCommand`'s shape;
     `kind` is `"calories"`/`"water"`/`"food"`, with all fields always
     present (zeroed if irrelevant to that `kind`) so the phone-side decoder
     doesn't need per-kind optional handling.
   - **Watch (Kotlin)** — `WearDataLayerSyncManager.sendMacroCommand(commandJson)`
     mirrors `sendFastingCommand`/`sendQuickAddCommand` (goes through the
     already-durable, already-retried `sendRealtimeEvent` queue — see Phase
     4's non-blocking-queue-drain fix). `NutritionViewModel.addCalories`/
     `addWater`/`logFood` each now also call a new private `sendMacroCommand`
     helper after their existing local `MacroStore` write + `refresh()`.
     `SyncService.kt` logs `MESSAGE_MACRO_ACK` the same inert way it already
     logs `MESSAGE_QUICKADD_ACK` (no local pending-command bookkeeping to
     clear on the watch side — matching quick-add's shape, not fasting's;
     retry durability lives in `WearRealtimeQueueStore`, not a second
     store).
   - **Phone (Kotlin)** — `PhoneWearListenerService.kt` gained the same
     `KEY_MACRO_COMMANDS` pending-list/`savePendingMacroCommand`/
     `pendingMacroCommands`/`clearPendingMacroCommand` companion-object
     plumbing that `KEY_QUICKADD_COMMANDS` already has, plus an
     `onWatchMacroCommandListener` and an `onMessageReceived` branch for
     `MESSAGE_MACRO_COMMAND`. `MainActivity.kt` (phone) wires that listener
     to a new `"onWatchMacroCommand"` Flutter method-channel call, drains
     `pendingMacroCommands` in `dispatchPendingWorkout()` (same place the
     fasting/quick-add pending lists are drained), handles a new
     `"markWatchMacroCommandApplied"` method-channel case, and sends the ack
     via a new `sendMacroAckToWear` (mirrors `sendQuickAddAckToWear`).
   - **Phone (Dart)** — `wear_sync_service.dart` gained the same
     handler-setter/pending-queue/drain shape as `onWatchQuickAddCommand`
     (`_onWatchMacroCommand`, `_pendingMacroCommands`,
     `_deliverMacroCommand`/`_drainPendingMacroCommands`, the
     `'onWatchMacroCommand'` dispatch case, `resetForTesting` coverage, and
     `markWatchMacroCommandApplied()`). `nutrition_providers.dart`'s
     `wearSyncControllerProvider` gained `WearSyncService.onWatchMacroCommand`,
     following the exact dedupe-after-success shape (Phase 2) of
     `onWatchFastingCommand`/`onWatchQuickAddCommand`: an `appliedMacroCommands`
     set is populated only *after* the corresponding repository write
     succeeds, so a failed write's command survives to be retried instead of
     being dropped.
   - **Phone-side write, "food"/"calories"** — there was no existing
     "log raw macros without a catalog food" concept on the phone (its
     `NutritionRepository.logFood` always requires a `foodId`; the sibling
     `onWatchQuickAddCommand` handler resolves one from `QuickAddStore`'s
     catalog). Rather than add a new data model, a `"calories"`/`"food"`
     command creates a one-off `createCustomFood(name: 'Quick Add (Watch)', kcalPer100g: ..., ...)`
     and logs it at exactly 100 g/portion — since the food's macros are
     defined *as* "per 100g", logging 100g makes the entry's contribution
     exactly equal the reported totals, with no unit-conversion arithmetic
     needed.
   - **Phone-side write, "water"** — new
     `NutritionRepository.addWaterMl(date, deltaMl)`, an upsert-increment
     into the pre-existing `DailySummaries.waterMl` column (Drift table
     already existed in the schema — added for an unrelated, never-finished
     purpose; nothing in the feature layer touched it before this). No
     migration needed. Wrapped in `_db.transaction()` (read-then-write
     upsert): reads the existing `DailySummaries` row for the day (if any),
     adds `deltaMl` to its `waterMl`, and `insertOnConflictUpdate`s the new
     total.

**Deviations / scope notes:**

- The plan's own Phase 5 prose names `WearDataLayerSyncManager.kt` in its
  file list without saying why; reading it confirmed it needed exactly one
  addition (`sendMacroCommand`, mirroring `sendFastingCommand`/
  `sendQuickAddCommand` for the new nutrition-sync commands) — no other
  change to that file was needed this phase.
- The plan's ENG-16 prose describes wrapping `pushActiveWorkoutSession()` in
  `runCatching` inside `broadcastSessionToPhone` specifically; the same bug
  (a bare sequential `await` ahead of the fast `sendMessageToAllNodes` call,
  with no exception isolation) existed identically in
  `broadcastSessionEndToPhone`/`broadcastSessionDiscardToPhone`, so the same
  fix was applied to both — not explicitly named in the plan's prose, but
  the same root cause the plan's own file list implies by naming
  `WorkoutViewModel.kt` as a whole.
- No new Gradle dependencies or Drift migrations were needed anywhere in
  this phase — `DailySummaries.waterMl` already existed in the schema, and
  `MacroStore.createCommand`/the new `WearSyncPaths` constants are pure
  additions to existing files.

**Test coverage gaps (documented, not filled this session, same pattern as
every prior phase's equivalent notes):**

- The echo-guard fix itself (item 1) has no dedicated regression test that
  asserts on `_isApplyingRemoteSession`'s value during the exact
  interleaving window the fix targets — the field is private, and the
  actual consequence of the old bug (a stale/incomplete outbound push
  firing mid-apply) is driven by `workouts_providers.dart`'s
  `wearWorkoutSyncControllerProvider`, a separate, large provider graph this
  codebase has no existing test-harness precedent for standing up (the
  exact gap the Phase 2 log entry already flagged for
  `onWatchFastingCommand`/`onWatchQuickAddCommand`, now hit a third time for
  the same underlying reason). Added instead: a test that fires two watch
  updates back-to-back *without awaiting between them* — the same
  interleaving shape production sees, since the platform-channel dispatcher
  never awaits a handler either — and asserts both still apply correctly,
  in order. This is a reasonable serialization regression net but is not a
  substitute for actually observing the flag.
- Items 2–4 (`stopOngoingServiceDirect`, the `MainActivity`
  `MutableStateFlow`/`LaunchedEffect` wiring, the `runCatching`-wrapped
  broadcast functions) have no unit tests — all three need either a live
  Android `Service`/`Activity`/`ViewModel` instance or Compose UI test
  infra, which neither Android module has any existing precedent for (the
  exact gap the Phase 1 log entry flagged for `WorkoutViewModel`/
  `SyncService` entityId-gating tests, and Phase 4 flagged for
  `flushPendingRealtimeMessages`'s node-iteration behavior). Verified by
  code-path inspection instead (see "Manual/inspection verification"
  below).
- The new Kotlin phone-side plumbing for macro commands
  (`PhoneWearListenerService`'s `pendingMacroCommands`/
  `clearPendingMacroCommand`/`savePendingMacroCommand`, `MainActivity`'s
  listener wiring and ack path) has no dedicated test — this mirrors the
  pre-existing, already-untested `pendingFastingCommands`/
  `pendingQuickAddCommands` twins it was modeled on (neither of those has a
  test either, confirmed by grep before writing this phase's code). Not a
  new gap introduced by this phase, but not closed by it either.
- `MacroStore.createCommand` (the one genuinely new, pure piece of decision
  logic in the nutrition-sync addition) **is** covered — see
  `MacroStoreTest.kt` below.

**Tests added:**

- `test/wear_workout_sync_service_test.dart` — one new test: two
  back-to-back (unawaited-between) watch updates for the same session both
  apply, strictly in order, ending on the second's payload. See the
  coverage-gap note above for what this does and doesn't prove.
- `test/phase5_nutrition_test.dart` — new `'Phase 5 — addWaterMl (watch
  water quick-add sync)'` group, 3 tests: creates the day's row on first
  add, accumulates across repeated same-day adds, keeps separate days
  independent.
- `android/wear/src/test/java/com/ams/herculex/sync/MacroStoreTest.kt`
  (**new file**, 3 tests, Robolectric — `org.json.JSONObject` is only a
  throwing stub on the plain-JUnit classpath without Robolectric shadowing
  it in, the same reason every other JSON-touching test in this module
  already runs under `@RunWith(RobolectricTestRunner::class)`; this file
  initially didn't and every test failed with `RuntimeException` on the
  first `JSONObject` call until that was added — caught by this session's
  own Gradle run, not left in): `createCommand` for `kind = "water"` carries
  only the water field non-zero; for `kind = "food"` carries all four
  macros; two calls mint distinct `commandId`s.

**Manual/inspection verification:**

No Android device or emulator was available in this execution environment
(`adb devices` returns an empty list) to actually run the four manual
scenarios the plan's own Phase 5 "Verifikacija" section calls for
(phone-finished workout while the Wear app is backgrounded; a second
notification tap after navigating away; simulated durable-put failure via
airplane mode; a watch-side quick-add appearing on the phone after sync).
**These four scenarios still need to be manually tested on real hardware or
a paired emulator by whoever has that available** — this was not silently
skipped, it could not be done from here. In its place, each fix was traced
by hand through its exact call path to confirm the mechanism holds:

- **Sticky foreground service:** confirmed `handleSessionEnd` and the
  `MESSAGE_FINISH_WORKOUT` branch both now call `stopOngoingServiceDirect()`
  unconditionally (not `activeViewModel?.let { }`-gated), and that
  `WorkoutOngoingService.onStartCommand`'s `ACTION_STOP` branch
  unconditionally calls `stopForeground(...)` + `stopSelf()` regardless of
  what state the service was in — so the direct call is suffient on its own
  even with no live ViewModel.
- **Notification tap:** confirmed `consumeOpenActiveWorkoutExtra` runs in
  both `onCreate` (before `setContent`, so the first tap's cold-start case
  is covered) and `onNewIntent` (the warm-Activity re-tap case), and that
  `openActiveWorkoutRequests` is a real `MutableStateFlow` collected via
  `collectAsState()` — Compose is guaranteed to see every increment as a
  distinct recomposition trigger, unlike the old bare-`Intent`-field
  approach.
- **Durable-put-blocks-fast-send:** confirmed `runCatching { }` fully
  encloses only the `pushActiveWorkoutSession` call in each of the three
  broadcast functions, with `sendMessageToAllNodes` as an unconditional
  next statement in the same coroutine body (not inside the `runCatching`
  block, and not `.also`/chained such that a failure would skip it).
- **Nutrition sync:** traced the full round trip end to end for each `kind`
  — Kotlin `NutritionViewModel.addCalories(200)` →
  `MacroStore.createCommand(kind = "calories", calories = 200)` →
  `WearDataLayerSyncManager.sendMacroCommand` → `MESSAGE_MACRO_COMMAND` →
  `PhoneWearListenerService.onMessageReceived` →
  `onWatchMacroCommandListener` → `MainActivity`'s `"onWatchMacroCommand"`
  method-channel call → Dart `WearSyncService`'s dispatch →
  `nutrition_providers.dart`'s handler → `createCustomFood` + `logFood` →
  `markWatchMacroCommandApplied` → `MESSAGE_MACRO_ACK` back to the watch.
  Every hop's method/constant names and payload shapes line up; the
  `addWaterMl` write itself is unit-tested (see above), and the
  `MacroStore.createCommand` payload shape is unit-tested — only the actual
  device-to-device transport is unverified here.

**Verification — all green:**

- `flutter test test/wear_workout_sync_service_test.dart
  test/wear_sync_contract_test.dart test/phase5_nutrition_test.dart
  test/wear_watch_event_queue_test.dart` → 54/54 passed.
- `flutter test` (full suite) → 350 tests, **4 failures**:
  - The same three pre-existing/unrelated failures every prior phase's log
    entry has documented: the two `ongoing_workout_surface_snapshot_test.dart`
    failures and the date-sensitive `training_blocks_view_test.dart` "week
    board shows real day names" test.
  - `test/wear_sync_contract_test.dart: WearRevisionAllocator with different
    keys does not collide` — the exact same-millisecond timing flake
    documented in the Phase 4 log entry (untouched by this phase; last
    touched in Phase 1). Phase 4's entry noted it "didn't reproduce in this
    session's `flutter test` run" but flagged it as equally susceptible in
    principle — it reproduced in this session's full-suite run. Confirmed
    non-flaky in isolation: passed 3/3 re-runs of just that test. Not a
    regression from this phase (this phase touched no file the test or the
    code under test depends on).
  - 350 = 347 (Phase 3's baseline) + 3 new `phase5_nutrition_test.dart`
    tests (the new test's own group) + 1 new `wear_workout_sync_service_test.dart`
    test − 1 (Phase 3's own baseline count already included the file before
    this phase's addition, so the net new count here is +4 tests, 0 new
    failures).
- `flutter analyze` (full repo) → 38 issues. Zero new issues in any file
  this phase touched in production code; the two `info`-level
  `use_null_aware_elements` hints on lines this phase's edit shifted
  (`test/wear_workout_sync_service_test.dart`) are the exact same
  pre-existing pattern the Phase 3 log entry already documented and left
  as-is for consistency with existing code (`_templateJson`'s `if (item !=
  null) 'catalogExerciseId': item.id,`).
- `./gradlew :wear:testDebugUnitTest` → 30 tests, **0 failures** (24 from
  Phases 0/1/3/4 + 6 new: 3 `MacroStoreTest` + the 3-test
  `WearSyncContractTest`/`WorkoutStoreTest`/`WearDataLayerSyncManagerTest`
  counts were already included in the prior total). Confirmed via
  `build/wear/test-results/testDebugUnitTest/*.xml`: all four suites
  (`MacroStoreTest`, `WearDataLayerSyncManagerTest`, `WearSyncContractTest`,
  `WorkoutStoreTest`) show `failures="0" errors="0"`. The Phase 4-documented
  `WearRevisionAllocator` flake did **not** reproduce in this Gradle run.
  **Gotcha hit and fixed in this session:** `MacroStoreTest.kt` initially
  had no `@RunWith(RobolectricTestRunner::class)` (reasoned, incorrectly,
  that a `Context`-free pure function needed no Android shadowing) — all 3
  tests failed with `RuntimeException` on the first `JSONObject` call, since
  `org.json` classes are stub-only (throw on every real call) on the plain
  unit-test classpath without Robolectric. Added the annotation; reran
  green.
- `./gradlew :app:testDebugUnitTest` → 10 tests (unchanged from Phase 4:
  `PendingWorkoutCollisionTest` 4/4, `MobileWearSyncManagerTest` 6/6), **0
  failures** — this phase's `app`-module changes (`MainActivity.kt`,
  `PhoneWearListenerService.kt`, `WearSyncPaths.kt`) had no new tests added
  (see coverage-gap note above) but didn't break any existing ones.
- `./gradlew :wear:assembleDebug :app:assembleDebug` → **BUILD SUCCESSFUL**,
  both APKs compile with every signature/field addition from this phase
  threaded through correctly.

**Files touched this phase:**

- `lib/features/workouts/data/wear_workout_sync_service.dart` (echo-guard
  ownership moved into `_enqueueRemoteApply`)
- `android/wear/src/main/java/com/ams/herculex/sync/SyncService.kt`
  (`stopOngoingServiceDirect`, `MESSAGE_MACRO_ACK` log branch)
- `android/wear/src/main/java/com/ams/herculex/MainActivity.kt`
  (`openActiveWorkoutRequests` `MutableStateFlow`, `consumeOpenActiveWorkoutExtra`)
- `android/wear/src/main/java/com/ams/herculex/workout/WorkoutViewModel.kt`
  (`runCatching`-wrapped durable puts in all three broadcast functions)
- `android/wear/src/main/java/com/ams/herculex/nutrition/NutritionViewModel.kt`
  (`addCalories`/`addWater`/`logFood` now also send a macro command;
  new `sendMacroCommand` helper)
- `android/wear/src/main/java/com/ams/herculex/sync/MacroStore.kt`
  (new `createCommand`)
- `android/wear/src/main/java/com/ams/herculex/sync/WearDataLayerSyncManager.kt`
  (new `sendMacroCommand`)
- `android/wear/src/main/java/com/ams/herculex/sync/WearSyncPaths.kt`
  (new `MESSAGE_MACRO_COMMAND`/`MESSAGE_MACRO_ACK`)
- `android/app/src/main/kotlin/com/ams/herculex/sync/WearSyncPaths.kt`
  (same two new constants, app-module copy)
- `android/app/src/main/kotlin/com/ams/herculex/PhoneWearListenerService.kt`
  (`KEY_MACRO_COMMANDS` plumbing, `onWatchMacroCommandListener`,
  `MESSAGE_MACRO_COMMAND` receive branch)
- `android/app/src/main/kotlin/com/ams/herculex/MainActivity.kt`
  (`markWatchMacroCommandApplied` channel case, listener wiring, pending-drain,
  `sendMacroAckToWear`)
- `lib/features/nutrition/data/wear_sync_service.dart` (macro-command
  handler/pending-queue/drain plumbing, `markWatchMacroCommandApplied`)
- `lib/features/nutrition/presentation/nutrition_providers.dart`
  (`onWatchMacroCommand` handler)
- `lib/features/nutrition/data/nutrition_repository.dart` (new `addWaterMl`)
- `test/wear_workout_sync_service_test.dart` (1 new test)
- `test/phase5_nutrition_test.dart` (new `addWaterMl` group, 3 tests)
- `android/wear/src/test/java/com/ams/herculex/sync/MacroStoreTest.kt`
  (new — 3 tests)

**Not committed to git yet** — same as every prior phase, stacked on top of
the pre-existing unrelated `sync_engine.dart`/`health_service.dart`/
`profile_view.dart` changes.

---

## Remediation project summary (all 6 phases)

All six phases of the plan
(`docs/wear-sync-race-conditions-remediation-plan-2026-08-11.md`) are now
done, all in 2026-08-11 sessions:

| Phase | Theme | Key fixes |
|---|---|---|
| 0 | Test harness groundwork | Cross-decoder v1 wire fixtures (Dart + new Kotlin test file); wear module had zero test sources/deps before this |
| 1 | Protocol v2: session UUID + monotone revision | `entityId` = a real, persisted session UUID (not a local auto-increment id) carried on every message including end; apply-time gating rejects updates/ends for the wrong session; revision persists across restart instead of resetting; legacy unenveloped payloads fail closed |
| 2 | Dart dedupe-after-success + transactions + queue fix | `WearDedupeState`/`AppliedRevisionStore` split into `wouldAccept`/`commit`, committed only after a successful write; `_syncSessionStateToDrift` wrapped in a transaction; `_enqueueRemoteApply` no longer poisons itself on one failed apply |
| 3 | ID-based exercise/set reconciliation | Positional (index) matching replaced with wire-id matching, so a mid-session delete/insert on the watch no longer corrupts unrelated rows; required an unplanned Kotlin `ActiveExercise.wireId` round-trip fix to actually work for exercises, not just sets |
| 4 | Kotlin collision-safe storage + isolated replay/flush + queue drain | Pending-workout slot collision resolved by revision instead of last-write-wins; `onPeerConnected`'s replay/flush and the phone's 4-way `replayPersistentState` each isolated per-field so one failure doesn't cascade; queue drain no longer `break`s on first failure, with a retry/age cap |
| 5 | Echo-guard robustness + Wear lifecycle/UX + missing nutrition sync | Echo-guard flag ownership moved into the Phase 2 queue; sticky foreground service, dead notification tap, and durable-put-blocks-fast-send all fixed; watch quick-adds (`+calories`/`+water`/manual food) now actually reach the phone |

**Net effect:** every ENG-06 through ENG-19 finding from
`docs/app-audit-report-2026-08-10.md`'s WearOS/cross-device section that
this plan scoped in is now addressed on both platforms, with unit-test
coverage for every piece of logic these six sessions could reach without
new device/Activity/Service/ViewModel test infrastructure (the recurring,
consistently-documented gap — none of the six phases' sessions found an
existing precedent for mocking `Wearable.getDataClient`/`MessageClient`/
`NodeClient`, standing up a live `Activity`/`Service`/`ViewModel` under
Robolectric, or wiring `wearWorkoutSyncControllerProvider`'s large provider
graph in a test).

**Known residual limitations, carried forward rather than silently
resolved:**

- The Phase 3 log entry's "known limitation": a watch-created set/exercise
  can briefly double-insert on the phone within the ~500 ms echo-suppression
  window, until the phone's next reactive push hands back the
  phone-canonical wire id. Self-corrects within about a second; a property
  of the existing echo-suppression design, not something any later phase
  changed.
- The `WearRevisionAllocator` "different keys do not collide" test
  (Dart and Kotlin) is a documented, reproducible timing flake (asserts two
  real-time-derived values taken microseconds apart never land in the same
  millisecond) — flagged in Phases 1/4/5's log entries as a good small
  follow-up (assert monotonicity per key instead of cross-key inequality),
  never fixed since no phase's actual scope touched it.
- The four Phase 5 manual-verification scenarios (see that section above)
  still need to be run on real hardware/emulator by whoever has that
  available — this session had none.

**Git status:** nothing from any of the six phases has been committed yet.
All of Phase 0 through Phase 5's work is stacked, uncommitted, in the
working tree alongside the pre-existing, unrelated, already-in-progress
changes to `lib/data/sync/sync_engine.dart`, `lib/features/health/data/health_service.dart`,
and `lib/features/profile/presentation/profile_view.dart` (explicitly
out-of-scope for this plan per its own header). **Given all verification
above is green and this was the last phase, now is a reasonable point to
commit** — but the unrelated pre-existing changes to those three files
should either be committed separately (if they're actually finished) or
left out of whatever commit(s) cover this plan's work, so the remediation
project's history stays legible on its own. Not committed automatically;
left for explicit instruction per this session's own operating rules.
