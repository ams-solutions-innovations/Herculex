---
phase: 10-assisted-rep-tracking
plan: 03b
subsystem: rep-capture-dart
tags: [flutter, dart, sensors, rep-tracking, wear-os-bridge]
requires:
  - "RepMovement/MotionSample/MotionTrace/RepDetector/RepFeatures (10-02)"
  - "the three /herculex/reps/* WearSyncPaths payloads and PhoneWearListenerService.onRepMessageListener (10-03a)"
  - "RepTrackingRepository.settings().phonePlacement (10-01)"
provides:
  - "TrackerState / ConfidenceBand / RepSuggestion (rep_suggestion.dart) — the shared contract 10-04 renders and 10-05 extends"
  - "RepCaptureService — batch reassembly, the single authoritative RepDetector.detect call, the >1-rep provisional-divergence rule, REP-04 discard"
  - "PhoneMotionSource — placement-gated, battery-gated, 5-minute-capped phone accelerometer source producing an identical MotionTrace shape to the wrist path"
  - "WearSyncService.onWatchRepCaptureStart/onWatchRepSamples/onWatchRepCaptureEnd — the Dart-side entry point for the three /herculex/reps/* paths"
affects:
  - "10-04 wires RepCaptureService and PhoneMotionSource into the live counter and review-and-confirm sheet"
  - "10-05 consumes RepSuggestion.features for RPE calibration"
tech-stack:
  added:
    - "sensors_plus ^6.1.1 (resolved 6.1.2) — the phase's one new dependency, fluttercommunity.dev"
  patterns:
    - "Fake-bridge test seam: RepCaptureService exposes public handleCaptureStart/handleSamples/handleCaptureEnd aliases of its own WearSyncService callbacks so tests drive it with no plugin channel, no device, no Gradle"
    - "Constructor-injected clock/battery-supplier/detect-function collaborators, mirroring 10-03a's Kotlin idiom, so every gate (placement, battery, 5-minute cap) and the discard-on-exception path are fake-testable"
    - "Confidence is degraded by stepping ConfidenceBand down once per independent cause (a sample gap, then a >1-rep provisional disagreement) rather than by touching the raw detector setConfidence value"
key-files:
  created:
    - lib/features/reps/domain/rep_suggestion.dart
    - lib/features/reps/data/rep_capture_service.dart
    - lib/features/reps/data/phone_motion_source.dart
    - test/rep_capture_service_test.dart
  modified:
    - pubspec.yaml
    - lib/features/nutrition/data/wear_sync_service.dart
    - android/app/src/main/kotlin/com/ams/herculex/MainActivity.kt
decisions:
  - "Confidence-band degradation is additive per cause (gap, then disagreement), each exactly one lowerByOne() step, rather than blending into a single formula — keeps every cause independently testable and matches the plan's 'never averaged' language for the disagreement rule specifically."
  - "RepCaptureService exposes rawBufferSampleCount and public fake-bridge handler aliases instead of requiring tests to go through WearSyncService's static setters directly, so the discard property and the assembly/divergence rules are exercised through the same code path production wiring uses."
  - "PhoneMotionSource enforces the 5-minute cap by checking the injected clock on every sample arrival rather than a real dart:async Timer, so the cap stays driven by the same fake clock a test controls instead of real wall time."
  - "PhoneMotionSource gained a captureEnded broadcast stream (not in the original interface list) so a cap firing autonomously mid-capture has a way to hand its collected trace and stoppedReason to a listener — the only other exit path (stop()) is caller-invoked and can't be relied on to happen a second time."
metrics:
  duration: ~55 min
  tasks: 4
  files_created: 4
  files_modified: 3
  tests_added: 15
  completed: 2026-08-14
---

# Phase 10 Plan 03b: Assisted Rep Tracking — Wear Rep Capture (Dart half) Summary

