---
phase: 10-assisted-rep-tracking
plan: 05
subsystem: rep-tracking-calibration
tags: [flutter, riverpod, rep-tracking, ridge-regression, leave-one-out, calibration]
requires:
  - "RepFeatures (10-02, rep_features.dart) — the five-feature vector and its version filter"
  - "RepSetObservationData/observationsFor/recordObservation (10-01, rep_tracking_repository.dart)"
  - "RepSuggestion.features (10-03b) — the derived, version-checked getter this plan consumes"
  - "RepReviewSheet, RepTrackingProviders, test/rep_tracker_widget_test.dart (10-04)"
provides:
  - "RpeEstimator — ridge-regularised OLS on standardised features, single named gate predicate (RpeEstimator.gatePasses), leave-one-out MAE"
  - "CalibrationProfile.fromObservations — per (slug, source, placement, sensorType) profile with version filtering and tuple-keyed invalidation"
  - "RepTrackingRepository.profileFor — cached, invalidated on recordObservation"
  - "calibrationProfileProvider — FutureProvider.family keyed on a CalibrationProfileKey record"
affects:
  - "REP-05 is now fully implemented and testable end to end: no phase currently depends on this plan's output beyond the review sheet it wires into"
tech-stack:
  added: []
  patterns:
    - "Hand-rolled ridge regression + Gauss-Jordan linear solve over dart:math, no new package (T-10-SC) — the LOO cross-validation refits from scratch per fold, including per-fold standardisation statistics, so no held-out row's information leaks into its own prediction"
    - "Single named gate predicate (RpeEstimator.gatePasses) is the only place the three REP-05 thresholds appear; CalibrationProfile derives insufficient/countOnly/calibrated by calling it twice — once with looMae fixed at 0.0 to isolate the count/session portion, once with the real looMae — rather than restating any threshold"
    - "CalibrationProfile is computed on demand from observationsFor, never persisted, so profile staleness is structurally impossible — RepTrackingRepository.profileFor only caches the computed value in memory per session and evicts on recordObservation"
key-files:
  created:
    - lib/features/reps/domain/rpe_estimator.dart
    - lib/features/reps/domain/rep_calibration.dart
    - test/rpe_estimator_test.dart
    - test/rep_calibration_test.dart
  modified:
    - lib/features/reps/data/rep_tracking_repository.dart
    - lib/features/reps/presentation/rep_tracking_providers.dart
    - lib/features/reps/presentation/rep_review_sheet.dart
    - test/rep_tracker_widget_test.dart
decisions:
  - "RpeEstimator.fit takes sampleCount/distinctSessionCount as explicit parameters rather than deriving them from the training row count, so the gate can be evaluated on a broader 'all confirmed sets, version-filtered' population than the (possibly smaller) subset of rows that actually have both a usable feature vector and a confirmed RPE. This is what let CalibrationProfile keep the interface's documented field meanings (sampleCount = all version-filtered rows) while still handing RpeEstimator exactly the rows it can train on."
  - "CalibrationProfile derives its three-way status without ever restating the 10/3/1.0 thresholds: it calls RpeEstimator.gatePasses twice, once with looMae forced to 0.0 (isolating count+session sufficiency) and once with the real looMae (the full calibrated check). This keeps 'RpeEstimator.gatePasses is the only place the thresholds appear' true by construction, verified by the plan's own grep."
  - "CalibrationProfile exposes both a public RpeModel? model field (null unless calibrated, per the plan's interface) and a double? estimate(RepFeatures) convenience method backed by a private RpeEstimator — added because the review sheet needs the estimator's own clamp/round/gate logic, not just the raw model, to avoid re-implementing it."
  - "_measurementRow (rep_review_sheet.dart) was changed from a fixed two-Text Row to a label + Expanded/right-aligned value, because the new calibration progress line ('calibrating for this setup (N of 10 sets)') is long enough to overflow the previous fixed layout — caught by test/rep_review_sheet_e2e_test.dart's pre-existing armband placement test, not a new test this plan added."
