# Herculex App Audit Report

Date: 2026-08-26
Scope: Flutter app (`lib/`, 395 files, ~172k LOC) — runtime crash paths, global
error handling, the workout-finish flow, cloud-sync schema parity, and the
migration test suite.
Status: Audit **plus remediation**. The P0/P1 findings were fixed in this pass;
everything else is recorded below with `file:line` for a later one.

Companion to `docs/app-audit-report-2026-08-10.md`, which covered
security/privacy/data-integrity. This one covers crashes.

## Executive Summary

The reported symptom — *"red screen when I finish a workout"* — is real,
reproducible, and was one defect with two faces. Tracing it surfaced a
structural gap behind it: **the app had no global error handling of any kind**.

Four things were wrong, in descending order of user impact:

1. **Finishing a workout broke itself.** `endSession()` disposes the very
   widget whose handler is still running, so the code after that await used a
   dead `ref` and threw. The dialog never closed, the celebration screen never
   opened, and the next dialog rebuild threw *during build* — the red screen.
2. **No error boundary anywhere.** A build failure was the red box in debug and
   a **silent grey box in release**, with nothing captured. No crash reporter,
   no log, no fallback UI.
3. **Cloud sync of workouts was broken by the previous commit.** Local schema
   v33/v34 added columns and tables with no Supabase counterpart, so every
   `workout_sessions` push failed with `PGRST204` and quarantined after 8
   retries.
4. **24 tests were failing**, all of them migration/schema — meaning the v33 and
   v34 migration steps had never been executed by anything.

Static analysis was clean throughout (`flutter analyze`: 0 errors), so none of
this was reachable by grep alone.

## Verification Performed

| Check | Before | After |
| --- | --- | --- |
| `flutter analyze --no-pub` | 24 issues, 0 errors | **23 issues, 0 errors** |
| `flutter test --no-pub` | 1235 passed, 4 skipped, **24 failed**, 11m incl. a 10-minute hang | **1269 passed, 4 skipped, 0 failed, 1m46s** |
| `dart run custom_lint` (riverpod_lint) | 1 issue | **0 issues** |

The one analyzer issue that disappeared is
`use_build_context_synchronously` at `active_workout_view.dart:644` — it was a
true positive for the bug in §1. The 23 that remain are all pre-existing and
cosmetic (unused imports, deprecated `onReorder`, one `unnecessary_null_comparison`);
none are in code this pass touched.

The suite went from 11 minutes to 1m46s because `end_fast_dialog_test.dart` was
burning the full 10-minute per-test timeout on the hang described in §4b.

---

## 1. Finishing a workout red-screened — FIXED

### Root cause

`WorkoutsView` renders the active-workout screen only while a session exists:

- `lib/features/workouts/presentation/workouts_view.dart:21-25` watches `activeSessionProvider`.
- `lib/features/workouts/presentation/workouts_providers.dart:48-50` → `watchActiveSession()`.
- `lib/features/workouts/data/workouts_repository.dart:412-421` filters on `endedAt.isNull()`.

