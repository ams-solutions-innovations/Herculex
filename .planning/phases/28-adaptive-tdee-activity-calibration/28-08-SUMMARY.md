---
phase: 28-adaptive-tdee-activity-calibration
plan: 08
subsystem: nutrition
tags: [tdee, riverpod, widget-tests, nutrition-targets, dream-physique]
requires:
  - phase: 28-07
    provides: maintenanceKcalProvider, latestTdeeEstimateProvider, adaptive baselineTargetsProvider
provides:
  - Editor "Maintenance calories" field pre-filled from the adaptive estimate
  - Quick Calories & Phase Planner baselined on pure maintenance
  - Dream-physique setup view reading baselineTargetsProvider
affects: [28-09, 23-persistent-dream-physique]
tech-stack:
  added: []
  patterns:
    - "Maintenance-labelled UI reads maintenanceKcalProvider; daily fallbacks read baselineTargetsProvider"
key-files:
  created: []
  modified:
    - lib/features/nutrition/presentation/views/nutrition_targets_view.dart
    - lib/features/profile/presentation/dream_physique_view.dart
    - test/features/nutrition/nutrition_targets_view_test.dart
key-decisions:
  - "Estimate is pure maintenance wherever a value is labelled maintenance; the goal delta is applied exactly once per path"
patterns-established:
  - "Prefill tests pre-warm profileProvider and latestTdeeEstimateProvider through a ProviderContainer wrapped in UncontrolledProviderScope"
requirements-completed: [TDEE-01, TDEE-04]
duration: 40min
completed: 2026-09-28
---

# Phase 28 Plan 08: Route Editor, Planner and Dream Physique Through Adaptive TDEE Summary

**Editor maintenance field, phase planner and dream-physique setup view now read `maintenanceKcalProvider` / `baselineTargetsProvider`, removing the last two `MacroTargets.fromProfile` bypasses in the UI.**

## Accomplishments
- `TargetEditorView.initState` reads `baselineTargetsProvider` (goal-adjusted daily figures for calories/macros) and `maintenanceKcalProvider` (pure maintenance for the "Maintenance calories" field). With an existing saved target the field still shows the estimate, falling back to baseline then the target's kcal.
- `_QuickPhasePlannerSection` feeds `DietPhaseCalculator.apply` the pure maintenance figure (fallback 2500), so the goal delta is no longer applied twice before the cut/bulk delta. `DietPhaseCalculator` is untouched.
- `dream_physique_view.dart` `_buildSetupView` uses `ref.watch(baselineTargetsProvider)`; the now-unused `macro_targets.dart` import was removed.
- PHYS-04 (Phase 23) one-line markers at both `DietPhaseCalculator.apply` call sites. No gate implemented.
- `nutrition_targets_view.dart` went from 2617 to 2615 lines (net -2, ceiling was +12), and no widgets were added, so plan 09 has its full budget.

## Task Commits
1. **Task 1: Route editor, planner and dream-physique through the adaptive providers** - `79faf28` (feat)

## Files Created/Modified
- `lib/features/nutrition/presentation/views/nutrition_targets_view.dart` - editor and planner routed through the adaptive providers
- `lib/features/profile/presentation/dream_physique_view.dart` - setup view reads `baselineTargetsProvider`
- `test/features/nutrition/nutrition_targets_view_test.dart` - shared harness now overrides `latestTdeeEstimateProvider`; `testApp` accepts an optional `ProviderContainer`; 4 new tests

## Tests
- New: observed 2650 prefill (maintenance field 2650, calories 2950), cold start (maintenance 2775, calories `fromProfile` value), editing a saved target still shows the estimate, planner shows `Baseline: 3000 kcal (TDEE)` when `maintenanceKcalProvider` is overridden to 3000.
- Red first: the three editor tests failed against the old `fromProfile` code before the edit; the planner test failed on the old baseline label.
- Full `flutter test`: **1558 passed, 9 skipped, 0 failed**.
- `flutter analyze`: 0 errors (42 pre-existing warnings/info, none in files touched here after the unused-import cleanup; one `directives_ordering` in the test file was fixed).
- `dart run tool/check_structure.dart`: 58 violations, all pre-existing over-600-line files; nothing new.

## Decisions Made
- Estimate is PURE maintenance wherever a value is labelled maintenance (editor field, phase planner, "TDEE Maintenance" chip). The goal-adjusted daily fallback stays in `baselineTargetsProvider`.
- Behavioural side effect to flag: for weight-loss and muscle-gain users the planner and editor maintenance numbers move by the old goal delta (-500 / +300). This corrects a double application that existed before this phase.

## Deviations from Plan
None in production code. Test-harness notes (not deviations in behaviour):
- `TextField` contents are not `Text` widgets, so `find.widgetWithText` cannot see them; a small `fieldWith(text)` predicate on `controller.text` is used instead.
- The editor tests set a 1080x4000 viewport so the lazy list builds the maintenance and calories fields.

## Issues Encountered
None blocking. `gsd-sdk` state-advance verbs still no-op on this STATE.md format, so the STATE.md note is hand-written.

## Known Stubs
None.

## Threat Flags
None. The prefill only populates a text field; a saved rule requires the user's explicit save and `TargetResolver` keeps it authoritative (T-28-32, T-28-33 mitigated; T-28-34 accepted with markers).

## Next Phase Readiness
Plan 28-09 can add the badge and detail sheet under the "Maintenance calories" field; the field and badge now read the same provider. Its edit budget on `nutrition_targets_view.dart` is intact.

## Self-Check: PASSED
- Files exist: the three modified files and this SUMMARY.
- Commit `79faf28` exists.