metrics:
  duration: ~2 hours
  tasks: 3
  files_created: 4
  files_modified: 4
  tests_added: 25
  completed: 2026-08-14
---

# Phase 10 Plan 05: Assisted Rep Tracking — Calibration Learning and RPE Gating Summary

A per (user, exercise, source, placement, sensor) RPE estimator — ridge-regularised OLS on five standardised features, gated by leave-one-out cross-validated error rather than by row count alone — wired from the repository through a Riverpod provider into the review sheet's RPE field, with a stated "N of 10 sets" progress line whenever the profile hasn't earned the right to suggest one.

## What Was Built

**Task 1 — the ridge-regularised RPE estimator and its single gate predicate (`202a7c3`).** `rpe_estimator.dart` fits ordinary least squares with a small fixed ridge lambda (`0.1`, a named `const`, never tuned) on five standardised features in the fixed order `meanPeriodMs, periodCv, normalisedAmplitude, finalRepPeriodRatio, amplitudeDecayRatio`. Rows with either nullable ratio feature are excluded from the fit entirely, never imputed. Standardisation statistics (per-feature mean/stddev) are computed from the training rows and stored on the fitted `RpeModel` so `predict` transforms a new row identically. `RpeEstimator.gatePasses({sampleCount, distinctSessionCount, looMae})` is the one named static predicate — `sampleCount >= 10 && distinctSessionCount >= 3 && looMae != null && looMae <= 1.0` — and is the only place those three literals appear anywhere under `lib/features/reps/` (verified by grep). Leave-one-out MAE refits the model from scratch on each n-1 fold, including that fold's own standardisation statistics, so no information from a held-out row (not even its contribution to a mean) reaches its own prediction. `estimate(RepFeatures f)` returns null on any gate failure or null feature, otherwise clamps to 5.0-10.0 and rounds to the nearest 0.5. `test/rpe_estimator_test.dart` (14 tests) verifies each of the three gate conditions failing independently, output shape (clamp + 0.5 boundary), degenerate inputs (all-null-ratio training set, single-row training set) yielding a null `looMae` rather than a crash, and — the one genuinely load-bearing test — the LOO MAE on a deterministic 3-row synthetic dataset matches an independently hand-derived closed-form value (`1/21`) to within `1e-9`. The closed form exploits the identity `sum(x_std_i^2) = n` for a population-standardised feature, and the fact that four constant "other" features standardise to zero and contribute nothing, to reduce the general multi-feature ridge+LOO computation to a single-feature formula that can be verified by hand rather than by re-running the implementation on itself.