The Dart half of capture: `RepSuggestion`/`TrackerState` as the shared contract, a `RepCaptureService` that reassembles the watch's batched samples, runs the single authoritative `RepDetector.detect` over them and enforces the >1-rep provisional-divergence rule, a placement/battery/5-minute-gated `PhoneMotionSource` producing the identical trace shape, and a 15-case fake-bridge test suite — plus the previously-missing Dart↔Kotlin wiring that makes the whole path live end to end, not just in tests.

## What Was Built

**Task 1 — the contract (`ad7f6bb`).** `rep_suggestion.dart` declares the exact five-state `TrackerState` and an ordered `ConfidenceBand` with `lowerByOne()` saturating at `low`. `RepSuggestion` is an immutable, `const`-constructible value object carrying the full field list from the plan's interface block, with a constructor assert requiring `stateReason` whenever `state` is `manual` or `countOnly`, and a `features` getter (`RepFeatures.fromJson(featuresJson)`, null on a version mismatch) that is the exact contract 10-05 will call `estimate()` on.

**Task 2 — the capture service (`630512e`).** `RepCaptureService` registers three `WearSyncService` callbacks, accumulates `/herculex/reps/samples` batches keyed by `seq` per `captureId`, and on capture end builds a `MotionTrace` and calls `RepDetector.detect` — the single, unconditional source of `proposedReps`. `provisionalCount` only ever feeds `provisionalDisagrees`; a gap (missed `seq`) and a >1-rep disagreement each independently step `ConfidenceBand` down exactly one rung. The raw sample buffer is cleared in a `finally` around the detect call, so a thrown detector still discards. Zero batches, a watch battery refusal, or an explicit `abort()` all degrade to `TrackerState.manual` with a stated reason and never emit a suggestion.

