# Herculex App Audit Report

Date: 2026-08-10  
Scope: Flutter mobile app, native Android phone integrations, WearOS app, local database, sync flows, tests, lint, and UI/UX review.  
Status: Read-only audit. No source files were changed during the review.

## Executive Summary

The app is not release-ready in its current state.

The largest risks are not polish issues. They are data integrity, privacy/security, false product behavior, and cross-device workout sync correctness. The WearOS app needs special attention because several phone-watch flows can lose, misapply, or silently fail workout state.

The highest priority work is:

1. Rotate and remove the embedded Gemini API key from the client.
2. Stop fabricating health data when permissions or platform reads fail.
3. Fix fake cloud sync behavior so pending sync operations are not reported as successful without remote acknowledgement.
4. Re-enable and test database foreign keys, or implement equivalent durable cascading behavior.
5. Stabilize phone-Wear workout identity, revision ordering, dedupe, and transactional apply.
6. Fix the failing Flutter tests and native Android widget lint errors.
7. Address destructive UI actions and WearOS tap-target/accessibility issues.

## Verification Performed

Commands reviewed during the audit:

| Check | Result |
| --- | --- |
| `flutter test --reporter expanded` | 322 passed, 2 failed |
| `flutter analyze` | 36 issues, no analyzer errors |
| `flutter pub outdated --no-dev-dependencies` | 28 locked dependencies upgradable; 12 direct deps constrained below resolvable versions |
| `./gradlew :wear:lintDebug :wear:testDebugUnitTest :app:lintDebug --continue` | Wear lint completed with warnings; Wear unit tests had no sources; phone lint failed |
| `git status --short` | Clean worktree after audit |

Flutter test failures:

- `test/ongoing_workout_surface_snapshot_test.dart:26` expects `82.5 kg x 8`, while implementation emits `82.5 kg x 8 reps`.
- `test/ongoing_workout_surface_snapshot_test.dart:43` expects action order `[+ Rep, +5kg, Done, -Rep, -5kg]`, while implementation emits `[Done, +Rep, +5kg, -Rep, -5kg]`.

Phone Android lint failures:

- RemoteViews usage errors in macro widget providers:
  - `android/app/src/main/kotlin/com/herculex/app/widgets/CarbsWidgetProvider.kt:33`
  - `android/app/src/main/kotlin/com/herculex/app/widgets/FatWidgetProvider.kt:33`
  - `android/app/src/main/kotlin/com/herculex/app/widgets/ProteinWidgetProvider.kt:33`
- Machine-local `local.properties` path errors also appeared during the native lint run.

## Release Blockers

### 1. Embedded Gemini API Key and Insecure Token Storage

Files:

- `lib/features/nutrition/data/gemini_food_analyzer_service.dart`
- `lib/features/auth/domain/auth_session.dart`
- `lib/features/auth/data/local_auth_repository.dart`
- `android/app/src/main/AndroidManifest.xml`
- `android/wear/src/main/AndroidManifest.xml`

Findings:

- A real Gemini API key is embedded as the default client key.
- The Gemini request places the key in the query URL, increasing accidental exposure through logs, proxies, crash reports, and analytics.
- A user-provided Gemini key is stored in SharedPreferences.
- Firebase ID token data is serialized into local auth session JSON and stored in SharedPreferences.
- Android backup exclusion is not configured for the sensitive local state.
- Wear manifest currently allows backup.

Impact:

- Production credential exposure.
- User token exposure on rooted/debuggable devices, backups, or local extraction.
- Forced key rotation risk if the repo has already been shared.

Recommended fix:

- Rotate the exposed Gemini key immediately.
- Remove all default API keys from client source.
- Proxy Gemini calls through a backend or user-owned secret flow.
- Avoid URL query parameters for secrets.
- Use platform secure storage for sensitive tokens.
- Add explicit Android backup exclusion for sensitive preferences/databases.
- Disable Wear backup unless there is a deliberate restore model.

### 2. Cloud Sync Reports Success Without Real Cloud Sync

File:

- `lib/data/sync/sync_engine.dart`

Findings:

- The sync engine simulates Firestore work with an artificial delay/logging path.
- Pending operations can be deleted and success reported without a real remote acknowledgement.
- `queueSyncOp` appears dormant because no callers were found, but the code path is dangerous if activated.

Impact:

- User data may appear synced when it is only locally discarded.
- Future features could unknowingly rely on a false durability guarantee.

Recommended fix:

- Either remove cloud sync claims entirely or implement a real acknowledgement/retry model.
- Pending operations should only be cleared after durable remote success.
- Add tests around offline, retry, conflict, and server failure behavior.

### 3. Health Data Is Fabricated on Failure

File:

- `lib/features/health/data/health_service.dart`

Findings:

- Errors are swallowed during health reads.
- When health data is unavailable, synthetic values are substituted, including steps, calories, heart rate, and sleep.
- Today’s health rows can be replaced by those synthetic values.
- Sleep totals can double-count overlapping sleep data types.
- The service requests broad read/write permissions.

Impact:

- Users can see false health data.
- Charts, insights, and downstream nutrition/workout logic may be based on invented measurements.
- This is especially risky in a fitness app because trust in recorded health state is central.

Recommended fix:

- Never synthesize user health measurements.
- Represent missing, denied, and errored states explicitly in the UI.
- Merge overlapping sleep intervals before summing.
- Request the minimum required permissions.
- Add tests for denied permissions, empty platform data, partial data, and overlapping sleep ranges.

### 4. Database Foreign Keys Are Disabled

File:

- `lib/data/local/database.dart`

Related repositories:

- `lib/features/workouts/data/workout_repository.dart`
- `lib/features/gyms/data/gyms_repository.dart`
- `lib/features/programs/data/programs_repository.dart`
- `lib/features/nutrition/data/nutrition_repository.dart`

Findings:

- Foreign key enforcement is intentionally disabled.
- Several delete paths remove parent rows without guaranteeing child cleanup.
- This creates orphan and dangling records across workouts, gyms, programs, and nutrition.

Impact:

- Historical records can become inconsistent.
- UI screens can display stale or broken references.
- Sync and analytics logic can operate on invalid relational state.

Recommended fix:

- Audit and repair existing orphaned rows.
- Re-enable foreign key enforcement in database open hooks.
- Use explicit cascading deletes or soft deletes where history must be preserved.
- Add migration tests and repository delete tests.

### 5. Nutrition History Changes After Catalog Deletion

File:

- `lib/features/nutrition/data/nutrition_repository.dart`

Findings:

- Historical nutrition totals are recomputed from the live food catalog.
- Deleting a food can cause older logged meals to lose their nutritional values.
- Missing food references can produce zeroed totals.

Impact:

- Historical nutrition data is not immutable.
- User progress and analytics can silently change after catalog edits.

Recommended fix:

- Store immutable nutrition snapshots on log entries.
- Prefer soft delete for catalog foods that have history.
- Add regression tests for deleting foods after logging meals.

## WearOS and Cross-Device Findings

### High Severity

| Finding | Files | Risk |
| --- | --- | --- |
| Failed Future chain can poison workout sync queue | `lib/features/workouts/data/wear_workout_sync_service.dart` | One malformed update can block later updates until restart |
| Dedupe revision is committed before durable apply | Dart and Kotlin Wear sync contract/service files | Failed applies may be treated as already processed |
| Delayed update can overwrite the wrong phone workout | `wear_workout_sync_service.dart`, `PhoneWearListenerService.kt` | Watch state can mutate a newer or unrelated phone workout |
| Workout end messages lack stable identity | `wear_workout_sync_service.dart`, `PhoneWearListenerService.kt` | Ending one workout can end another after reconnection or restart |
| Snapshot reconciliation is positional despite wire IDs | `wear_workout_sync_service.dart` | Exercise/set reorder or deletion can corrupt the wrong item |
| Remote session apply is not wrapped in a Drift transaction | `wear_workout_sync_service.dart` | Partial writes can leave invalid workout state |
| `_isApplyingRemoteSession` race can suppress or allow wrong echoes | `wear_workout_sync_service.dart` | Feedback loop prevention is unreliable |
| Phone-ended workout can leave sticky Wear foreground service | `SyncService.kt`, `WorkoutOngoingService.kt` | Watch may continue showing stale active workout state |
| Ongoing notification tap may do nothing | `WorkoutOngoingService.kt`, `MainActivity.kt` | User cannot reliably return to active workout |
| Watch nutrition quick actions are local only | `NutritionViewModel.kt` | Watch appears to update calories/water/food without syncing phone |
| Macro goals are not effectively parsed on watch | Flutter nutrition Wear service, native sync managers | Wear macro UI can show wrong goal context |
| Durable put failure aborts fast message send | `WorkoutViewModel.kt` | Watch-to-phone commands may fail unnecessarily |

Recommended WearOS sync direction:

- Introduce a stable shared workout/session UUID across phone and watch.
- Include session identity in every command, update, and end message.
- Use monotonic revision or Lamport-style ordering instead of wall-clock millis alone.
- Apply remote snapshots transactionally.
- Commit dedupe markers only after successful durable apply.
- Reconcile exercises and sets by stable IDs, not list position.
- Treat phone-ended sessions as tombstones so delayed Wear messages cannot resurrect or mutate them.
- Add contract tests that run the same payloads through Dart and Kotlin decoders.

### Additional WearOS Platform and UX Risks

Files:

- `android/wear/src/main/kotlin/.../HomeScreen.kt`
- `android/wear/src/main/kotlin/.../ActiveWorkoutScreen.kt`
- `android/wear/src/main/kotlin/.../ManageExerciseScreen.kt`
- `android/wear/src/main/kotlin/.../SetLoggerScreen.kt`
- `android/wear/src/main/kotlin/.../MediaControlsScreen.kt`
- `android/wear/src/main/kotlin/.../FastingScreen.kt`
- `android/wear/src/main/kotlin/.../AddWaterScreen.kt`
- `android/wear/src/main/kotlin/.../OneUiPill.kt`
- `android/wear/src/main/AndroidManifest.xml`

Findings:

- Wear macro overview content is passed but not rendered because `OneUiPillCard` ignores the `content` slot.
- Finish, discard, and remove actions are one-tap destructive actions.
- Several Wear controls are below comfortable WearOS target sizes.
- Active workout is not prioritized strongly enough on the watch home screen.
- Active workout screen places media controls before the current exercise.
- Sync animation stops after a fixed delay regardless of actual result.
- Hidden pager/swipe behavior can conflict with custom right-swipe handling.
- Ambient/AOD behavior is not explicitly handled for screens with timers or infinite animation.
- Emoji-style icons reduce consistency and accessibility compared with vector icons.
- Notification permission is requested immediately at launch rather than contextually.
- Foreground service/current permission handling should be revisited before target SDK upgrades.

Recommended WearOS UX direction:

- Make active workout the first-class home state.
- Use confirmation or undo for Finish, Discard, Remove exercise, and similar actions.
- Raise tap targets toward 48dp where layout allows.
- Add TalkBack labels for symbolic controls and custom pills.
- Use Wear-friendly iconography instead of emoji symbols.
- Tie sync UI to real success/failure state.
- Validate round 40-47mm displays, square Wear displays, rotary/bezel behavior, TalkBack, bright outdoor use, damp-hand interaction, and AOD.

## Phone and Platform Findings

| Severity | Finding | Files | Recommendation |
| --- | --- | --- | --- |
| High | Timezone database is not initialized before scheduling notifications | `lib/main.dart`, supplement and workout notification services | Initialize timezone data and set local timezone before scheduling |
| High | Exact alarm scheduling failures are silent | `supplement_notification_scheduler.dart`, `workout_notification_service.dart` | Add exact alarm permission/access UX and fallback behavior |
| High | Deleted supplement reminders can remain scheduled | `supplement_notification_scheduler.dart` | Track notification IDs durably and cancel exact IDs |
| High | Progress photos store picker temp/cache path | `measurements_view.dart`, measurements repository | Copy images into app-owned storage before saving |
| High | Android macro widgets fail RemoteViews lint | macro widget providers and layout | Use RemoteViews-supported widgets and methods |
| Medium | OpenFoodFacts client has no timeout/cancel/error mapping | `openfoodfacts_client.dart` | Add request timeouts, cancellation, and user-safe error states |
| Medium | Release builds can fall back to debug signing | phone and Wear Gradle files | Fail release build when signing config is missing |
| Medium | SharedPreferences sync queue read-modify-write is unsynchronized | native sync managers | Serialize writes or move queue to durable structured storage |
| Medium | Wall-clock millis used as revision | `WorkoutStore.kt` | Use monotonic revision per session |
| Medium | Decoders accept broad schema/entity/origin values | Dart and Kotlin Wear contracts | Validate schema version, entity, and origin strictly |

## UI/UX Scorecard

Phone and tablet:

| Pillar | Score |
| --- | --- |
| Copy | 2 / 4 |
| Visuals | 3 / 4 |
| Color | 2 / 4 |
| Typography | 2 / 4 |
| Spacing | 2 / 4 |
| Experience Design | 1 / 4 |
| Total | 12 / 24 |

WearOS:

| Pillar | Score |
| --- | --- |
| Copy | 2 / 4 |
| Visuals | 2 / 4 |
| Color | 3 / 4 |
| Typography | 2 / 4 |
| Spacing | 1 / 4 |
| Experience Design | 1 / 4 |
| Total | 11 / 24 |

## Highest-Priority UI/UX Fixes

### Phone App

1. Add accessible labels and semantics to custom navigation and workout controls.
   - `lib/widgets/floating_nav_bar.dart`
   - `lib/features/workouts/presentation/active_workout_view.dart`
   - `lib/features/nutrition/presentation/widgets/macro_rings.dart`

2. Fix onboarding disabled/loading behavior.
   - `lib/features/onboarding/presentation/onboarding_view.dart`
   - `lib/widgets/premium_button.dart`

3. Add confirmation or undo for destructive actions.
   - Gym deletes
   - Nutrition swipe deletes
   - Meal log entry deletes
   - Active exercise deletes
   - Template deletes

