---
phase: 10-assisted-rep-tracking
plan: 03b
type: execute
wave: 3
depends_on: ["10-01", "10-02", "10-03a"]
files_modified:
  - lib/features/reps/domain/rep_suggestion.dart
  - lib/features/reps/data/rep_capture_service.dart
  - lib/features/reps/data/phone_motion_source.dart
  - pubspec.yaml
  - test/rep_capture_service_test.dart
autonomous: true
requirements: [REP-02, REP-04]
user_setup: []

must_haves:
  truths:
    - "The proposed rep count always equals the Dart detector's output — provisionalCount from the watch never changes it, and the two counts are never averaged"
    - "A provisional-vs-authoritative disagreement greater than 1 rep lowers the confidence band by exactly one step and is surfaced as such"
    - "The raw sample buffer is empty after detection completes, asserted through the service's own accessor rather than assumed"
    - "Capture end with zero batches yields TrackerState.manual with a stated reason, never a zero-rep suggestion"
    - "The phone motion source refuses to start unless RepTrackingSettings.phonePlacement is non-null"
    - "The 5-minute cap and the 15 % battery gate are enforced on the phone source and proven with a fake clock and a fake battery level"
  artifacts:
    - path: "lib/features/reps/domain/rep_suggestion.dart"
      provides: "TrackerState, ConfidenceBand and the immutable RepSuggestion value object 10-04 and 10-05 consume"
      contains: "class RepSuggestion"
    - path: "lib/features/reps/data/rep_capture_service.dart"
      provides: "bridge callback registration, seq-ordered batch assembly, detection, and in-memory-only sample handling"
      contains: "RepDetector.detect"
    - path: "lib/features/reps/data/phone_motion_source.dart"
      provides: "phone-local sensors_plus source with the placement gate, the battery gate and the 5-minute cap"
      contains: "phonePlacement"
    - path: "test/rep_capture_service_test.dart"
      provides: "fake-bridge coverage of ordering, gaps, discard, the provisional divergence rule, the cap and the battery gate"
      contains: "provisionalCount"
  key_links:
    - from: "lib/features/reps/data/rep_capture_service.dart"
      to: "lib/features/reps/domain/rep_detector.dart"
      via: "RepDetector.detect over the reassembled MotionTrace — the single authoritative count"
      pattern: "RepDetector\\.detect"
    - from: "lib/features/reps/data/rep_capture_service.dart"
      to: "lib/features/reps/domain/rep_suggestion.dart"
      via: "emits RepSuggestion and a TrackerState stream"
      pattern: "RepSuggestion\\("
    - from: "lib/features/reps/data/rep_capture_service.dart"
      to: "android/app/src/main/kotlin/com/ams/herculex/PhoneWearListenerService.kt"
      via: "WearSyncService callbacks on the three /herculex/reps/* message paths from 10-03a"
      pattern: "capture_start|samples|capture_end"
    - from: "lib/features/reps/data/phone_motion_source.dart"
      to: "lib/features/reps/data/rep_tracking_repository.dart"
      via: "settings().phonePlacement is the null-guard the source refuses to start without (REP-02)"
      pattern: "phonePlacement"
    - from: "lib/features/reps/data/phone_motion_source.dart"
      to: "lib/features/reps/domain/motion_sample.dart"
      via: "emits the identical MotionTrace shape as the wrist source, so detection is source-agnostic"
      pattern: "MotionTrace"
---

<objective>
The Dart half of capture: reassemble the watch's batched samples into a `MotionTrace`, run the single authoritative detector over it, and emit an immutable `RepSuggestion` — plus a phone-local source that produces the identical trace shape and cannot start without an explicitly chosen placement.

Purpose: this is where the authoritative count is decided and where the "raw samples are discarded at set end" property (REP-04) is actually enforced. It also owns `TrackerState` and `RepSuggestion`, the phase's two central value objects, which 10-04 renders and 10-05 extends.
Output: `rep_suggestion.dart` (the shared contract), `rep_capture_service.dart`, `phone_motion_source.dart`, `sensors_plus` in `pubspec.yaml`, and a fake-bridge test suite that needs no device.

Split from the original 10-03 with 10-03a, which owns everything Kotlin and is verified by Gradle. This half is verified entirely by `flutter test`.