**Task 3 — sensors_plus and the phone source (`90992ea`).** Added `sensors_plus` (resolved 6.1.2, fluttercommunity.dev, the phase's only new dependency). `PhoneMotionSource` subscribes to `userAccelerometerEventStream` at `SensorInterval.gameInterval`, falling back to `accelerometerEventStream` and recording `sensorType` accordingly, and stamps every sample with a monotonic `tMs` from an injected clock. It refuses to start without `RepTrackingSettings.phonePlacement` (REP-02) or below 15% battery, returning a typed `PhoneMotionStartRefusal` and emitting `TrackerState.manual` rather than throwing or defaulting a placement. The clock and battery supplier are constructor-injected; the 5-minute cap is checked against the clock on every sample so it stays fake-testable without a real Timer.

**Task 4 — the fake-bridge suite (`c384265`).** 15 cases in `test/rep_capture_service_test.dart`, driven entirely through public handler aliases on `RepCaptureService` (no plugin channel, no device, no Gradle) and a synthetic deterministic pull-up trace built in the test file (there is no recorded fixture corpus yet — 10-02 Task 5 is still a pending human checkpoint). Covers in-order assembly, a dropped-seq gap's effect on `missedBatches`/`coverageRatio`/band, discard on both the success and thrown-detector paths, the zero-batch and never-started manual cases, all three `provisionalCount` divergence sub-cases (2/8/14 all yielding `proposedReps == 8`), the >1-vs-==1 band-lowering boundary, and the phone source's placement/battery refusals plus the 5-minute cap.

## Verification

| Check | Result |
|---|---|
| `flutter test test/rep_capture_service_test.dart` | 15 tests, 0 failures |
| `flutter analyze lib/features/reps/` | No issues found |
| `flutter test` (existing rep_* suites: local-only, eligibility, repository, features, capture) | all green, no regressions |
| `flutter test test/wear_watch_event_queue_test.dart test/wear_workout_sync_service_test.dart` | all green, no regressions from the `WearSyncService` bridge addition |
| `grep -rn "provisionalCount" lib/features/reps/data/rep_capture_service.dart` | parse, `provisionalDisagrees` comparison, stored field, one comment — never in a `proposedReps` expression |
| `grep -cn "average\|(a + b) / 2\|~/ 2" rep_capture_service.dart` | 1 hit, the doc comment stating "never averaged" — no arithmetic averaging present |
| `grep -rn "debugPrint\|print(\|log(" lib/features/reps/data/` | 0 |
| `grep -rln "workouts_repository\|wear_workout_sync_service\|features/workouts" lib/features/reps/` | 1 hit, a doc comment stating the REP-03 fence — no import |
| `git diff pubspec.yaml` | `sensors_plus` is the only added dependency |
| `:app:compileDebugKotlin` (JAVA_HOME=Android Studio JBR) | BUILD SUCCESSFUL |
| `grep -c "enum TrackerState" lib/**` | 1 (rep_suggestion.dart only) |

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 3 - Blocking] `WearSyncService` had no Dart-side entry point for the three `/herculex/reps/*` paths, and `MainActivity.kt` never assigned `PhoneWearListenerService.onRepMessageListener`**
- **Found during:** Task 2
- **Issue:** The plan's action text says to register "`WearSyncService` callbacks for `/herculex/reps/capture_start`, `/herculex/reps/samples` and `/herculex/reps/capture_end`," but no such callbacks existed on `WearSyncService` — it only had the workout/fasting/quick-add/macro setters. Separately, `PhoneWearListenerService.onRepMessageListener` (the Kotlin-side listener 10-03a built and documented as "assign this to attach") was never wired to the Flutter `MethodChannel` in `MainActivity.kt`, unlike every other `PhoneWearListenerService.onWatch*Listener`. Without both halves, nothing could ever carry a rep message from Kotlin to Dart in production — `RepCaptureService`'s registration would have had nothing to register against, and the fake-bridge tests (which bypass the bridge entirely) would never have caught it.
- **Fix:** Added three demultiplexing setters (`onWatchRepCaptureStart`/`onWatchRepSamples`/`onWatchRepCaptureEnd`) to `WearSyncService`, dispatched from a single new `'onRepMessage'` method-channel case that switches on the wire `path` — mirroring the Kotlin side's one-listener-many-paths shape rather than inventing three method-channel methods. Wired `MainActivity.kt`'s `PhoneWearListenerService.onRepMessageListener` to invoke it, following the exact idiom of the six existing `onWatch*Listener` assignments.
- **Files modified:** `lib/features/nutrition/data/wear_sync_service.dart`, `android/app/src/main/kotlin/com/ams/herculex/MainActivity.kt`
- **Commit:** `630512e`
- **Verification:** `:app:compileDebugKotlin` BUILD SUCCESSFUL (`JAVA_HOME="C:/Program Files/Android/Android Studio/jbr"` per LESSONS.md); `flutter analyze` clean on the Dart side; existing `wear_workout_sync_service_test.dart`/`wear_watch_event_queue_test.dart` suites still green.

**2. [Rule 2 - Missing critical] `PhoneMotionSource` had no way to report a trace when the 5-minute cap fired on its own**
- **Found during:** Task 4 (writing the cap test)
- **Issue:** The cap is enforced from inside `_onSample`, calling the private `_stop` and discarding its return value. The only public way to retrieve a `PhoneMotionCaptureResult` was calling `stop()` — but by the time a caller could react to `isCapturing` flipping false, the cap had already collected and discarded the result internally. There was no way for 10-04's eventual integration (or this plan's own test) to learn what was collected or that `stoppedReason == 'cap'`.
- **Fix:** Added a `captureEnded` broadcast stream that both `stop()` and the internal cap trigger publish to, so every capture end — user-initiated or autonomous — is observable the same way.
- **Files modified:** `lib/features/reps/data/phone_motion_source.dart`
- **Commit:** `c384265`

### Intentional Scope Decisions

