---
phase: 23-persistent-dream-physique-multi-phase-nutrition
plan: 11
subsystem: application
tags: [physique, riverpod, providers, check-in, goal-starter, charts]
requires: ["23-03", "23-06", "23-07", "23-08", "23-09"]
provides:
  - physique_providers.dart (repository/service providers, goal/phase/check-in/photo streams, eligibility, body-fat reading, phase status, legacy migration + reconcile provider)
  - physique_chart_providers.dart (range/lift selection, weight, strength and training-level chart data)
  - PhysiqueGoalStarter (stagePhotos, discardStaged, startFromAnalysis) and physiqueGoalStarterProvider
  - PhysiqueCheckInFlow, CheckInOutcome (CheckInRecorded, CheckInAiUnavailable, BaselineSaved), physiqueCheckInFlowProvider
affects: [23-12, 23-13, 23-14, 23-15, 23-16, 23-17]
tech-stack:
  added: []
  patterns: [StreamProvider over drift repositories, fail-closed eligibility with sync fallback, plain-class orchestration flow with progress callback, adopt-by-move with rollback]
key-files:
  created:
    - lib/features/physique/application/physique_providers.dart
    - lib/features/physique/application/physique_chart_providers.dart
    - lib/features/physique/application/physique_goal_starter.dart
    - lib/features/physique/application/physique_check_in_flow.dart
    - test/features/physique/physique_providers_test.dart
    - test/features/physique/physique_goal_starter_test.dart
    - test/features/physique/physique_check_in_flow_test.dart
  modified: []
key-decisions:
  - "physiquePhaseStatusProvider and body-fat reading are plain Providers (null until goal and phases load); position is 0 while no phase is current (proposal pending)"
  - "Eligibility reads profileProvider: data -> that age, loading -> stored profile via currentProfile, error/none/null age -> restricted"
  - "Consent is checked after the cap pre-check and before baseline loading or any network call; no-analysis saves skip consent"
  - "Baseline photo poses from the Dream Physique save path default to front"
  - "Starter discards all staged temp files on failure (adopted ones are already moved, discard is tolerant) and deletes physique/<goalUuid>/"
requirements-completed: []
duration: 40min
completed: 2026-10-02
---

# Phase 23 Plan 11: Physique application layer Summary

Application layer connecting domain rules, repositories, photo pipeline and AI service: live providers for goal, phase status, advance offer, cap date, body-fat reading and chart data, a goal starter that turns a Dream Physique analysis into a goal with sanitised baseline photos, and a check-in flow that stages, cap-checks, analyses, classifies in Dart and then persists.

## Tasks

1. physique_providers.dart (+ tests, 26 cases) - ccb6add
2. physique_chart_providers.dart and PhysiqueGoalStarter (+ tests, 9 starter cases, 5 chart-provider cases) - 4e0dd65
3. PhysiqueCheckInFlow (+ tests, 18 cases) - de11532

## Verification

- `flutter test test/features/physique test/dream_physique_service_test.dart`: 287 pass
- `flutter analyze lib/features/physique test/features/physique`: no issues
- `dart format --set-exit-if-changed lib/features/physique test/features/physique`: clean
- `check_structure` lists no `features/physique` file; application files are 148 to 393 lines
- No `DateTime.now()` in `lib/features/physique/application` (the only grep hit for `DateTime.now` as a regex is `DateTime(now.year, ...)`, built from the injected Clock)
- No nutrition repository, targets or DietPhaseCalculator imports in the application layer (the exit evaluator and DietPhase enum are domain types only)

## Deviations from Plan

None - plan executed as written. TDD tasks were committed as one feat commit each (tests written alongside the implementation, not a separate RED commit).

## Notes for later plans

- Plan 15 `savePhysiqueGoal`: call `stagePhotos`, show the No face found dialog when `noFaceFound`, then `startFromAnalysis`; `discardStaged` on cancel.
- Plan 16 progress screen: `physiquePhaseStatusProvider(goalId)` returns null until loaded; render the "Log measurements to refine this." action from `logMeasurementsHint`.
- `physiqueLegacyMigrationProvider` must be read once at app start (not yet wired into bootstrap by this plan).
- PHYS-01/04/05/06/07/08 are only application halves here; requirements not marked complete.

## Known Stubs

None.

## Threat Flags

None.

## Self-Check: PASSED

All seven created files exist; commits ccb6add, 4e0dd65, de11532 present.