**REP-03 fence, enforced two plans early:** nothing created here may import anything from `lib/features/workouts/`. In particular `wear_workout_sync_service.dart` lives there and holds a `WorkoutsRepository` — read it for its callback-registration idiom, import `lib/features/nutrition/data/wear_sync_service.dart` instead. 10-04 Task 4 adds the static test that catches a violation, but it does not exist yet, so this plan has to hold the line by discipline.
</objective>

<execution_context>
@$HOME/.claude/get-shit-done/workflows/execute-plan.md
@$HOME/.claude/get-shit-done/templates/summary.md
</execution_context>

<context>
@.planning/PROJECT.md
@.planning/ROADMAP.md
@.planning/STATE.md
@.planning/phases/10-assisted-rep-tracking/10-CONTEXT.md
@.planning/phases/10-assisted-rep-tracking/10-03a-PLAN.md
</context>

<interfaces>
<!-- Consumed from 10-02 -->
```dart
enum RepMovement { pullUp, dip }                                  // rep_movement.dart
class MotionSample { final int tMs; final double x, y, z; }       // motion_sample.dart
class MotionTrace { final List<MotionSample> samples; final String sensorType;
                    MotionTrace resampled({int hz = 50}); }
class RepDetectionResult { final int repCount; final List<double> perRepConfidence;
                           final double setConfidence; final List<int> cyclePeriodsMs;
                           final List<double> cycleAmplitudes; final bool missedRepSuspected; }
class RepDetector { static RepDetectionResult detect(MotionTrace t, {RepDetectorConfig config}); }
class RepFeatures { factory RepFeatures.fromResult(RepDetectionResult r);
                    Map<String, dynamic> toJson(); }               // rep_features.dart
```

<!-- Consumed from 10-03a: the wire payloads this service parses -->
```
/herculex/reps/capture_start : { captureId, exerciseSlug, sensorType, startedAtMs }
/herculex/reps/samples       : { captureId, seq, sensorType, samples: [{tMs,x,y,z}] }
/herculex/reps/capture_end   : { captureId, endedAtMs, batchCount, stoppedReason,
                                 provisionalCount }   // NON-AUTHORITATIVE
```

<!-- Published by THIS plan. 10-04 renders it, 10-05 extends the RPE path. Full field list is the contract. -->
```dart
// lib/features/reps/domain/rep_suggestion.dart
enum TrackerState { disabled, ready, tracking, countOnly, manual }
enum ConfidenceBand { high, medium, low }   // ordered; lowerByOne() steps high->medium->low->low

@immutable
class RepSuggestion {
  final String captureId;
  final String exerciseSlug;
  final RepMovement movement;
  final String source;              // 'wrist' | 'phone'
  final String? placement;          // 'pocket_front' | 'armband' | null
  final String sensorType;          // 'linear_acceleration' | 'accelerometer'

  final int proposedReps;           // AUTHORITATIVE — always RepDetectionResult.repCount
  final int? provisionalCount;      // NON-AUTHORITATIVE watch count; display/diagnostic only
  final bool provisionalDisagrees;  // (provisionalCount - proposedReps).abs() > 1

  final double setConfidence;       // 0-1, from the detector
  final ConfidenceBand confidenceBand; // after any disagreement penalty
  final bool missedRepSuspected;
  final int missedBatches;
  final int sampleCount;
  final double coverageRatio;       // received batches / expected batchCount

  final Map<String, dynamic>? featuresJson;   // RepFeatures.toJson(), for recordObservation
  RepFeatures? get features;                 // derived: RepFeatures.fromJson(featuresJson),
                                             // null when featuresJson is null or its 'v' mismatches.
                                             // 10-05 consumes THIS, not featuresJson.
  final TrackerState state;
  final String? stateReason;        // non-null whenever state is manual or countOnly
}
```
</interfaces>

<tasks>

<task type="auto">
  <name>Task 1: Publish the RepSuggestion and TrackerState contract</name>
  <read_first>
    .planning/phases/10-assisted-rep-tracking/10-CONTEXT.md ("Confidence and fallback states" — the five-state `TrackerState` table is decided there; "Where detection runs" — the >1-rep disagreement rule)
    lib/features/reps/domain/rep_movement.dart (10-02 output — `RepMovement` is imported, never redeclared)
    lib/features/analytics/domain/training_snapshot.dart (the repo idiom for an immutable domain value object with derived getters)
  </read_first>
  <files>lib/features/reps/domain/rep_suggestion.dart</files>
  <action>