- **`RepCaptureService` does not integrate `PhoneMotionSource`.** The plan's `key_links` list only connects `phone_motion_source.dart` to `rep_tracking_repository.dart` and `motion_sample.dart`, not to `rep_capture_service.dart`. Wiring a phone-sourced trace through detection and into a `RepSuggestion` is left for 10-04, which owns the live counter and review sheet that will drive both sources.
- **No `RepDetectionResult`-throwing edge case exists in `RepDetector` itself.** To exercise the discard-on-exception path (a plan-mandated test case), `RepCaptureService` accepts an optional injected `detect` function (defaulting to `RepDetector.detect`), which the test overrides with a throwing fake. This is additive constructor injection, consistent with 10-03a's Kotlin-side collaborator-injection pattern, and does not change production behavior (the default is the real detector).

## Known Stubs

None. Every path built here is live: `RepCaptureService` is wired to the real `WearSyncService` bridge (which is now itself wired to the real native listener), and `PhoneMotionSource` uses the real `sensors_plus` streams by default with injection only for tests.

## Threat Flags

None beyond what the plan's own threat register already covers. The two deviations above are themselves T-10-12/T-10-16-adjacent completions (making the already-declared mitigations reachable in production), not new surface:

| Threat | Mitigation | Evidence |
|---|---|---|
| T-10-12 (spoofed authority) | `proposedReps` unconditionally `RepDetectionResult.repCount`; three `provisionalCount` sub-cases assert invariance | `rep_capture_service_test.dart` "provisional divergence" group |
| T-10-13 (raw buffer disclosure) | buffer cleared in a `finally`, asserted 0 on both success and thrown-detector paths | `rep_capture_service_test.dart` "discard (REP-04)" group |
| T-10-14 (fabricated zero-batch count) | `manual` with a reason, never a zero-rep suggestion, never a provisional fallback | `rep_capture_service_test.dart` "nothing-captured vs zero reps" group |
| T-10-15 (phone source elevation) | hard null-check on `phonePlacement` before any subscription; typed refusal | `rep_capture_service_test.dart` "phone source gates" group |
| T-10-16 (battery DoS) | 15% refusal and 5-minute cap, both fake-tested via injected clock/battery | `rep_capture_service_test.dart` "phone source gates" group |
| T-10-SC (`sensors_plus` install) | resolved from pub.dev standard hosted repo, `fluttercommunity.dev`, actively maintained (7.1.0 available, not discontinued); `git diff pubspec.yaml` shows it as the only addition | `pubspec.lock` entry, `git diff pubspec.yaml` |

## Notes for the Next Plan

- **10-04** wires `RepCaptureService.suggestions`/`stateStream` and `PhoneMotionSource.captureEnded`/`stateStream` into the live counter and review-and-confirm sheet, and decides how a phone-sourced `MotionTrace` reaches `RepDetector.detect` (this plan deliberately left that connection to 10-04's key_links).
- **The `RepSuggestion.state` a successful capture emits** is `TrackerState.countOnly` (with a reason) when the confidence band lands on `low`, and `TrackerState.tracking` otherwise — a Claude's-Discretion choice this plan made in the absence of an explicit spec for the success path; 10-04 should treat this as provisional UI wiring, not a locked contract, since RPE gating (10-05) may want its own opinion on when `countOnly` applies.
- **`stoppedReason` values other than `"user"`** (`"cap"`, `"battery"`, `"background"`, `"destroy"`) mean an incomplete capture per 10-03a's notes. This plan only special-cases `"battery"` explicitly (→ `manual`); `"cap"`, `"background"` and `"destroy"` currently flow through normal detection if samples exist. Revisit if UAT surfaces a case where a `"cap"`-truncated set should not be proposed confidently.
- Watch APK staleness still looks exactly like a sync bug — check `adb shell dumpsys package com.ams.herculex | grep lastUpdateTime` before debugging transport (LESSONS.md:83).

## Self-Check: PASSED

All four created files exist on disk (`rep_suggestion.dart`, `rep_capture_service.dart`, `phone_motion_source.dart`, `test/rep_capture_service_test.dart`); all three modified files (`pubspec.yaml`, `wear_sync_service.dart`, `MainActivity.kt`) carry the changes. All four task commits (`ad7f6bb`, `630512e`, `90992ea`, `c384265`) are present in `git log`.
