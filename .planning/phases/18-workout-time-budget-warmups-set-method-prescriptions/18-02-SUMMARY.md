---
phase: 18-workout-time-budget-warmups-set-method-prescriptions
plan: 02
subsystem: domain
tags: [dart, drift-free-domain, warmup, duration-estimation, TDD]

requires:
  - phase: 17-deterministic-program-planner-hard-guardrails
    provides: "SlotRole.isHeavy/main distinction used unchanged for eligibility"
provides:
  - "WarmupResolver.resolve(...) -> List<WarmupStep>, intensity-density + movement-order ramp logic"
  - "WorkoutDurationEstimator.estimateExercise/estimateSession -> Duration, itemized breakdown"
affects: [18-04-resolver-wiring, 18-05-generation-wiring]

tech-stack:
  added: []
  patterns:
    - "Plain-Dart domain services (no Flutter/drift imports) callable from both data layer and unit tests without a database"

key-files:
  created:
    - lib/features/workouts/domain/warmup_resolver.dart
    - lib/features/workouts/domain/workout_duration_estimator.dart
    - test/features/workouts/warmup_resolver_test.dart
    - test/features/workouts/workout_duration_estimator_test.dart
  modified: []

key-decisions:
  - "Density table thresholds (>=0.90 -> 5 steps, >=0.80 -> 4, >=0.70 -> 3, else/null -> 2) match the plan's exact spec verbatim, including null targetPercentOf1Rm falling to the 2-step case for RIR-based straight sets with no %1RM."
  - "Abbreviated ramp (D-09) is computed as a suffix of the full ramp (top-most/heaviest steps kept), never a separately-derived shape, to satisfy the 'same formula, fewer steps' constraint."
  - "WorkoutDurationEstimator mini-set burst time is a fixed formula keyed on SetType.metaKeys.contains('miniSets') rather than reading the runtime meta map, per the plan's explicit instruction (estimate time without needing the actual runtime meta value)."

patterns-established:
  - "TDD RED/GREEN per task: failing test committed first, then minimal implementation."

requirements-completed: [PRES-02, PRES-03]

duration: 25min
completed: 2026-09-15
---

# Phase 18 Plan 02: Warmup Ramp & Duration Estimator Domain Services Summary

**Plain-Dart `WarmupResolver` (intensity-density ramp + movement-order abbreviation) and `WorkoutDurationEstimator` (itemized session-length projection) replacing the fixed ramp tables and flat time-buffer logic.**

## Performance

- **Duration:** ~25 min
- **Started:** 2026-09-15T00:00:00Z (approx, not separately timestamped)
- **Completed:** 2026-09-15
- **Tasks:** 2 completed
- **Files modified:** 4 (2 created source, 2 created test)

## Accomplishments
- `WarmupResolver.resolve` implements the four-tier density table (D-08) and movement-order abbreviation as a strict suffix of the full ramp (D-09), replacing `_automaticWarmups`/`_maxEffortSets`'s fixed tables (D-10).
- `WorkoutDurationEstimator.estimateExercise`/`estimateSession` itemize working-set time, unilateral doubling, warmup time, and rest-pause/myo-reps mini-set bursts (D-06), plus per-exercise transition time in session totals.
- Both services are plain Dart (only import each other / `set_type.dart` / `slot_role.dart`), callable from the data layer and unit tests without a database, per CLAUDE.md's domain-layer rule.

## Task Commits

Each task was committed atomically (TDD RED -> GREEN):

1. **Task 1: WarmupResolver** - `df32dd5` (test, RED) -> `9864cec` (feat, GREEN)
2. **Task 2: WorkoutDurationEstimator** - `6647452` (test, RED) -> `88caa38` (feat, GREEN)

## Files Created/Modified
- `lib/features/workouts/domain/warmup_resolver.dart` - `WarmupStep` value type + `WarmupResolver.resolve` density/order ramp logic
- `lib/features/workouts/domain/workout_duration_estimator.dart` - `WorkoutDurationEstimator.estimateExercise`/`estimateSession`
- `test/features/workouts/warmup_resolver_test.dart` - eligibility gate, density tiers, abbreviation-as-suffix, modality gate, null-target fallback
- `test/features/workouts/workout_duration_estimator_test.dart` - working-set time, unilateral doubling, mini-set bursts, warmup contribution, session transition time

## Decisions Made
- Abbreviation formula: `(fullRamp.length / 2).ceil().clamp(1, fullRamp.length)` steps kept, taken from the end (heaviest) of the full ramp — matches plan text exactly.
- `WarmupStep` deliberately does not extend/wrap `PlannedSetSnapshot` (a `data/`-layer type) to keep `domain/` free of data-layer imports; Plan 18-04 owns the `WarmupStep` -> `PlannedSetSnapshot` mapping at the call site.

## Deviations from Plan

None - plan executed exactly as written.

## Issues Encountered

None.

## User Setup Required

None - no external service configuration required.

## Next Phase Readiness

- Plan 18-04 (resolver wiring) can now replace `_automaticWarmups`/`_maxEffortSets` in `planned_session_resolver.dart` with `WarmupResolver.resolve(...)`, mapping `WarmupStep` -> `PlannedSetSnapshot`.
- Plan 18-05 (generation wiring) can call `WorkoutDurationEstimator.estimateSession` to trim accessory/isolation volume toward `SmartProgramConfiguration.workoutDurationMinutes` (D-05/D-07), superseding `_timePlanFor`.
- No blockers.

## TDD Gate Compliance

Both tasks followed RED (`test(...)`) -> GREEN (`feat(...)`) commit sequence; no REFACTOR commit was needed (implementations passed cleanly on first attempt, no cleanup required).

---
*Phase: 18-workout-time-budget-warmups-set-method-prescriptions*
*Completed: 2026-09-15*