Create `lib/features/reps/domain/rep_suggestion.dart` declaring `enum TrackerState { disabled, ready, tracking, countOnly, manual }` — the exact five states from 10-CONTEXT's table, no more and no fewer — and `enum ConfidenceBand { high, medium, low }` with a `ConfidenceBand lowerByOne()` extension stepping `high -> medium -> low -> low` (saturating, never wrapping).

Declare the immutable `RepSuggestion` class with the full field list in this plan's `<interfaces>` block, all `final`, with a `const` constructor and named required parameters. Add a `ConfidenceBand bandFor(double setConfidence)` static helper with fixed thresholds so band derivation lives in exactly one place.

Add a derived getter `RepFeatures? get features => featuresJson == null ? null : RepFeatures.fromJson(featuresJson!);`. **This getter is the contract 10-05 consumes** (`estimate(suggestion.features)`); it returns null both when nothing was captured and when the stored vector's `v` key does not match the current detector version, which is exactly the behaviour 10-05's gate expects. `featuresJson` stays on the class as the raw map 10-04 passes to `recordObservation`.

Document `proposedReps` as **authoritative — always `RepDetectionResult.repCount`** and `provisionalCount` as **non-authoritative, display and diagnostic only, never used to compute `proposedReps`, never averaged with it**. That doc comment is the contract 10-04 relies on when it renders the disagreement notice.

`stateReason` must be non-null whenever `state` is `manual` or `countOnly`; assert this in the constructor. `countOnly` and `manual` are not error states (10-CONTEXT) — nothing in this file may name them errors or failures.

Import only `package:flutter/foundation.dart` (which re-exports `@immutable`) and `rep_movement.dart`/`rep_features.dart`. **Do not import `package:meta/meta.dart`** — `meta` is not a declared dependency in `pubspec.yaml` and referencing it directly trips `depend_on_referenced_packages`, failing this task's own analyze gate. No Drift, no Flutter widgets, no plugins.
  </action>
  <verify>
    <automated>flutter analyze lib/features/reps/domain/rep_suggestion.dart</automated>
  </verify>
  <done>File analyzes clean; `TrackerState` has exactly the five 10-CONTEXT values; `ConfidenceBand.lowerByOne()` saturates at `low`; `grep -c "enum TrackerState" lib/` returns 1; `grep -c "enum RepMovement" lib/features/reps/domain/rep_suggestion.dart` returns 0.</done>
</task>

<task type="auto">
  <name>Task 2: Build the capture service — batch reassembly, authoritative detection, and the divergence rule</name>
  <read_first>
    lib/features/nutrition/data/wear_sync_service.dart (the Dart side of the bridge and its static-callback idiom, `onWatchWorkoutStarted` and friends)
    lib/features/workouts/data/wear_workout_sync_service.dart (lines 39-41 — the three `WearSyncService.onWatchWorkout*` assignments; **read for idiom only**)
    lib/features/reps/domain/rep_detector.dart (10-02 output — `RepDetector.detect` is the only source of `proposedReps`)
    lib/features/reps/domain/motion_sample.dart (10-02 output — `MotionTrace.resampled`)
    lib/features/reps/domain/rep_suggestion.dart (Task 1 output — the emitted contract)
    .planning/phases/10-assisted-rep-tracking/10-03a-PLAN.md (the `<interfaces>` block — the exact wire payload keys this service parses)
    .planning/phases/10-assisted-rep-tracking/10-CONTEXT.md ("Watch-phone disconnect" — never fall back to the provisional count; "Where detection runs" — the >1-rep rule)
  </read_first>
  <files>lib/features/reps/data/rep_capture_service.dart</files>
  <action>
Create `lib/features/reps/data/rep_capture_service.dart` registering `WearSyncService` callbacks for `/herculex/reps/capture_start`, `/herculex/reps/samples` and `/herculex/reps/capture_end`, mirroring the registration shape at `lib/features/workouts/data/wear_workout_sync_service.dart:39-41`.

