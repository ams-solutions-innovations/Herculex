---
phase: 21-crossfit-gpp-training-tracks
plan: 03
subsystem: domain
tags: [drift, exercise-programming, time-budget, prerequisites, tdd]

# Dependency graph
requires:
  - phase: 16-exercise-programming-metadata-discipline-taxonomy
    provides: exercise_programming_metadata.json schema (prerequisiteSlugs, scalingGroup) and ExerciseProgrammingEligibility.verifyPrerequisites dual-check gate
  - phase: 18-workout-time-budget-warmups-set-method-prescriptions
    provides: WorkoutDurationEstimator.estimateExercise/estimateSession per-rep time-budget model
provides:
  - "WorkoutDurationEstimator.estimateCappedSegment(capSeconds) for AMRAP/EMOM/For-Time metcon segments, composing with estimateSession's existing Iterable<Duration> parameter"
  - "8 curated prerequisiteSlugs entries (kipping-muscle-up, strict-muscle-up, power-clean, hang-power-clean, clean-and-jerk, power-snatch, hang-snatch, squat-snatch) closing the metadata gap RESEARCH.md identified"
affects: [21-04-crossfit-program-planner, 21-05-gpp-program-planner]

# Tech tracking
tech-stack:
  added: []
  patterns:
    - "Fixed/capped-duration segments feed a conservative upper-bound Duration into estimateSession as one more element of its Iterable<Duration> parameter, no signature change needed"
    - "Metadata-only prerequisite gating: single-movement prerequisiteSlugs curated without building a chained-complex scalingGroup ladder — deliberately deferred scope per RESEARCH.md"

key-files:
  created: []
  modified:
    - lib/features/workouts/domain/workout_duration_estimator.dart
    - test/features/workouts/workout_duration_estimator_test.dart
    - assets/data/exercise_programming_metadata.json
    - test/exercise_scaling_resolver_test.dart

key-decisions:
  - "estimateCappedSegment returns capSeconds verbatim with no per-rep math, documented as a conservative upper bound (advanced athletes finishing early still show as taking the full cap) rather than a predicted actual completion time"
  - "Olympic-lift family (power-clean, hang-power-clean, clean-and-jerk, power-snatch, hang-snatch, squat-snatch) all gated on front-squat + overhead-press per Phase 16's stated-but-unshipped D-07 intent, matching front-squat/overhead-press's actual programmingDifficulty: intermediate in the metadata"
  - "kipping-muscle-up and strict-muscle-up mirror bar-muscle-up's existing pull-up + chest-dips gate exactly; no scalingGroup added to any of the 8 entries, keeping chained-complex ladder scope explicitly deferred rather than silently built"

requirements-completed: [CF-01, CF-02]

# Metrics
duration: 25min
completed: 2026-09-26
---

# Phase 21 Plan 03: Duration Cap Estimator + Prerequisite Metadata Gap Summary

**Added `WorkoutDurationEstimator.estimateCappedSegment` for fixed-duration metcon segments and curated 8 missing `prerequisiteSlugs` entries (muscle-up variants + all 6 Olympic lifts) closing a metadata gap from Phase 16's unshipped intent.**

## Performance

- **Duration:** 25 min
- **Started:** 2026-09-26T09:57:00Z
- **Completed:** 2026-09-26T10:22:11Z
- **Tasks:** 2
- **Files modified:** 4

## Accomplishments
- `WorkoutDurationEstimator.estimateCappedSegment(capSeconds: 600)` returns the cap verbatim as a `Duration`, proven via TDD (RED then GREEN) to compose with `estimateSession`'s existing `Iterable<Duration>` parameter with zero signature change.
- Closed the `prerequisiteSlugs` metadata gap RESEARCH.md identified: `kipping-muscle-up`/`strict-muscle-up` now mirror `bar-muscle-up`'s `pull-up`/`chest-dips` gate; `power-clean`, `hang-power-clean`, `clean-and-jerk`, `power-snatch`, `hang-snatch`, `squat-snatch` now require `front-squat`/`overhead-press`.
- Extended `test/exercise_scaling_resolver_test.dart` with a `CrossFit prerequisite gating (CF-02)` group proving `ExerciseProgrammingEligibility.verifyPrerequisites` gates a novice with no completed history and admits one with completed prerequisites, for both the Olympic-lift and muscle-up families.

## Task Commits

Each task was committed atomically:

1. **Task 1: WorkoutDurationEstimator.estimateCappedSegment** - `e49d172` (test, RED) then `c7ed2d4` (feat, GREEN)
2. **Task 2: Curate prerequisiteSlugs metadata gap + extend scaling resolver tests** - `0577289` (feat)

**Plan metadata:** pending (this commit)

_Note: Task 1 followed the plan's tdd="true" RED/GREEN cycle; no REFACTOR commit was needed since the minimal implementation matched the documented design directly._

## Files Created/Modified
- `lib/features/workouts/domain/workout_duration_estimator.dart` - Added `estimateCappedSegment({required int capSeconds})` static method with a doc comment explaining the conservative-upper-bound design choice (RESEARCH.md Pitfall 3)
- `test/features/workouts/workout_duration_estimator_test.dart` - Added `WorkoutDurationEstimator.estimateCappedSegment` group: verbatim-cap assertion and an `estimateSession` composition assertion
- `assets/data/exercise_programming_metadata.json` - Set `prerequisiteSlugs` on 8 entries: `["pull-up","chest-dips"]` for `kipping-muscle-up`/`strict-muscle-up`; `["front-squat","overhead-press"]` for `power-clean`, `hang-power-clean`, `clean-and-jerk`, `power-snatch`, `hang-snatch`, `squat-snatch`
- `test/exercise_scaling_resolver_test.dart` - Added `CrossFit prerequisite gating (CF-02)` group with 4 new tests calling `ExerciseProgrammingEligibility.verifyPrerequisites` directly against `power-clean` and `kipping-muscle-up` fixtures

## Decisions Made
- Front-squat and overhead-press fixtures in the new test group use `programmingDifficulty: 'intermediate'` (matching their real metadata values) rather than the `_makeExercise` default of `'novice'`, so the "novice with no history" test case is actually gated by the history check rather than trivially passing the dual-check's experience-rank branch first.
- No `scalingGroup` was added to any of the 8 curated entries — RESEARCH.md's Olympic-complexes section explicitly scoped a chained-complex scaling ladder out of this phase; single-movement prerequisite gating is the CF-02-satisfying surface area.

## Deviations from Plan

None - plan executed exactly as written.

## Issues Encountered

None.

## User Setup Required

None - no external service configuration required.

## Next Phase Readiness
- `estimateCappedSegment` is ready for `21-04-crossfit-program-planner` and `21-05-gpp-program-planner` to feed AMRAP/EMOM/For-Time metcon caps into session time-budget checks.
- The 8 curated `prerequisiteSlugs` entries are ready for both planners' skill/scaling gating without further metadata changes; `lib/data/local/exercise_importer.dart`'s existing JSON-to-column mapping requires no code changes (data-only edit, confirmed by reading importer lines 277-310 before editing).
- No blockers identified for Wave 2 (21-04, 21-05).

---
*Phase: 21-crossfit-gpp-training-tracks*
*Completed: 2026-09-26*

## Self-Check: PASSED

All created/modified files confirmed present; all 3 task commit hashes (e49d172, c7ed2d4, 0577289) confirmed in git log.
