---
phase: 10-assisted-rep-tracking
plan: 04
subsystem: rep-tracking-ui
tags: [flutter, riverpod, rep-tracking, consent, review-sheet, write-boundary]
requires:
  - "TrackerState/ConfidenceBand/RepSuggestion (10-03b, rep_suggestion.dart)"
  - "RepCaptureService.stateStream/suggestions and PhoneMotionSource.stateStream/captureEnded (10-03b)"
  - "RepTrackingRepository.grantConsent/revokeConsent/setExerciseEnabled/isEnabledFor/recordObservation (10-01)"
  - "eligibleRepSlugs/isEligible/movementFor (10-01, rep_tracking_eligibility.dart)"
provides:
  - "RepTrackingConsentView — the app's only grantConsent() call site, with a required-placement phone gate and a revoke control"
  - "RepTrackerPanel — renders all five TrackerState values, wired per eligible exercise card"
  - "RepReviewSheet — editable, pre-filled review sheet whose only write path is the injected onConfirm callback"
  - "test/rep_tracker_write_boundary_test.dart — the REP-03 static gate over the whole of lib/features/reps/"
  - "RepCaptureService.buildPhoneSuggestion/activeCaptureIdFor — the phone-trace-to-detection path 10-03b left open"
affects:
  - "10-05 will read RepSuggestion.features from the same suggestion this plan's panel/sheet already carry, and will add the suggested-RPE field the sheet currently leaves empty"
tech-stack:
  added: []
  patterns:
    - "App-lifetime singleton providers (repCaptureServiceProvider/phoneMotionSourceProvider) instead of per-widget instances, so a capture in flight survives a screen rebuild"
    - "Two independent StreamControllers (suggestions, stateStream) notified via separate microtasks — a listener on one must never assume it runs before or after a listener on the other for the same logical event; RepTrackerPanel resets its 'armed' gate on a set-identity change (didUpdateWidget) rather than from inside either listener, to avoid exactly that race"
    - "onComplete interception: the existing per-set completion tap opens RepReviewSheet only when a pending suggestion exists for that exact set entry id; the set is written (via onConfirm) only after a successful Save, never on dismissal"
key-files:
  created:
    - lib/features/reps/presentation/rep_tracking_consent_view.dart
    - lib/features/reps/presentation/rep_tracker_panel.dart
    - lib/features/reps/presentation/rep_review_sheet.dart
    - test/rep_tracker_write_boundary_test.dart
    - test/rep_tracker_widget_test.dart
    - test/rep_review_sheet_e2e_test.dart
  modified:
    - lib/features/reps/presentation/rep_tracking_providers.dart
    - lib/features/reps/data/rep_tracking_repository.dart
    - lib/features/reps/data/rep_capture_service.dart
    - lib/features/workouts/presentation/active_exercise_card.dart
    - lib/app/router.dart
    - lib/features/profile/presentation/profile_view.dart
decisions:
  - "All workouts-side wiring landed in active_exercise_card.dart, not active_workout_view.dart as the plan's files_modified predicted — the per-set completion handler (the updateSet call site the review sheet wraps) and the exercise options menu both live there; active_workout_view.dart only builds the list of ActiveExerciseCard widgets and has no per-set logic at all."
  - "RepCaptureService gained buildPhoneSuggestion, answering 10-03b's explicitly-left-open question of how a phone-sourced MotionTrace reaches RepDetector. It mirrors the wrist bridge's suggestion-building logic but with provisionalCount always null (there is no on-device provisional count for a phone capture)."
  - "The phone-source battery gate has no real battery-level plugin behind it: pubspec.yaml is untouched per T-10-SC, so the production BatteryLevelSupplier always reports 100%. The refusal logic itself is fully implemented and tested (from 10-03b); only the live reading is a stand-in until a future plan adds a battery plugin."
  - "RepTrackerPanel's Start/Stop button drives PhoneMotionSource.start()/stop() directly for the phone source. For the wrist source there is nothing to call — a real wrist capture starts when the watch's own /herculex/reps/capture_start message arrives, driven by the user's tap on the watch itself (10-03a's own UI). The phone-side tap only 'arms' the panel to start reflecting whichever capture the shared RepCaptureService reports next, and Stop aborts the matching in-flight capture via the new RepCaptureService.activeCaptureIdFor."
  - "test/rep_tracker_write_boundary_test.dart's fourth forbidden token is db.setEntries (the actual SetEntries table object), not the plan's literal db.update( — the latter would also flag rep_tracking_repository.dart's own legitimate drift .update() calls against its own local-only tables."
  - "10-02 Task 5's recorded fixture corpus (test/fixtures/motion/, accuracyFixtures) does not exist yet; Task 5's widget/e2e tests substitute a deterministic synthetic trace generator, following the exact precedent test/rep_capture_service_test.dart (10-03b) already set for the same gap."