**Task 2 — the calibration profile with version filtering and tuple-keyed invalidation (`ac5c61b`).** `rep_calibration.dart`'s `CalibrationProfile.fromObservations(List<RepSetObservationData>)` is computed on demand, never persisted. It parses each row's `featuresJson` through `RepFeatures.fromJson` and drops rows where it returns null (an older detector's `v`), reports `sampleCount`/`distinctSessionCount` over the surviving rows, `medianCadenceMs`/`cadenceSpread` over all of them (RPE-labelled or not), and trains the RPE fit only on rows with a non-null `confirmedRpeX10`. Status derivation never restates the gate's thresholds: `dataSufficient` is computed by calling `RpeEstimator.gatePasses` with `looMae: 0.0` (a value that always passes the LOO check, isolating the count/session portion), and `calibrated` by calling it again with the real `looMae`; `status` is `insufficient` when `!dataSufficient`, `countOnly` when `dataSufficient && !calibrated`, `calibrated` otherwise. `test/rep_calibration_test.dart` (9 tests) covers: 9 sets → insufficient; 10 sets across 2 sessions → insufficient (session gate independent of count); 10 sets/3 sessions with cadence strongly correlated to RPE → calibrated; the same shape with random, uncorrelated RPE → NOT calibrated (the anti-overfitting / no-assumed-slowdown check); an amplitude-decay-only correlation (constant cadence) → still calibrated, proving the model is not cadence-only; a stale-version regression that drops a calibrated profile's surviving count below 10 → back to insufficient; null-`confirmedRpeX10` rows excluded from the fit but still moving `medianCadenceMs`; and a changed placement producing a fresh `insufficient` profile while the original key's profile stays untouched.

**Task 3 — `profileFor` through the repository, and review-sheet consumption (`0102c77`).** `RepTrackingRepository.profileFor({slug, source, placement, sensorType})` wraps `CalibrationProfile.fromObservations(await observationsFor(...))` behind an in-memory cache keyed by the four-part tuple; `recordObservation` evicts the matching key so the very next read reflects the set just confirmed. `calibrationProfileProvider` (`rep_tracking_providers.dart`) is a `FutureProvider.family<CalibrationProfile, CalibrationProfileKey>` keyed on a named record (`{slug, source, placement, sensorType}`) rather than a `List`, for correct structural memoisation. `rep_review_sheet.dart` watches it keyed on the suggestion's own tuple: while `status == calibrated` and the user hasn't touched the RPE field, the slider is pre-filled with `profile.estimate(suggestion.features)` and labelled "suggested — edit if it looks wrong"; once the user drags the slider or taps clear, that value is theirs forever for this sheet instance, regardless of what the profile does on a later rebuild. When not calibrated, the "how this was measured" expander's "Calibration" row states progress plainly — "calibrating for this setup (N of 10 sets)" when insufficient, "still learning your pace — not yet confident enough to suggest an RPE" when `countOnly` — never styled or worded as an error. `recordObservation` now receives the real `suggestedRpeX10` (the value that was actually on screen when auto-suggested, independent of what the user ultimately saved) instead of a hardcoded null. The rep-count `TextField` has no `CalibrationStatus` branch anywhere in the file. `test/rep_tracker_widget_test.dart`'s pre-existing `RepReviewSheet` case now overrides `calibrationProfileProvider` with an explicit `insufficient` profile (unchanged assertions); a new case inserts 10 correlated, three-session observations, confirms the resulting profile is `calibrated`, overrides the provider with it, and asserts the `Slider`'s `value` equals `profile.estimate(...)`, that it remains editable (`onChanged != null`), and that the rep `TextField` is identical to the insufficient case's.

## Verification

| Check | Result |
|---|---|
| `flutter test test/rpe_estimator_test.dart` | 14 tests, 0 failures, including the hand-computed LOO MAE match to 1e-9 |
| `flutter test test/rep_calibration_test.dart` | 9 tests, 0 failures |
| `flutter test test/rep_tracker_widget_test.dart test/rep_tracker_write_boundary_test.dart` | 11 tests, 0 failures |
| `flutter test` (full suite) | 598 passed, 4 pre-existing skips, 0 failures |
| `flutter analyze` (whole project) | 0 issues introduced by this plan (pre-existing infos/warnings in unrelated files untouched) |
| `grep -n "slowdown\|slow_down" lib/features/reps/domain/rpe_estimator.dart` | no matches |
| `grep -rn "10\b.*sampleCount\|distinctSessionCount >= 3\|looMae <= 1.0" lib/features/reps/` | 2 hits, both inside `RpeEstimator.gatePasses`' own body |
| `grep -rn "features/workouts" lib/features/reps/` | 5 hits, all doc-comment prose naming the boundary rule, no code reference |

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 1 - Bug] The new calibration progress text overflowed the review sheet's measurement row layout**
- **Found during:** Task 3, running the full test suite after wiring the review sheet
- **Issue:** `test/rep_review_sheet_e2e_test.dart`'s pre-existing armband placement test failed with a `RenderFlex overflowed by 141 pixels` — `_measurementRow`'s `Row` used a fixed two-`Text` layout with `mainAxisAlignment: spaceBetween` and no wrapping, which the short "yes"/"no" value it previously displayed never exceeded. The new "calibrating for this setup (N of 10 sets)" / "still learning your pace — not yet confident enough to suggest an RPE" progress strings are much longer.
- **Fix:** Changed `_measurementRow` to wrap the value in an `Expanded` with `TextAlign.right`, so long values wrap onto a second line within the available width instead of overflowing. This is a layout-only change; every row's rendered label/value pairing is unchanged.
- **Files modified:** `lib/features/reps/presentation/rep_review_sheet.dart`
- **Commit:** `0102c77`