4. Replace raw or hidden error states with user-safe recovery UI.
   - `insights_view.dart`
   - `dashboard_widgets.dart`
   - `active_workout_view.dart`
   - `measurements_view.dart`
   - `templates_view.dart`

5. Improve contrast for button colors.
   - Current dark primary `#0A84FF` with white is approximately 3.65:1.
   - Current light primary `#007AFF` with white is approximately 4.02:1.
   - Both are below the 4.5:1 target for normal text.

6. Add tablet/adaptive layouts.
   - `main_scaffold.dart`
   - `dashboard_view.dart`
   - `dashboard_widgets.dart`
   - `health_integrations_view.dart`
   - `measurements_view.dart`

7. Bundle or remove the declared Inter font.
   - Theme references Inter, but `pubspec.yaml` does not define bundled fonts.

8. Add localization strategy.
   - UI currently mixes English, Slovenian, and hard-coded strings.

### WearOS App

1. Render the macro overview content that is currently passed into `OneUiPillCard`.
2. Move active workout state and current exercise to the top of watch workflows.
3. Add confirmation/undo for destructive workout actions.
4. Increase small controls to Wear-friendly target sizes.
5. Add accessibility labels to icon-only and symbolic controls.
6. Replace emoji-like symbols with consistent vector icons.
7. Make sync animation reflect real sync state.
8. Add ambient/AOD handling for timers and infinite animations.
9. Request notification permission at a contextual moment.

## Test and Coverage Gaps

Current gaps:

- No meaningful Wear unit tests were discovered during Gradle verification.
- Flutter widget tests are minimal.
- No golden tests for key phone layouts.
- No semantic accessibility tests for custom controls.
- No large-text or high-contrast test coverage.
- No multi-size validation for phone, tablet, foldable, and Wear round/square displays.
- No cross-language contract test suite for Dart/Kotlin Wear payloads.
- No database migration tests proving foreign key and cascade behavior.
- No sync failure/retry/conflict tests for cloud or phone-watch sync.

Recommended additions:

- Contract tests for every Wear payload type in Dart and Kotlin.
- Drift transaction and migration tests.
- Repository delete tests that assert no orphan rows remain.
- Health service tests for denied permission, missing data, partial data, and overlapping sleep.
- Notification scheduling tests around timezone and exact alarm failure.
- Widget/golden tests for onboarding, active workout, dashboard, nutrition, and measurements.
- Wear Compose UI tests for active workout, set logger, nutrition, fasting, and media controls.

## Suggested Remediation Order

### Phase 1: Security and Trust

- Rotate the Gemini API key.
- Remove embedded secrets from the client.
- Move sensitive auth/session storage out of SharedPreferences.
- Disable or tightly configure Android backup for sensitive state.
- Remove synthetic health measurements.

### Phase 2: Data Integrity

- Re-enable database foreign keys or implement equivalent durable cascade logic.
- Repair existing orphan risks.
- Snapshot nutrition values at log time.
- Fix progress photo persistence.

### Phase 3: Sync Correctness

- Replace fake cloud sync with real acknowledgement semantics or remove claims.
- Redesign phone-Wear session identity and revision model.
- Make Wear apply transactional.
- Fix dedupe-after-success behavior.
- Add cross-device contract and failure tests.

### Phase 4: Release Hygiene

- Fix failing Flutter snapshot tests.
- Fix Android RemoteViews lint errors.
- Fail release builds when signing config is missing.
- Add timeout/error handling to external API clients.
- Clean up analyzer warnings that obscure real issues.

### Phase 5: UI/UX Hardening

- Fix destructive action flows.
- Add accessibility semantics.
- Improve Wear tap targets and active-workout priority.
- Add adaptive phone/tablet layouts.
- Fix contrast and typography/font configuration.
- Add localization groundwork.

## Manual Device Validation Still Needed

The audit did not include emulator or physical-device visual validation.

Before release, test:

- Phone widths: 320dp, 360dp, 430dp.
- Landscape phone layouts.
- Foldable/tablet layouts.
- Text scaling: 1.3x and 2.0x.
- Bold text and high contrast.
- TalkBack/VoiceOver navigation.
- Wear round displays from 40mm to 47mm.
- Wear square displays.
- Wear rotary/bezel behavior.
- Wear AOD/ambient mode.
- Bright outdoor watch use.
- Damp-hand/glove interaction during workouts.

## Final Verdict

The app has a strong product foundation, but the current build should be treated as pre-release quality. The most important fixes are not cosmetic. They protect user trust: real data, secure credentials, durable history, and reliable phone-watch workout state.

Once the release blockers and Wear sync issues are fixed, the UI/UX work becomes much more valuable because it will be polishing a trustworthy core instead of making unstable behavior look finished.