metrics:
  duration: ~2.5 hours
  tasks: 5
  files_created: 6
  files_modified: 6
  tests_added: 10
  completed: 2026-08-14
---

# Phase 10 Plan 04: Assisted Rep Tracking — Consent, Live Tracker Panel, Review Sheet Summary

The user-facing surface: a dedicated consent screen that is the only way to turn assisted rep tracking on, a per-exercise opt-in that degrades to a consent link rather than a silent no-op, a live tracker panel rendering every `TrackerState`, and an editable review-and-confirm sheet whose only route to the database is a callback the workouts feature injects — plus the widened static test that makes "the tracker cannot write a set" a checked property.

## What Was Built

**Task 1 — consent screen and per-exercise opt-in (`2726ded`).** `rep_tracking_consent_view.dart` is the app's only `grantConsent()` call site (`grep -rn "grantConsent" lib/` confirms exactly one call site). It explains what is measured/where it's processed/what is kept/what it never does, offers a wrist-or-phone sensor-source picker, and for `phone` keeps the primary action disabled until an explicit `pocket_front`/`armband` placement is chosen — never defaulted. A revoke control states up front that it deletes all stored calibration data before confirming. Reachable from Profile → "Assisted Rep Tracking" and registered at `/rep-tracking-consent`. `RepTrackingRepository` gained `updateSensorPreferences` (a writer for `defaultSource`/`phonePlacement` that didn't exist before this plan) and `rep_tracking_providers.dart` gained the consent form's local `StateNotifier`.

**Task 2 — tracker panel rendering all five `TrackerState` values (`22881ec`).** `rep_tracker_panel.dart` gives every state an explicit branch: `disabled` returns `SizedBox.shrink()` (nothing rendered, no padding); `ready` shows a "Start tracking" button with no auto-start anywhere (no `initState` call to a start method, no stream-driven auto-start — the button's `onPressed` is the only caller); `tracking` shows a spinner and a Stop button; `countOnly`/`manual` use the same neutral chrome (never the error/warning treatment) and show the proposed count / stated reason respectively. The panel imports nothing from `lib/features/workouts/` and receives everything via constructor parameters. `RepCaptureService` gained `buildPhoneSuggestion` and `activeCaptureIdFor` — see Deviations.

**Task 3 — review sheet with an injected confirm callback (`b3846c9`).** `rep_review_sheet.dart` declares `RepConfirmCallback = Future<void> Function(int reps, int? rpeX10)` and imports nothing from `lib/features/workouts/` — not `data/`, not `domain/`, not `presentation/`. The rep count is an editable, pre-filled `TextField`; a divergence banner shows when `provisionalDisagrees` is true; a "how this was measured" `ExpansionTile` surfaces source/placement/sensor/coverage/calibration. Saving reads whatever is currently in the fields, awaits `onConfirm`, and only then calls `recordObservation` — if `onConfirm` throws, no observation is recorded. Dismissing (barrier tap or Cancel) calls neither. All of Task 1's per-exercise toggle, Task 2's panel insertion and this task's review-sheet interception landed in `active_exercise_card.dart` — see Deviations for why.

**Task 4 — the write-boundary gate widened to the whole feature (`fc386ba`).** `test/rep_tracker_write_boundary_test.dart` recursively reads every `.dart` file under `lib/features/reps/`, strips `//`-prefixed comment lines, and asserts none contains `WorkoutsRepository`, `updateSet`, `SetEntriesCompanion` or a raw `db.setEntries` table reference, and that no import's path contains a `workouts/` path segment — checked with a regex robust to this codebase's relative-import convention (`'../../workouts/...'`), not just the plan's literal `features/workouts/` substring, which only matches a `package:` import style this codebase doesn't use. Verified to fail with a named file/line when a deliberate `import '../../workouts/presentation/active_workout_view.dart';` is added to a reps file.

**Task 5 — widget suite and the fixture-driven no-write e2e test (`cbe605b`).** `test/rep_tracker_widget_test.dart` covers `disabled` (zero-size subtree), `ready` (start control, no count), `countOnly` (count + no-RPE note, driven through a real `RepCaptureService` with a dropped batch and a >1-rep provisional disagreement to force the band to `low`), `manual` (reason text from an unknown-capture-id `capture_end`), consent revoked mid-session making the panel disappear on the next build, and the review sheet passing the *edited* value to `onConfirm`. `test/rep_review_sheet_e2e_test.dart` drives one synthetic wrist trace through `RepCaptureService` end to end into `RepReviewSheet`, asserting dismissal calls `onConfirm` zero times with zero `rep_set_observations` rows, and that saving after an edit calls `onConfirm` once with the edited value and writes exactly one observation whose `detectedReps` is the fixture count and `confirmedReps` is the edit. A second sub-case drives a phone/armband synthetic trace through `RepCaptureService.buildPhoneSuggestion` and asserts the "how this was measured" expander shows `armband`.

## Verification

| Check | Result |
|---|---|
| `flutter test test/rep_tracker_widget_test.dart test/rep_tracker_write_boundary_test.dart test/rep_review_sheet_e2e_test.dart` | 10 tests, 0 failures |
| `flutter analyze` (whole project) | 0 errors/warnings introduced by this plan (pre-existing `active_workout_view.dart` unused-field warnings and lint infos are untouched by this plan) |
| `flutter test` (existing rep_* suites: capture, features, local-only, eligibility, repository) | 38 tests, all green, no regressions |
| `grep -rn "updateSet\|WorkoutsRepository" lib/features/reps/` | 2 hits, both doc-comment prose naming the fenced symbols, no code reference |
| `grep -rln "features/workouts" lib/features/reps/` | 3 hits, all doc-comment prose; the static test itself (not a grep) is the enforced check |
| `grep -rn "grantConsent" lib/ --include=*.dart` | exactly one call site (`rep_tracking_consent_view.dart`) |
| `git diff --stat pubspec.yaml` | empty |
| Deliberately added `import '../../workouts/presentation/active_workout_view.dart';` to a reps file | `rep_tracker_write_boundary_test.dart` fails, naming the file and line |

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 3 - Blocking] The plan's integration target file (`active_workout_view.dart`) has no per-set logic at all**
- **Found during:** Task 2, confirmed reading the actual file before any edit
- **Issue:** The plan's `files_modified` and Task 2/3 action text name `active_workout_view.dart` as where the tracker panel is inserted and where the review sheet wraps "the existing user-driven completion handler." Reading the file: it only builds the `ReorderableListView` of `ActiveExerciseCard` widgets — it has no per-set-row UI, no `updateSet` call, and no exercise options menu. All three live in `active_exercise_card.dart` (`_SetRow`'s `onComplete` closure at what was line 244, and `_showMenu`'s bottom sheet).
- **Fix:** Wired the per-exercise toggle (Task 1), the `RepTrackerPanel` insertion (Task 2) and the review-sheet interception of the set-completion tap (Task 3) into `active_exercise_card.dart` instead. The onComplete closure now opens `RepReviewSheet` when a pending suggestion exists for the tapped set entry; the set is written only after a successful Save (tracked via a locally captured `saved` flag so a dismissal correctly skips both the write and the rest-timer/advance logic that follows a genuine completion).
- **Files modified:** `lib/features/workouts/presentation/active_exercise_card.dart` (not `active_workout_view.dart`, which is untouched)
- **Commit:** `b3846c9` (bundled with Task 3; the panel insertion and per-exercise toggle from Tasks 1–2 are causally linked edits to the same widget tree and landed in the same file across those task commits' history — see the individual task commits for the incremental diffs)

**2. [Rule 2 - Missing critical] `RepTrackingRepository` had no writer for the sensor-source/placement fields the consent screen needs**
- **Found during:** Task 1
- **Issue:** `RepTrackingSettings.defaultSource`/`.phonePlacement` exist in the schema (10-01) but nothing ever wrote them — `grantConsent` only touches `consentGrantedAt`/`consentVersion`. Without a writer, the consent screen's sensor-source/placement picker would have nowhere to persist its choice.
- **Fix:** Added `RepTrackingRepository.updateSensorPreferences({required source, placement})`, following the same insert-or-update-singleton pattern `grantConsent` already uses. Called immediately after `grantConsent` from the consent screen, never defaulting a null placement itself.
- **Files modified:** `lib/features/reps/data/rep_tracking_repository.dart`
- **Commit:** `2726ded`

**3. [Rule 2 - Missing critical] Nothing connected a phone-sourced trace to `RepDetector` — 10-03b's summary flagged this as an open question for this plan**
- **Found during:** Task 2
- **Issue:** `RepCaptureService` only ever builds a `RepSuggestion` from the wrist bridge's batched messages; `PhoneMotionSource` produces a `MotionTrace` via its `captureEnded` stream but nothing turned that into a `RepSuggestion`. 10-03b's summary explicitly named this as left for 10-04 to decide.
- **Fix:** Added `RepCaptureService.buildPhoneSuggestion(captureId, exerciseSlug, trace, placement, stoppedReason)`, mirroring the wrist path's suggestion-building logic (same authoritative `RepDetector.detect` call, same band-lowering-per-cause rule for a non-`'user'` `stoppedReason`) but with `provisionalCount` always null — there is no on-device provisional count for a phone capture. `RepTrackerPanel` calls it from its `PhoneMotionSource.captureEnded` listener.
- **Files modified:** `lib/features/reps/data/rep_capture_service.dart`
- **Commit:** `22881ec`

**4. [Rule 1 - Bug] A cross-stream race could leave the tracker panel stuck showing "Tracking…" forever**
- **Found during:** Task 5, while writing the `countOnly` widget test (`pumpAndSettle` timed out)
- **Issue:** `RepCaptureService.suggestions` and `.stateStream` are two independent `StreamController`s. The panel's suggestion listener reset an `_armed` gate to `false` before the state listener (which used the same gate to decide whether to apply an incoming `TrackerState`) had necessarily run — Dart's microtask ordering meant the suggestion listener's `_armed = false` sometimes landed first, causing the state listener to silently drop the terminal `countOnly`/`manual` transition. The panel then stayed on `tracking`'s indeterminate spinner indefinitely.
- **Fix:** The suggestion/phone-end listeners no longer reset `_armed`. Instead, `didUpdateWidget` resets `_armed`/`_captureState`/`_reason`/`_lastProposedReps` to a fresh "ready" only when the caller moves the panel on to a different `setEntryId` — the actual signal that a new set is being tracked.
- **Files modified:** `lib/features/reps/presentation/rep_tracker_panel.dart`
- **Commit:** `22881ec` (fix landed before the Task 2 commit was made; no separate commit needed)

**5. [Rule 1 - Bug] The plan's literal `db.update(` write-boundary token would have flagged the reps repository's own legitimate writes**
- **Found during:** Task 4, first test run
- **Issue:** `rep_tracking_repository.dart` legitimately calls `_db.update(_db.repTrackingSettings)`/`_db.update(_db.repTrackingExercisePrefs)` against its own local-only tables — this is not a REP-03 violation, but the plan's literal `db.update(` token matched it anyway (`_db.update(` contains `db.update(` as a substring), failing the test against the plan's own known-legitimate code.
- **Fix:** Scoped the fourth forbidden token to `db.setEntries` (the actual table object backing the set write path) instead of the generic drift `.update(` method name, keeping the check's intent (catch a raw drift write to the sets table bypassing `WorkoutsRepository`) without false-positiving on the reps feature's own tables.
- **Files modified:** `test/rep_tracker_write_boundary_test.dart`
- **Commit:** `fc386ba`

### Intentional Scope Decisions

- **No real recorded fixture corpus exists yet.** 10-02 Task 5 (recording real pull-up/dip traces on a watch and pocketed phone) is still a pending human checkpoint. Task 5's widget and e2e tests substitute a deterministic synthetic trace generator, matching the exact precedent `test/rep_capture_service_test.dart` (10-03b) already established for the same gap. **REP-06 is deliberately left unchecked in REQUIREMENTS.md** — the never-auto-complete guarantee this plan proves is real and automated, but the "recorded motion traces... verify counting accuracy" clause needs actual recorded fixtures, not synthetic ones.
- **The phone battery gate has no real reading behind it.** `pubspec.yaml` is untouched (T-10-SC forbids a new dependency this plan), so `phoneMotionSourceProvider`'s production `BatteryLevelSupplier` always returns 100. The refusal logic itself (from 10-03b) is fully implemented and tested; only the live battery percentage is a stand-in for a future plan to wire a real plugin.
- **REP-01 and REP-04 were already marked complete by 10-01** and are unaffected by this plan. **REP-02 and REP-03 are now marked complete** — the consent screen's required-placement gate (REP-02) and the write-boundary test plus the review sheet's callback-only write path (REP-03) are both fully implemented and verified end to end. **REP-05 and REP-06 remain open** (10-05 and the pending fixture-recording checkpoint respectively).

## Known Stubs

- The "live count" during `TrackerState.tracking` is a spinner, not a running number — `RepCaptureService`/`PhoneMotionSource` expose no incremental sample-count or provisional-tick stream during an in-progress capture (10-03a's Kotlin `provisionalRepCount` only reaches Dart as one value on `capture_end`, not as a live stream). The count only ever appears once capture ends, in `countOnly`/`manual` or directly in the review sheet. Documented in `rep_tracker_panel.dart`'s tracking-view comment; a future plan would need a new bridge message to make this a true live count.
- `phoneMotionSourceProvider`'s battery reading is hardcoded to 100% (see Deviations) — the 15% refusal path is real code but currently unreachable in production.

## Threat Flags

None beyond what the plan's own threat register already covers — all five registered threats (T-10-17 through T-10-21) are mitigated by the artifacts this plan builds:

| Threat | Mitigation | Evidence |
|---|---|---|
| T-10-17 (elevation via write-path reference) | Widened static test bans the four write-path symbols and any `workouts/` import across the whole feature directory | `test/rep_tracker_write_boundary_test.dart`, both groups passing plus the deliberate-violation check |
| T-10-18 (tampering via the review sheet) | `onConfirm` is the sheet's only write route; dismissal calls neither it nor `recordObservation`, proven end to end from a fake repository | `test/rep_review_sheet_e2e_test.dart` dismissal assertions |
| T-10-19 (spoofed authority in the review sheet display) | The sheet always shows `proposedReps` with the already-lowered `confidenceBand`; `provisionalCount` never renders as the proposal | `rep_review_sheet.dart`'s divergence banner, `_ConfidenceBadge` |
| T-10-20 (elevation via consent gating) | Exactly one `grantConsent` call site; the per-exercise menu tile degrades to a consent link, never a no-op; `disabled` renders nothing | `_RepTrackingMenuTile`, `RepTrackerPanel`'s `effectiveState` gate |
| T-10-21 (phone placement) | Consent screen's primary action stays disabled until a placement is chosen for the phone source, with no default | `rep_tracking_consent_view.dart`'s `RepConsentFormState.canSubmit` |
| T-10-SC (package installs) | No dependency added; `pubspec.yaml` untouched | `git diff --stat pubspec.yaml` empty |

## Notes for the Next Plan

- **10-05** should read `RepSuggestion.features` from the same `suggestion` object `RepTrackerPanel`/`RepReviewSheet` already carry, and will need to add the suggested-RPE value the sheet currently always leaves empty (`suggestedRpeX10: null` in the `recordObservation` call inside `rep_review_sheet.dart`) once its LOO gate passes.
- **A real recorded fixture corpus is still the actual REP-06 gate.** The moment 10-02 Task 5 (or its 10-06 in-app-recording successor) produces `test/fixtures/motion/pullup_wrist_clean_8reps` and `test/fixtures/motion/pullup_phone_armband_8reps`, `test/rep_review_sheet_e2e_test.dart` should be repointed at them via `accuracyFixtures` instead of the synthetic generator, and REP-06 checked off.
- **The tracker panel currently has no true live count during `tracking`** — see Known Stubs. If UAT surfaces this as a real gap, it needs a new incremental bridge message (a live tick, not just the terminal payload), which is out of this plan's scope.
- **Battery gate is a stub in production** until a battery-level plugin is added — see Known Stubs and T-10-SC.

## Self-Check: PASSED

All six created files exist on disk (`rep_tracking_consent_view.dart`, `rep_tracker_panel.dart`, `rep_review_sheet.dart`, `rep_tracker_write_boundary_test.dart`, `rep_tracker_widget_test.dart`, `rep_review_sheet_e2e_test.dart`); all six modified files carry the changes. All five task commits (`2726ded`, `22881ec`, `b3846c9`, `fc386ba`, `cbe605b`) are present in `git log`.