### Intentional Scope Decisions

- **No real recorded fixture corpus was used or needed.** Per the task brief, calibration and RPE tests use synthetic training data (deterministic linear/correlated/random-RPE datasets), matching the precedent set by 10-02 Task 5's still-pending human checkpoint and by 10-03b/10-04's own synthetic-trace tests. REP-06 remains open and untouched by this plan.
- **REP-05 is now fully implemented.** No RPE is suggested below 10 confirmed sets, below 3 distinct sessions, or above 1.0 leave-one-out MAE — each condition independently sufficient to block, enforced through the single `RpeEstimator.gatePasses` predicate and exercised end to end from synthetic observations through to the review sheet's rendered `Slider`.

## Known Stubs

None introduced by this plan. The pre-existing stubs from 10-04 (no true live count during `tracking`, phone battery gate hardcoded to 100%) are unaffected.

## Threat Flags

None beyond the plan's own threat register, all mitigated by this plan's artifacts:

| Threat | Mitigation | Evidence |
|---|---|---|
| T-10-22 (silent model corruption across detector versions) | `CalibrationProfile.fromObservations` drops any row whose `featuresJson` fails `RepFeatures.fromJson`'s `v` check; the resulting fallback to `insufficient` is asserted by test | `test/rep_calibration_test.dart`'s stale-version regression case |
| T-10-23 (fabricated confidence) | Ridge regularisation plus a leave-one-out MAE gate rather than a row count; the random-RPE user never calibrates; LOO MAE itself verified against a hand-computed value | `test/rpe_estimator_test.dart`'s hand-computed case, `test/rep_calibration_test.dart`'s random-RPE case |
| T-10-24 (assumed final-rep slowdown) | No branch condition on any slowdown/cadence signal; `finalRepPeriodRatio` is one of five standardised features free to collapse to zero; the amplitude-decay-only user still calibrates | `test/rep_calibration_test.dart`'s amplitude-decay case; `grep -n "slowdown\|slow_down"` shows no matches at all |
| T-10-25 (elevation via review-sheet edits) | Task 3 touches `rep_review_sheet.dart` but introduces no `lib/features/workouts/` import; the 10-04 write-boundary test re-run as this task's gate | `test/rep_tracker_write_boundary_test.dart`, both groups passing |
| T-10-SC (package installs) | No dependency added; the ridge fit and linear solve are hand-rolled over `dart:math` | `git diff --stat pubspec.yaml` empty |

## Notes for the Next Plan

- **10-06** (in-app fixture-recording debug tool) does not depend on anything this plan built and can proceed independently.
- **REP-06 is still the open gate.** Once a real recorded fixture corpus exists (`test/fixtures/motion/...`), `test/rep_review_sheet_e2e_test.dart` should be repointed at it, and it would also be reasonable at that point to add an integration test that feeds real fixture-derived features through `CalibrationProfile`/`RpeEstimator` rather than only the synthetic datasets this plan used.
- **The RPE suggestion label ("suggested — edit if it looks wrong")** and the two non-calibrated progress strings are Claude's Discretion widget copy per 10-CONTEXT's "widget composition of the review sheet" note — worth a product-copy pass if this reaches real users.

## Self-Check: PASSED

All four created files exist on disk (`lib/features/reps/domain/rpe_estimator.dart`, `lib/features/reps/domain/rep_calibration.dart`, `test/rpe_estimator_test.dart`, `test/rep_calibration_test.dart`); all four modified files carry the changes described above. All three task commits (`202a7c3`, `ac5c61b`, `0102c77`) are present in `git log`.