**Import fence:** that file is read for idiom only. `rep_capture_service.dart` imports `lib/features/nutrition/data/wear_sync_service.dart` (the bridge itself) and **never** `wear_workout_sync_service.dart`, which lives under `lib/features/workouts/` and holds `_workoutsRepository` (line 30). 10-04 Task 4's boundary test bans **any** import from `lib/features/workouts/` across the whole of `lib/features/reps/`; importing it here would break REP-03 two plans later, long after this plan's own gates went green.

Accumulate batches in a private `Map<String, List<_Batch>>` keyed by `captureId`, order by `seq`, and record any missing `seq` as `missedBatches`. A gap must degrade confidence, not be papered over by concatenating across it — and `coverageRatio` is `receivedBatches / batchCount` from the capture-end payload.

On capture end: build a `MotionTrace` from the ordered samples, call `RepDetector.detect(trace, config: RepDetectorConfig.forMovement(movement))` (which resamples to 50 Hz internally), and set `proposedReps = result.repCount`. **`proposedReps` is the detector's output unconditionally.** Read `provisionalCount` from the payload and store it on the suggestion as a non-authoritative field. Compute `provisionalDisagrees = provisionalCount != null && (provisionalCount - proposedReps).abs() > 1`; when true, set `confidenceBand = RepSuggestion.bandFor(result.setConfidence).lowerByOne()` and otherwise `bandFor(result.setConfidence)`. **Never average the two counts, never substitute the provisional one, and never adjust `proposedReps` by any function of `provisionalCount`** (10-CONTEXT "Where detection runs").

Hold raw samples in a private in-memory buffer keyed by `captureId` and **clear that entry as soon as detection completes**, in a `finally` so an exception during detection still discards. No file, no database, no `debugPrint`/`log` line containing a sample value. Expose `int rawBufferSampleCount(String captureId)` (returning 0 for a cleared or unknown id) purely so the discard is a tested property rather than a comment.

Expose a `Stream<TrackerState>` plus the current `stateReason`. Emit `manual` with a stated reason on: capture end with zero batches ("watch was not connected — count not verified"), a battery refusal reported from the watch, and an abort. **Capture end with zero batches must never produce a zero-rep suggestion** — "zero reps detected" and "nothing was captured" are different facts and conflating them is the failure 10-CONTEXT calls out. Never fall back to `provisionalCount` in the manual case.

Attach `RepFeatures.fromResult(result).toJson()` to the suggestion as `featuresJson` so 10-04 can pass it straight to `recordObservation`.
  </action>
  <verify>
    <automated>flutter analyze lib/features/reps/data/rep_capture_service.dart</automated>
  </verify>
  <done>File analyzes clean; `grep -n "RepDetector.detect" lib/features/reps/data/rep_capture_service.dart` shows the single authoritative call; `grep -n "provisionalCount" lib/features/reps/data/rep_capture_service.dart` shows it used only for `provisionalDisagrees` and the stored field, never in a `proposedReps` expression; `grep -cn "average\|(a + b) / 2\|~/ 2" lib/features/reps/data/rep_capture_service.dart` is 0.</done>
</task>

<task type="auto">
  <name>Task 3: Add sensors_plus and the placement-gated phone motion source</name>
  <read_first>
    pubspec.yaml (the dependency block and its existing version-pinning style)
    lib/features/reps/domain/motion_sample.dart (10-02 output — the `MotionTrace` this source must emit identically to the wrist source)
    lib/features/reps/data/rep_tracking_repository.dart (10-01 output — `settings()` and `RepTrackingSettingData.phonePlacement`, the gate)
    lib/features/reps/domain/rep_suggestion.dart (Task 1 output — `TrackerState.manual` and its reason string)
    .planning/phases/10-assisted-rep-tracking/10-CONTEXT.md ("Sensor and sampling" and "Interruption and battery handling")
  </read_first>
  <files>lib/features/reps/data/phone_motion_source.dart, pubspec.yaml</files>
  <action>
Add `sensors_plus` to `pubspec.yaml` under `dependencies`, pinned in the same style as the existing entries. Before adding it, verify the package unconditionally at `https://pub.dev/packages/sensors_plus`: confirm the publisher is `fluttercommunity.dev`, the package is not discontinued, and the version selected is the current stable. There is no RESEARCH.md for this phase, so there is no audit table to consult — the pub.dev check is the whole gate.

