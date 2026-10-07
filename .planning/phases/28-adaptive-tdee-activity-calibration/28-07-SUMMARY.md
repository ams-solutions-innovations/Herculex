---
phase: 28-adaptive-tdee-activity-calibration
plan: 07
subsystem: nutrition-application
tags: [tdee, riverpod, recalibration, lifecycle, clock]
requires:
  - phase: 28-02
    provides: MacroTargets.seedMaintenanceKcal / fromMaintenance / multiplierFor / bmr
  - phase: 28-04
    provides: TdeeEstimator.recalibrate / shouldRecalibrate, ActivityClassifier
  - phase: 28-06
    provides: TdeeEstimatesRepository, TdeeInputsRepository
provides:
  - tdeeEstimatesRepositoryProvider, latestTdeeEstimateProvider, tdeeEstimateProvider, maintenanceKcalProvider
  - baselineTargetsProvider sourced from the adaptive estimate
  - TdeeRecalibrator, TdeeResumeObserver, tdeeRecalibratorProvider, tdeeRecalibrationControllerProvider
affects: [28-08, phase-29]
tech-stack:
  added: []
  patterns:
    - "Provider<void> controller watched in app.dart, guarded async body with catch (_)"
    - "WidgetsBindingObserver registered by a provider and removed in ref.onDispose"
key-files:
  created:
    - lib/features/nutrition/application/tdee_providers.dart
    - lib/features/nutrition/application/tdee_recalibration_controller.dart
    - test/features/nutrition/tdee_providers_test.dart
    - test/features/nutrition/tdee_recalibration_test.dart
  modified:
    - lib/features/nutrition/application/nutrition_providers.dart
    - lib/app/app.dart
key-decisions:
  - "baselineTargetsProvider keeps type Provider<MacroTargets?>; cold start, loading and error return exactly MacroTargets.fromProfile(profile), so no existing widget test needed a harness change."
  - "A stored coldStart row's kcal is ignored in favour of the live profile seed, so an ActivityLevel reset takes effect at once (D-14); observed and classifier rows are returned as stored (D-15)."
  - "The recalibrator reads the profile through the latest emitted value, not profileProvider.future, so a forced run after a reset sees the new level."
requirements-completed: [TDEE-01, TDEE-02, TDEE-03, TDEE-04, TDEE-05]
duration: 40min
completed: 2026-09-28
---

# Phase 28 Plan 07: TDEE Providers and Recalibration Controller Summary

**The adaptive maintenance estimate now drives `baselineTargetsProvider`, and a Clock-gated recalibrator runs at app open, on resume and on ActivityLevel reset, with saved manual targets still winning.**

## Tasks

| Task | Name | Commit |
|------|------|--------|
| 1 | tdee_providers.dart and baselineTargetsProvider rewire | 6b50d55 |
| 2 | TdeeRecalibrator, controller provider, app.dart registration | 3af00bd |

## What was built

- `tdee_providers.dart`: `latestTdeeEstimateProvider` (non-autoDispose `StreamProvider`), `tdeeEstimateProvider` (stored observed/classifier row, otherwise a synthesized cold-start row from the live seed), `maintenanceKcalProvider` (pure maintenance, no goal delta; plan 08 should read this for maintenance-labelled UI). It does not import `nutrition_providers.dart`.
- `nutrition_providers.dart`: only `baselineTargetsProvider` changed (about 11 added lines, 934 lines total, it was already over the limit). Non-cold-start estimates go through `MacroTargets.fromMaintenance`, so the goal delta is added exactly once. `effectiveTargetsProvider` and `TargetResolver` are untouched.
- `tdee_recalibration_controller.dart`: `TdeeRecalibrator.run({force})` with an in-flight guard and a blanket `catch (_)`; steps are filtered to the last 14 days before classification; it never references `nutrition_targets`. The controller provider runs once when a profile first arrives, forces a run when `activityLevel` changes, and a `TdeeResumeObserver` triggers a non-forced run on `AppLifecycleState.resumed` (removed on dispose). The estimate stream is kept warm with `ref.listen`, never `ref.watch`.
- `app.dart`: one `ref.watch(tdeeRecalibrationControllerProvider)` plus its import.

## Verification

- `tdee_providers_test.dart` 11 tests and `tdee_recalibration_test.dart` 13 tests pass, covering: null/loading/error degrade to the seed, observed and classifier rows, reseed on reset, observed method unchanged by reset, null and incomplete profile, TDEE-04 saved rule (2222) beating an observed 3000 estimate, all five steps of the logging-stopped fixture on the exact dates (coldStart pending, observed, observed F kcal 2500, held on 2026-03-08 with `held` and `measured_at` 2026-03-01, coldStart fallback on 2026-03-15), same-day and post-cadence resume, in-flight overlap, lifecycle wiring (only `resumed` fires, none after dispose), and `nutrition_targets` rows identical before and after runs.
- Full `flutter test`: 1554 passed, 9 skipped, 0 failed.
- `flutter analyze`: 0 errors (42 pre-existing warnings/infos, none in the new files).
- `tool/check_structure.dart`: 58 violations, all pre-existing; `app.dart` (798) and `nutrition_providers.dart` (934) were already over 600.
- Grep gates: no `DateTime.now`, no `nutritionTargets` in the controller or estimates repository; `tdeeRecalibrationControllerProvider` appears once in `app.dart`.
- `nutrition_targets_view_test`, `weekly_calories_test` and `health_integration_phase6_test` pass with no harness change.

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 1 - Bug] Recalibrator read a stale profile after an ActivityLevel reset**
- **Found during:** Task 2, end-to-end controller test
- **Issue:** `ref.read(profileProvider.future)` returned the first emitted profile, so the forced reseed row was computed from the old level (kcal 2775 instead of 3088).
- **Fix:** read `ref.read(profileProvider).asData?.value` first and fall back to awaiting the future.
- **Files modified:** `lib/features/nutrition/application/tdee_recalibration_controller.dart`
- **Commit:** 3af00bd

The plan's test-first order was followed, but each task landed as one commit (tests plus implementation) because a red-only commit would not compile.

## Limits to know about

- There is no background scheduler in this project, so a user who never reopens or resumes the app is not recalibrated. App open, resume and reseed are the only triggers.
- Each persisted qualified non-observed row restarts the 7-day promotion clock; the recalibrator passes `TdeeEstimatesRepository.recent()` so the estimator sees the real history.
- On the very first frame the estimate stream has not emitted yet, so the baseline briefly shows the profile seed and then switches to the stored estimate for observed or classifier users. This is the deliberate D-08 degrade and is exercised by the loading-stream test.
- `NutritionRepository.watchDailyTotalsForRange` still does not filter `deletedAt`; food entries are hard-deleted today so it does not disagree with `foodLoggedDays`.

## Known Stubs

None.

## Threat Flags

None. No new endpoints, auth paths or schema changes.

## Self-Check: PASSED

- Files exist: tdee_providers.dart, tdee_recalibration_controller.dart, both test files.
- Commits exist: 6b50d55, 3af00bd.