So the moment `endSession()` commits, the stream emits `null`,
`ActiveWorkoutView` leaves the tree, and `_ActiveWorkoutViewState` is
**disposed** — while its Finish dialog is still on the Navigator stack.
Riverpod's `ref` then throws `StateError: Cannot use "ref" after the widget was
disposed`, which is a real throw, not a debug assert: it fires in release too.

Two distinct failures followed from that:

**(a) Finish silently aborted.** `active_workout_view.dart:761-763` (pre-fix)
did `ref.read(wearWorkoutSyncServiceProvider)` *after* `await
repo.endSession(...)` at :742 and a multi-frame Health write at :749-756. The
throw was uncaught, so :774 (`Navigator.pop`) and :776 (`WorkoutFinishView.show`)
never ran. The user was left on a stuck "Finish Workout" dialog over a workout
that had, in fact, already been saved. Same shape at :728, :730 and :765-771.

**(b) The red screen.** `active_workout_view.dart:648-650` (pre-fix) called
`ref.watch(editingSessionOriginalEndedAtProvider)` from inside the dialog's
`StatefulBuilder` — a **build-phase** read on a `ref` captured from a widget
that no longer exists. Any rebuild after (a), such as tapping "Change" at
:673-698, threw during build → the default red `ErrorWidget`.

`_confirmCancel` had the same latent shape at :559-565 and :590-596.

### Fix

New `lib/features/workouts/application/finish_workout_action.dart`.
`FinishWorkoutAction.resolve(ref)` eagerly resolves every provider the flow
needs **before the first await**; `run()` then performs the writes without
touching `ref` or a `BuildContext` again. The dialog now pops *before* the
write rather than after, and the finish screen is pushed through a
`NavigatorState` captured up front (the root navigator outlives the screen; the
widget's own `context` is guaranteed dead by then).

The dialog's edited end-time moved from a global `StateProvider` into the
dialog's own `StatefulBuilder` state, removing the build-phase `ref.watch`
entirely. `_showFinishSummary` no longer takes `context`/`ref` parameters —
shadowing `State.context` with a parameter is what defeated the analyzer's
async-gap checking in the first place.

Also fixed here: the `TextEditingController` at :639 was never disposed (leaked
on every finish, and on every early return).

### Related: dynamic mode never ended the session at all — FIXED

`dynamic_workout_view.dart:886-892` opened `WorkoutFinishView` **without calling
`endSession`**. Consequences: `session_summary.dart:97` computed
`(endedAt ?? startedAt).difference(startedAt)` = zero, so the summary read
`0m`; calories fell back to the `sets.length * 2` estimate; and because the
session stayed active, the live banner and the ongoing-workout notification
kept running behind the celebration screen. It now routes through the same
`FinishWorkoutAction`.

---

## 2. No global error handling — FIXED

A repo-wide grep for `ErrorWidget.builder`, `FlutterError.onError`,
`PlatformDispatcher.instance.onError` and `runZonedGuarded` returned **zero
matches**. `lib/main.dart` called `runApp` bare.

Consequences:

- Widget build errors → red `ErrorWidget` in debug, **blank grey box in release**.
- Uncaught async errors (dropped Futures, `Timer.periodic` callbacks, stream listeners) reached the root zone and were printed at best.
- No crash reporting. `lib/core/env.dart:28-29` declares `sentryDsn` and `oneSignalAppId`; neither identifier is referenced anywhere else.
- `lib/core/result.dart` and `lib/core/failures.dart` defined a `Result`/`Failure` layer with **0 imports** — the intended error-typing layer was never adopted.

### Fix

New `lib/core/error/`:

| File | Role |
| --- | --- |
| `app_error_handler.dart` | Installs `FlutterError.onError`, `PlatformDispatcher.instance.onError`, and `ErrorWidget.builder`. Called from `main.dart` immediately after `ensureInitialized()`, before anything that can throw. |
| `error_log.dart` | In-memory ring buffer, last 50 errors. No I/O, no dependency, and hardened against an error object whose `toString()` itself throws. |
| `app_error_view.dart` | `AppErrorView` (the in-place fallback) and `AppErrorScreen` (full-screen, for the router). |
| `error_log_view.dart` | Read-only log viewer. |

`AppErrorView` reads the **static** `AppColors` rather than `context.hx`, and
supplies its own `Directionality`: `ErrorWidget.builder` replaces an arbitrary
widget at an arbitrary point in the tree, so it can land above `MaterialApp`
entirely — needing an inherited `Theme` there would throw from inside the error
path and recurse. It is intentionally non-interactive for the same reason;
recovery actions live in `AppErrorScreen`, which has a real context.

`GoRouter` gained the `errorBuilder` it never had (`lib/app/router.dart`).

**Deliberately not `runZonedGuarded`**: `main` calls
`WidgetsFlutterBinding.ensureInitialized()` before several awaits, and
binding-initialised-in-a-different-zone-than-`runApp` is its own class of
startup failure. Since Flutter 3.3, `PlatformDispatcher.onError` covers
everything reaching the root zone, which is the coverage the zone guard would
have added.

The log viewer is routed at `/diagnostics/errors` **outside** the router's
`kDebugMode` block, unlike the `/admin/*` routes. Release is precisely where an
error is otherwise invisible, so it has to be reachable there. It is linked
from the admin dashboard under a new "Diagnostics" section.

Per the brief, no crash-reporting dependency was added; `Env.sentryDsn` stays
stubbed.

---

## 3. Cloud sync of workouts is broken — SQL WRITTEN, NOT APPLIED

Local schema v33 and v34 (commit `bd43449`) shipped **without their remote
half**:

- **v33** added `workout_sessions.photo_path` and `.calories_burned` (`lib/data/local/database.dart:837-838`). Neither is listed in that table's `localOnlyColumns` (`lib/data/sync/sync_table_specs.dart:184-196` — only `session_uuid` is), and `SyncService._buildRemotePayload` (`lib/data/sync/sync_service.dart:480-500`) does `SELECT *` and forwards every unconsumed column. So a v33 client sends both in **every** `workout_sessions` upsert, including the null ones.
- **v34** added `workout_circuits` and `circuit_exercises` and registered both in `sync_table_specs.dart:180-182, 242-248`. The remote tables do not exist at all.

Against the live project, PostgREST answers `PGRST204` (unknown column) and
`42P01` (undefined table) respectively. `_pushOne` records the failure,
retries with exponential backoff, and **quarantines the op at
`maxPushAttempts = 8`**. Every finished workout has been failing to reach the
cloud since that commit, silently — the sync layer is well-built enough that it
degrades to a `lastError` in `SyncState` rather than throwing, which is why
nothing surfaced.

`supabase/migrations/0013_set_entry_metrics.sql` documents this exact hazard in
its ORDERING note. The same trap was walked into again.

### Deliverable

`supabase/migrations/0015_workout_circuits_and_session_columns.sql` — the two
columns plus both tables with RLS policies, `set_updated_at` /
`record_sync_tombstone` triggers, and the `supabase_realtime` publication,
following the `0014_joint_pain_logs.sql` template. `circuit_exercises.exercise_id`
uses the `CatalogueFk` shape, so it carries the
`exercise_catalog_id` / `exercise_slug` pair and the XOR check constraint that
`exercise_progressions` and `machine_settings` use in `0002`.

**Not applied.** Review and push it yourself. Anything already quarantined from
these two regressions needs the outbox retried after it lands (the admin
dashboard's "Re-upload All Local Data" action).

---

## 4. 24 failing tests (and a 10-minute hang) — FIXED

### 4a. The migration half (10 tests)

All 24 were migration/schema tests. Root cause: `schemaVersion => 34`
(`lib/data/local/database.dart:89`) while `drift_schemas/` and
`test/generated_migrations/` stopped at **v32**. The whole suite still validated
against v32:

```
Schema does not match
 workout_sessions:
  columns: additional:
   Contains the following unexpected entries: photo_path, calories_burned
```

The v33/v34 migration steps are correct on inspection — but **nothing had ever
executed them**. `.planning/phases/11-.../11-03-PLAN.md` records this as
"Research Pitfall 9": forgetting the two `drift_dev schema` commands produces a
failure that reads like a migration bug but is a stale dump.

### Fix

Regenerated `drift_schemas/drift_schema_v34.json` and
`test/generated_migrations/schema_v34.dart`, repointed all ten
`migrateAndValidate` calls from 32 to 34, and added a **v32 → v34 replay** —
the first test to exercise the v33 and v34 steps at all.

There is deliberately no `drift_schema_v33.json`. `schema dump` captures only
the *current* version, and `git log -S"schemaVersion => 33"` returns nothing:
v32 → v34 landed in a single commit, so **no build ever carried v33** and no
device can be sitting on it. v32 → v34 is the only real upgrade path.

### 4b. The other 14

| Test | Cause | Fix |
| --- | --- | --- |
| `schema_v25_test.dart` (4) | `migrateAndValidate(db, 25)` — but `AppDatabase` always migrates to its own `schemaVersion`, so this compared a v34 database against the v25 snapshot. | Retargeted to 34. `schema_v26_test.dart` already documented this convention ("this pair of lines moves with every `schemaVersion` bump") and had been kept at 31; the rest were never updated. |
| `schema_v26/27/28/29_test.dart` (4) | Same: `testWithDataIntegrity` ends in `migrateAndValidate(db, newVersion)`. | `newVersion`/`createNew` retargeted to v34, with the rationale copied into each file. |
| `fk_constraints_test.dart` | Frozen FK inventory: 38 declared edges, actual 40. v34's `circuit_exercises` added a CASCADE and a RESTRICT edge. | Added both edges; counts 20/10/8 → 21/11/8. Note the companion "edge action counts" test iterates the *expected* list, so it passes vacuously and must be updated in step. |
| `rep_tracking_profiles_test.dart` (2) | Eight new catalogue slugs from the library expansion had no rep-tracking profile. The failure message names its own fix. | Ran `tool/derive_rep_profiles.py --write`; `assets/data/rep_tracking_profiles.json` regenerated. The registry-length assertion is derived from `catalog.length`, so it healed with it. |
| `exercise_search_test.dart` | `expect(hitCount('curl'), lessThan(45))` — the catalogue grew and "curl" now legitimately matches 46. | Made proportional: `lessThan(namesById.length * 0.15)`. The test asserts a *precision* property; a hard count was only ever a snapshot of one catalogue size and hid a real signal behind routine growth. |
| `widget_test.dart` | Booting the real app starts `NotificationSyncService`, whose pull is `.timeout(const Duration(seconds: 2))` (`notification_sync_service.dart:88`). That live Timer outlives `pumpAndSettle`, and the binding asserts on any timer pending at teardown. | Pump 3s so it elapses. |
| `end_fast_dialog_test.dart` (2) | The app bug in §5's last row. One test failed the cancel assertion; the other **hung for the full 10-minute timeout** on `watchHistory().first`. | Fixed in the app, not the test. |

---

## 5. Other crashes fixed in this pass

| Site | Defect | Severity |
| --- | --- | --- |
| `lib/features/buddy/application/buddy_providers.dart:24-40` | `buddyGatewayProvider` / `buddyChannelServiceProvider` **threw `StateError`** when `Env.hasSupabase` was false. `active_workout_view.dart:88` watches this transitively in `build()`, so a throw out of `Provider.create` propagated synchronously out of `ref.watch` → **instant red screen on the app's most-used screen** in every credential-less build: the `.vscode/launch.json` "local-only, no backend" config, a bare `flutter run`, and every widget test. Now degrades via `UnconfiguredBuddyGateway`, matching the existing `UnconfiguredAuthService` / `NoopSyncBackendService` idiom. | **P0** |
| `lib/features/buddy/application/buddy_providers.dart` (same provider) | `ref.onDispose(controller.dispose)` on a `StateNotifierProvider` — which already disposes its notifier. A **double dispose**, throwing on every teardown. Latent and invisible only because the provider above always threw before reaching that line in any test. Uncovered by fixing the first bug. | **P1** |
| `active_exercise_card.dart:1698`, `dynamic_workout_view.dart:687` | Unguarded `jsonDecode` **inside `build()`** on `setTypeMetaJson` — untrusted, sync-carried, migration-surviving free-form JSON. Any malformed or legacy value = `FormatException` during layout on the active-workout screen. Also `(meta['miniSets'] as List?)?.cast<int>()`, where a non-object JSON root gives `NoSuchMethodError` and `cast` defers element failures to render time. Now goes through `domain/set_type_meta.dart`. | **P1** |
| `exercise_details_view.dart:216` | `maxX: (points.length - 1).toDouble()` — with exactly one completed session `minX == maxX == 0` and fl_chart's `(x - minX) / (maxX - minX)` is NaN → `RenderBox` assertion. Fires for **every user** the first time they open exercise details after one workout. | **P1** |
| `metric_detail_view.dart:257-276` | Same degenerate x-range, on the user's first body measurement. `minX`/`maxX` were not set at all, so fl_chart inferred a collapsed range from the spots. | **P1** |
| `lib/core/units.dart:93` | `kg.round()` throws `UnsupportedError` on NaN/Infinity. Called from `build()` at `workout_finish_view.dart:705` and `active_workout_view.dart:183`. Same guard added to `session_summary.dart`'s `tonnageLabel`. | **P2** |
| `lib/app/router.dart:95,101` | `int.parse(state.pathParameters['id']!)` inside route builders — a bang plus a throwing parse on untrusted deep-link/notification input, in a build phase, with no `errorBuilder` to catch it. Now `tryParse` + a typed error screen. | **P2** |
| `lib/features/profile/presentation/profile_view.dart:149` | `ref.read()` inside `dispose()` — the sole `riverpod_lint` finding (`avoid_ref_inside_state_dispose`). The final draft flush ran on every back-navigation pop. Repository snapshotted in `initState` instead. | **P2** |
| `muscle_recovery_v3.dart:268` | `clamp` passes NaN straight through (NaN fails both comparisons), and the caller does `.round()` on the result — `UnsupportedError`, not 0. One bad contribution failed the whole recovery provider. | **P2** |
| `muscle_recovery_row.dart:56` | `value: recoveryScore / 100` — the only progress-indicator `value:` in the app with no clamp. | **P3** |
| `workouts_repository.dart:655,719` | `.getSingle()` (throws `StateError` on 0 rows) on caller-supplied ids that can name merged-away or concurrently-removed rows. One reachable caller is the widget MethodChannel handler's *unawaited post-frame callback*, where the throw has no handler at all. Now `getSingleOrNull()` + `NotFoundFailure` — which also puts the previously-dead `lib/core/failures.dart` to work. | **P2** |
| `recipe_builder_view.dart:69` | `setState` after `await` with no `mounted` check; dismissing the sheet mid-insert threw "setState() called after dispose()". The next method in the same file already guarded it. | **P3** |
| `end_fast_dialog.dart` (Save) | `await repo.watchHistory().first` — a *stream* subscription used to take a one-shot value — sat **between the user's tap and `cancelFastingGoal()`**. If that first emission is slow or absent, the scheduled goal notification stays armed and the session is never ended: the user taps Save and nothing happens. `cancelFastingGoal()` now runs first, and `FastingRepository.history()` was added as the one-shot read. This is what made `end_fast_dialog_test.dart` hang for the full 10-minute test timeout. | **P2** |

---

## 6. Found and NOT fixed — for a later pass

Ranked by likelihood of firing for a real user.

### 6.1 `MissingPluginException` is not a `PlatformException`

They are sibling classes; `on PlatformException catch` does **not** catch it. It
is what's thrown wherever the native handler isn't registered — i.e. all of iOS
for these Android-only channels.

- `lib/services/widget_sync_service.dart` — all four methods (`:39, :62, :78, :91`) catch only `PlatformException` and have **no `Platform.isAndroid` guard**. Their three callers are `async` `ref.listen` callbacks (`analytics_providers.dart:131-138`, `:151-158`, `nutrition_providers.dart:692+`) whose Futures Riverpod discards, and all three are started unconditionally at `app.dart:577-579`. Net effect on iOS: three uncaught `MissingPluginException`s per data change.
- `lib/features/nutrition/data/wear_sync_service.dart` — 11 sites (`:381, :392, :413, :454, :463, :478, :488, :505, :516, :527, :546`) with the same defect. The file is inconsistent with itself — `:342, :402, :423, :433, :443` use a bare `catch`. `WearSyncService.initialize()` is called from `main.dart` on every platform.
- `lib/services/app_shortcuts_service.dart:40-42` — `QuickActions.initialize` unguarded, while `setShortcutItems` right below it is correctly wrapped.

`lib/services/workout_bubble_service.dart:35,115` is the reference pattern to
copy: a `Platform.isAndroid` gate plus a bare `catch`.

### 6.2 Sync service: uncaught async errors on a 20-second timer

- `sync_service.dart:198-204` — `pushOnce`/`pullAll` are fired from `Timer.periodic` with the Future dropped, and both are `try { } finally { }` with **no `catch`** (`:364-402`, `:642-661`). A throw from `_refreshState`'s `customSelect` (`:120-130`) or from `_applyPulledRow` (called at `:695`, *outside* the `_backend.pull` try block) escapes into a Timer callback — an uncaught async error every 20 seconds. Now at least visible via the new `ErrorLog`.
- `sync_service.dart:213` — the realtime stream's `.listen((_) => pullAll())` has no `onError`; a websocket failure is an unhandled stream error.
- `lib/app/providers.dart:51-58` — `service.start(uid)` / `service.stop()` called unawaited from a `ref.listen`. `start()` awaits `_claimLocalDatabaseFor` (which does `DELETE FROM pending_sync_ops`), then `.subscribe()`, then `pushOnce()`/`pullAll()`. Any throw in that chain is an unhandled async error **at sign-in**, leaving `_userId` set with timers possibly uninstalled.
- `SupabaseSyncBackendService` (`supabase_sync_backend_service.dart:21-82`) has **no try/catch at all**, so a `401 JWT expired` and a `23503 foreign_key_violation` are indistinguishable — both become `e.toString()` in `last_error` and retry 8 times. An expired token quarantines the entire outbox after ~20 minutes instead of triggering a refresh. Repo-wide there is exactly **one** `on PostgrestException` (`buddy_remote_gateway.dart:135`).

### 6.3 Database open is the highest-blast-radius single point of failure

`lib/data/local/database.dart:864-886` — `beforeOpen` runs
`ExerciseImporter.runFromAsset(this)` on **every app open**. It is internally
guarded (`exercise_importer.dart:22-36`) with a fallback to `_seedFallback(db)`,
but **`_seedFallback` itself is not guarded**. If seeding throws, the database
never opens, `appDatabaseProvider` throws, and since every repository provider
watches it, the entire app is a grey box. Same exposure from a corrupt or
locked SQLite file at `:890`.

Unguarded migration steps, unlike their neighbours: `database.dart:383-395`
(v22 per-row UUID backfill), `:403` (`repairForeignKeyViolations`),
`:589-594` (a `(t as dynamic).syncUuid` cast per column across 34 tables, where
the cast sits *outside* `tryAddColumn`'s try block).

### 6.4 Seven async builders with no error branch

`hasError` appears **zero times** in the repo. Each of these renders a
permanent spinner and swallows the exception:

`nutrition_view.dart:565`, `:642`, `:731`; `log_entry_sheet.dart:1144`;
`block_builder_view.dart:640`; `fixture_recording_view.dart:83`;
`rotation_pool_sheet.dart:252`.

Worth noting the good news: all **97** `AsyncValue.when(` call sites do have an
`error:` branch, and `.requireValue` is used zero times.

### 6.5 Parsing hazards on DB/remote strings

`DateTime.parse` (throws; `tryParse` doesn't) on values that come from the
database or the network: `training_blocks_view.dart:173`, `:426`;
`programs_providers.dart:83-84` (getters on a provider-family argument, so the
throw poisons the provider); `scheduled_workout_row.dart:32`;
`calendar_service.dart:46`; `sync_service.dart:676`, `:741`, `:761`.
`goals_view.dart:287` does the same thing correctly, inside a `try`.

`openfoodfacts_client.dart:24,53` — `jsonDecode(resp.body) as Map<String, dynamic>`
checks the status code but not the body. Captive portals return HTTP 200 with
HTML, and barcode scanning is a core flow on gym/hotel Wi-Fi.

`machine_config_sheet.dart:59` — unguarded `jsonDecode` in a method fired from
`initState`, so the sheet sticks at `_loaded == false`.

### 6.6 Smaller items

- `periodization.dart:99` — `(weeks * 0.4).ceil().clamp(1, weeks)` throws `ArgumentError` when `weeks == 0` (`clamp` requires `lower <= upper`). Guarded only by `assert(weeks > 0)` at `:43`, and **asserts are stripped in release**. `programs_repository.dart:154` and `preset_program.dart:34` do not validate.
- `rpe_estimator.dart:94,100` — `reduce` on a possibly-empty iterable plus `/ n` with `n == 0`, reachable from the LOO cross-validation loop at `:192` when `n == 1`.
- `workouts_repository.dart:579-583` — `watchSingle()` emits a `StateError` into the stream the moment the row count leaves 1 (i.e. session deleted). `workouts_providers.dart:135` awaits it via `.future`, which rethrows and poisons `sessionSummaryProvider`. Currently absorbed by `workout_finish_view.dart:194`'s `error:` branch, so it degrades to an `Error: ...` text screen rather than a red one.
- `lib/app/providers.dart:137-144` — `measurementsRepositoryProvider` calls `repo.syncOnStartup()`, and `MeasurementsRepository`'s constructor (`measurements_repository.dart:18`) calls it **again**. Two unawaited concurrent runs on first read, racing on the profile's `weightKg`.
- `lib/app/app.dart:102-176` — the inbound widget-channel handler has no try/catch; `(call.arguments as Map?)` throws `TypeError` on a `List` payload, and the `openActiveWorkout` branch then runs unawaited DB writes in a post-frame callback.
- `calendar_service.dart:127` — `calendarsResult.data!.firstWhere(..., orElse: () => calendarsResult.data!.first)`: a bang *and* `.first` on a possibly-empty list.
- `set_type_menu.dart:381,383` — `orElse: () => all[1]` / `all[0]` with no length check.
- `workout_calendar_card.dart:112,338` — `summaries.first` inside a `.when(data:)`; safe today only because `dashboard_providers.dart:250` hardcodes `List.generate(7, ...)`.
- `dashboard_customize_sheet.dart:332` and `dashboard_view.dart:658` — `.types.first` as the first statement of `build()`, guarded at the call site rather than the widget boundary.
- `muscle_deload_advisor.dart:88` — the only `firstWhere` in `lib/` with neither `orElse` nor a surrounding `try`. Safe by coincidence, and it runs 152 times per recovery computation.
- Leaks: `goals_view.dart` (`:152, :178, :206, :266`) and `calorie_meal_goals_view.dart:163` create `TextEditingController`s and have **no `dispose()` override at all**. `workout_finish_view.dart:94-98` builds a new `CurvedAnimation` on every build, never disposed.
- `workout_finish_view.dart:142-149` — `_removePhoto` uses `ref` after an await with no guard and no try/catch; `_pickPhoto` right above it is wrapped.
- Cosmetic, surfaced by the new test: the finish dialog trips Flutter's "ListTile background color or ink splashes may be invisible" advisory — a `DecoratedBox` between a `ListTile` and its `Material`.

### 6.7 Non-crash observations

- `lib/app/router.dart` redirect: if `profileProvider` ever enters an *error* state, `profileAsync.asData?.value` is null and the user is permanently redirected to `/onboarding`. There is no error branch.
- Auth errors are surfaced by string-scraping — `'$error'.replaceAll('Exception: ', '').replaceAll('AuthException: ', '')` at `onboarding_view.dart:136/151/166/193` and `profile_view.dart:2161/2180`. A `PostgrestException` would be shown to the user verbatim, SQL detail included.
- `gamification_providers.dart:61-63, :88-90` swallow **all** exceptions from achievement evaluation with `catch (_)`, so PR/achievement failures are silent. `workouts_providers.dart:148` calls the evaluator outside that guard.
- `lib/services/widget_sync_service.dart:98-104` shadows `debugPrint` with an `assert(() { ... }())` block, so **every widget-sync log is compiled out in release**.
- Zero routes read `state.extra`, and `router.dart` has no `extra as X` casts — that whole class of hot-restart/deep-link bug does not exist here.
- The Drift migration is unusually well-defended: every `addColumn` from v24 on goes through a local `tryAddColumn` helper, every index creation is `IF NOT EXISTS` inside a `try`, and no NOT-NULL-without-default column is ever added.
- The sync service's failure *bookkeeping* (backoff, `attempts`, `last_error`, quarantine, `SyncState` to the UI) is the best-engineered error handling in the repo. Its gaps are at the edges (§6.2), not the core.

---

## Files Changed

**Added**
- `lib/core/error/app_error_handler.dart`, `app_error_view.dart`, `error_log.dart`, `error_log_view.dart`
- `lib/features/workouts/application/finish_workout_action.dart`
- `lib/features/workouts/domain/set_type_meta.dart`
- `lib/features/buddy/data/unconfigured_buddy_gateway.dart`
- `supabase/migrations/0015_workout_circuits_and_session_columns.sql` *(not applied)*
- `drift_schemas/drift_schema_v34.json`, `test/generated_migrations/schema_v34.dart`
- `test/workout_finish_flow_test.dart`, `test/app_error_handler_test.dart`

**Modified**
- `lib/main.dart`, `lib/app/router.dart`
- `lib/features/workouts/presentation/active_workout_view.dart`, `dynamic_workout_view.dart`, `active_exercise_card.dart`, `exercise_details_view.dart`
- `lib/features/workouts/data/workouts_repository.dart`, `lib/features/workouts/domain/session_summary.dart`
- `lib/features/buddy/application/buddy_providers.dart`, `lib/features/buddy/data/buddy_channel_service.dart`
- `lib/features/profile/presentation/profile_view.dart`
- `lib/features/analytics/domain/muscle_recovery_v3.dart`, `presentation/widgets/muscle_recovery_row.dart`
- `lib/features/measurements/presentation/metric_detail_view.dart`
- `lib/features/nutrition/presentation/recipe_builder_view.dart`
- `lib/core/units.dart`
- `lib/features/fasting/data/fasting_repository.dart`, `presentation/end_fast_dialog.dart`
- `lib/features/admin/presentation/admin_dashboard_view.dart`
- `assets/data/rep_tracking_profiles.json` *(regenerated)*
- `test/migration_test.dart`, `schema_v25..v29_test.dart`, `fk_constraints_test.dart`, `exercise_search_test.dart`, `widget_test.dart`, `end_fast_dialog_test.dart`

## Recommended Next Steps

1. Review and apply `0015_workout_circuits_and_session_columns.sql`, then retry the outbox. Until then, workout sync stays broken.
2. §6.1 — the `MissingPluginException` family. Cheap, mechanical, and it is currently throwing uncaught on iOS on every data change.
3. §6.3 — guard `_seedFallback` and the database open. Highest blast radius left in the app.
4. §6.2 — add `catch` to `pushOnce`/`pullAll` and `onError` to the realtime listener.
5. §6.4/§6.5 — error branches and `tryParse`. Both get easier to prioritise now that the `ErrorLog` makes failures visible.