Create `lib/features/reps/data/phone_motion_source.dart` implementing the phone-local source with **identical `MotionTrace` output** to the wrist path, so `RepDetector` is source-agnostic: subscribe to `userAccelerometerEventStream()` (linear acceleration equivalent) with `samplingPeriod: SensorInterval.gameInterval`, falling back to `accelerometerEventStream()` with `sensorType: 'accelerometer'` where the linear stream is unavailable, and stamp each sample with a monotonic `tMs` from an injected clock.

**It refuses to start unless `RepTrackingSettings.phonePlacement` is non-null** — placement must be explicitly chosen, never defaulted (REP-02). Return a typed refusal and emit `TrackerState.manual` with the reason; do not throw an untyped exception and do not pick a placement.

Take the clock and a battery-level supplier as constructor-injected collaborators (not `DateTime.now()` and not a static plugin lookup) so both gates are fake-testable. Apply the same **15 % battery refusal** and **5-minute hard cap** as the watch controller: below 15 % the source never subscribes; at 5 minutes it cancels the subscription, keeps what was collected and reports `stoppedReason = 'cap'`. Cancel the stream subscription in a `finally` on every exit path so a refusal or a cap leaves no live subscription.
  </action>
  <verify>
    <automated>flutter pub get &amp;&amp; flutter analyze lib/features/reps/data/phone_motion_source.dart</automated>
  </verify>
  <done>`sensors_plus` resolves; the file analyzes clean; `grep -n "phonePlacement" lib/features/reps/data/phone_motion_source.dart` shows the null guard before any subscription call; the clock and battery supplier are constructor parameters, not static lookups.</done>
</task>

<task type="auto">
  <name>Task 4: Fake-bridge test suite covering ordering, discard, divergence, the cap and the battery gate</name>
  <read_first>
    lib/features/reps/data/rep_capture_service.dart (Task 2 output — `rawBufferSampleCount`, the `TrackerState` stream and the divergence fields being asserted)
    lib/features/reps/data/phone_motion_source.dart (Task 3 output — the injected clock and battery supplier)
    lib/features/reps/domain/rep_suggestion.dart (Task 1 output — `ConfidenceBand` ordering)
    test/rep_detector_test.dart (10-02 output — the fixture-loading helper to reuse for a realistic sample stream)
    test/support/test_database.dart (the repo's fake/in-memory test-harness idiom)
  </read_first>
  <files>test/rep_capture_service_test.dart</files>
  <action>
Create `test/rep_capture_service_test.dart` driving `RepCaptureService` through a **fake bridge** — no device, no Gradle, no plugin channel. Cases:

*Assembly.* In-order batches reconstruct the original trace exactly, sample-for-sample. A dropped `seq` sets `missedBatches` to the number missing, lowers `coverageRatio` below 1.0, and lowers the reported confidence relative to the same trace delivered intact.

*Discard (REP-04).* After detection completes, `rawBufferSampleCount(captureId)` is 0 — assert on the service's own accessor so the discard is a tested property. Assert it is also 0 when detection throws (inject a trace that trips the error path).

*Nothing-captured vs zero reps.* Capture end with zero batches yields `TrackerState.manual` with a non-null `stateReason`, and **no `RepSuggestion` with `proposedReps == 0`** is emitted. Additionally assert the emitted state does not carry `provisionalCount` as the proposed value.

*Provisional divergence (the B5 rule).* (a) Feed a fixture trace the detector counts as 8, with `provisionalCount` set to each of `2`, `8` and `14` in three sub-cases, and assert `proposedReps == 8` in **all three** — the proposed count always equals the Dart detector's output regardless of `provisionalCount`. (b) With `provisionalCount == 8` (agreement), `confidenceBand == RepSuggestion.bandFor(setConfidence)`; with `provisionalCount == 14` (divergence > 1), `confidenceBand == RepSuggestion.bandFor(setConfidence).lowerByOne()` — lowered by **exactly one** step, and `provisionalDisagrees` is true. (c) `provisionalCount == 9` against 8 (divergence of exactly 1) does **not** lower the band, proving the threshold is strictly greater than 1.

*Phone source gates.* Starting the phone source with a null `phonePlacement` returns the typed refusal and emits `manual`; no sensor subscription is created. With the fake battery supplier at 14 %, start is refused and no subscription is created (UAT row 9's automated counterpart). With the fake clock advanced past 5 minutes mid-capture, the subscription is cancelled, collected samples are kept, and `stoppedReason == 'cap'` (UAT row 6's automated counterpart).
  </action>
  <verify>
    <automated>flutter test test/rep_capture_service_test.dart</automated>
  </verify>
  <done>All cases pass; the three `provisionalCount` sub-cases all yield `proposedReps == 8`; a >1 divergence lowers the band by exactly one and a divergence of exactly 1 does not; `rawBufferSampleCount` is 0 after both a successful and a failed detection; the phone source is refused with a null placement and below 15 % battery, and caps at 5 minutes.</done>
</task>

</tasks>

<threat_model>
## Trust Boundaries

| Boundary | Description |
|----------|--------------|
| Native bridge → Dart | Payloads arrive from `PhoneWearListenerService` with a `seq` that may have gaps; malformed or partial input must degrade to `manual`, never to a fabricated count. |
| Raw sample buffer → anywhere else | Samples exist in Dart memory for the duration of detection only. Any path to a file, a log or the database violates REP-04. |
| Provisional count → proposed count | The one place the phase could silently substitute a less-trustworthy number for the authoritative one. |

## STRIDE Threat Register

| Threat ID | Category | Component | Disposition | Mitigation Plan |
|-----------|----------|-----------|-------------|------------------|
| T-10-12 | Spoofing (of authority) | `rep_capture_service.dart` | mitigate | `proposedReps` is unconditionally `RepDetectionResult.repCount`; `provisionalCount` is a documented non-authoritative field used only to compute `provisionalDisagrees`; three test sub-cases assert the count is invariant to it (Tasks 2 and 4). |
| T-10-13 | Information Disclosure | raw sample buffer | mitigate | Buffer cleared in a `finally` on every exit path; `rawBufferSampleCount` asserted 0 after both success and failure; no log statement may contain a sample value (Tasks 2 and 4, REP-04). |
| T-10-14 | Tampering (fabricated data) | capture-end with zero batches | mitigate | Emits `manual` with a stated reason and never a zero-rep suggestion, never a provisional fallback (Tasks 2 and 4). |
| T-10-15 | Elevation of Privilege | `phone_motion_source.dart` | mitigate | Hard null-check on `RepTrackingSettings.phonePlacement` before any subscription; typed refusal, no default placement (Task 3, REP-02). |
| T-10-16 | Denial of Service (battery) | `phone_motion_source.dart` | mitigate | 15 % refusal and 5-minute cap with injected clock/battery, fake-tested (Tasks 3 and 4). |
| T-10-SC | Tampering | `sensors_plus` install | mitigate | The single new dependency in the phase. Task 3 requires an unconditional pub.dev verification (publisher `fluttercommunity.dev`, not discontinued, current stable) before the `pubspec.yaml` edit; `git diff pubspec.yaml` in this plan's verification confirms nothing else was added. |
</threat_model>

<verification>
- `flutter test test/rep_capture_service_test.dart`
- `flutter analyze lib/features/reps/`
- `grep -rn "provisionalCount" lib/features/reps/data/rep_capture_service.dart` — appears only in the parse, the `provisionalDisagrees` comparison and the stored field; never in a `proposedReps` expression.
- `grep -rn "debugPrint\|print(\|log(" lib/features/reps/data/` — no statement interpolating a sample value.
- `git diff pubspec.yaml` — the only added dependency is `sensors_plus`.
</verification>

<success_criteria>
- The proposed count always equals the Dart detector's output; the two counters are never averaged.
- A >1-rep provisional disagreement lowers the confidence band by exactly one step; a disagreement of exactly 1 does not.
- `rep_capture_service` holds zero raw samples after detection, verified by test on both the success and the failure path.
- A watch that never reconnects yields `manual` with a reason, never a zero-rep suggestion and never the provisional count.
- The phone source cannot start without an explicitly selected placement, below 15 % battery, or beyond 5 minutes.
- `TrackerState` and `RepSuggestion` have exactly one declaration each, in `rep_suggestion.dart`.
</success_criteria>

<output>
Create `.planning/phases/10-assisted-rep-tracking/10-03b-SUMMARY.md` when done
</output>
