---
phase: 18-workout-time-budget-warmups-set-method-prescriptions
plan: 05
subsystem: data
tags: [dart, program-generation, time-budget, warmup, drift]

requires:
  - phase: 18-workout-time-budget-warmups-set-method-prescriptions
    plan: 02
    provides: "WarmupResolver.resolve, WorkoutDurationEstimator.estimateExercise/estimateSession"
  - phase: 18-workout-time-budget-warmups-set-method-prescriptions
    plan: 01
    provides: "SlotPrescriptionCodec.encode/decode, ProgramDayExercises.prescriptionCodecJson, Programs.allowTimeSavingSetTechniques"
provides:
  - "SmartProgramPlanner.populate() two-pass per-day time-budget trim loop driven by real warmup/unilateral estimates"
  - "Codec-encoded stored-override prescriptions (prescriptionCodecJson) instead of ad-hoc templateSets JSON"
  - "Programs.allowTimeSavingSetTechniques persisted at generation time"
affects: []

tech-stack:
  added: []
  patterns:
    - "Two-pass generation loop: collect per-slot plans first, project/trim against a real duration estimate, then insert — instead of insert-immediately single-pass"

key-files:
  created:
    - test/features/programs/smart_program_planner_test.dart
  modified:
    - lib/features/programs/data/smart_program_planner.dart
    - test/smart_program_planner_test.dart

key-decisions:
  - "Task 1 and Task 2 are committed together (single commit) rather than as two atomic commits: both rewrite the same populate() insert block (Task 1's pass-2 restructure and Task 2's prescriptionCodecJson field rename land in the same lines), and splitting them would require an intermediate non-compiling state."
  - "Trim priority is isolation-then-accessory only; SlotRole.conditioning is excluded from the trimmable set even though it is not `role.isHeavy`, since the plan's must_haves and threat model only name accessory/isolation as trimmable."
  - "weeklySetsByMuscle accumulation and the persisted `restSeconds` column both keep reading the pre-trim `_Target` (the `target` field), not the trimmed `timePlan.target` — this preserves the single-pass code's existing weekly-set-cap accounting unchanged, per the plan's instruction that only the insert loop's data source changes, not its field mapping."
  - "The unilateral-doubling and warmup-eligibility trim-decision tests use `machine_plate` (in SlotRoleEligibility's max-effort-modality set but outside WarmupResolver's eligible-modality set) instead of the plan's illustrative `cable` example, because `cable` can never earn SlotRole.main eligibility from `SlotRoleEligibility.derive` at all (main requires cnsScore>=5 AND a max-effort-capable modality, and cable is not one) — `machine_plate` is the smallest real modality that is main-eligible yet warmup-ineligible."

requirements-completed: [PRES-01, PRES-02, PRES-04]

duration: ~50min
completed: 2026-09-15
---

# Phase 18 Plan 05: Time-Budget Trim Loop, Codec-Based Prescriptions & Persisted Opt-In Summary

**Two-pass per-day generation loop that projects session duration via `WorkoutDurationEstimator` (fed by real `WarmupResolver` ramps and the catalog's real unilateral flag) and trims accessory/isolation volume to fit `workoutDurationMinutes*1.10`, plus switching stored-override writes to `SlotPrescriptionCodec` and persisting `allowTimeSavingSetTechniques` onto the generated `Programs` row.**

## Performance

- **Duration:** ~50 min
- **Completed:** 2026-09-15
- **Tasks:** 2 completed (committed together — see Deviations)
- **Files modified:** 2 (`smart_program_planner.dart`, `smart_program_planner_test.dart`); 1 created (`test/features/programs/smart_program_planner_test.dart`)

## Accomplishments

- `SmartProgramPlanner.populate()`'s per-day loop is now two-pass: pass 1 computes every slot's `target`/`timePlan` and tracks movement order (`sawHeavyLift`) exactly as `resolveProgramDay`'s materialize-time resolver does (18-04); pass 2 inserts the (possibly trimmed) plan list.
- Between the two passes, the day's projected duration is computed via `WorkoutDurationEstimator.estimateSession`, itemizing each slot's real `WarmupResolver.resolve(...)` ramp (same role/mechanics/modality/target-%1RM/movement-order inputs 18-04's resolver uses, including the `SlotTrainingMethod.maxEffort -> 0.90` constant) and real unilateral flag from `ExerciseCatalog.movementPatternRaw`. If the estimate exceeds `workoutDurationMinutes*1.10`, a trim loop reduces isolation-then-accessory slot set counts to a floor of 1, then drops isolation-then-accessory slots entirely, until the day fits or no trimmable slots remain. `SlotRole.main`/`supplemental` are never touched.
- `_timePlanFor`'s myo-reps compression path now builds a `SlotPrescription`/`WorkSegment` and writes `SlotPrescriptionCodec.encode(...)` into the renamed `_TimePlan.prescriptionCodecJson` field, which flows into `ProgramDayExercisesCompanion.insert(prescriptionCodecJson: ...)` — the legacy ad-hoc `templateSets` JSON blob and `prescriptionJson` column are no longer written by generation.
- `populate()` writes `configuration.allowTimeSavingSetTechniques` onto the `Programs` row immediately after fetching it, so the opt-in survives past generation for 18-03's live-workout gate and 18-04's resolver.

## Task Commits

Both tasks landed in one commit because they rewrite the same `populate()` insert block (see Deviations):

1. **Task 1 + Task 2** - `a82353e` (`feat(18-05): trim day duration to time budget via WorkoutDurationEstimator; codec-based prescriptions`)

## Files Created/Modified
- `lib/features/programs/data/smart_program_planner.dart` - two-pass trim loop, `_DaySlotPlan`, `_estimateDayDuration`/`_estimateSlotDuration`, codec-based `_timePlanFor`, persisted `allowTimeSavingSetTechniques`
- `test/features/programs/smart_program_planner_test.dart` (new) - 5 tests: short-vs-long duration trim comparison, warmup-eligible-vs-ineligible main lift trim comparison, unilateral-flag trim comparison, `allowTimeSavingSetTechniques` persistence, codec round-trip
- `test/smart_program_planner_test.dart` - updated the "short sessions use opted-in Myo-reps" test's assertion from `prescriptionJson != null` to `prescriptionCodecJson != null` (Rule 1 — this plan's Task 2 change broke the old assertion)

## Decisions Made

- Trim priority is isolation-then-accessory only; `SlotRole.conditioning` is deliberately excluded from the trimmable set (see `key-decisions` above).
- `weeklySetsByMuscle` accounting and the persisted `restSeconds` column read from the pre-trim `_Target`, matching the pre-existing single-pass behavior exactly — trimming only affects `timePlan.target` (what's actually inserted as `targetSets`/`targetRepsMin`/etc.), not the outer volume-cap bookkeeping.
- Test fixtures use `machine_plate` instead of the plan's illustrative `cable` modality for the warmup-ineligible-but-main-eligible case, since `cable` can never earn `SlotRole.main` eligibility at all (see `key-decisions`).

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 1 - Bug] Fixed `test/smart_program_planner_test.dart`'s Myo-reps assertion**
- **Found during:** Task 2
- **Issue:** The existing "short sessions use opted-in Myo-reps only for isolation slots" test asserted `row.prescriptionJson != null`, which Task 2's field rename to `prescriptionCodecJson` broke.
- **Fix:** Changed the assertion to `row.prescriptionCodecJson != null`.
- **Files modified:** `test/smart_program_planner_test.dart`
- **Commit:** `a82353e`

### Workflow Adaptation (not a Rule 1-4 deviation)

**Task 1 and Task 2 committed together, not as two atomic commits.** Both tasks rewrite the exact same `populate()` per-day loop and its `ProgramDayExercisesCompanion.insert(...)` call: Task 1's pass-2 restructure (sourcing the insert from the post-trim `_DaySlotPlan` list) and Task 2's field rename (`prescriptionJson` -> `prescriptionCodecJson`) land in the same lines of the same insert block. Splitting them into two commits would require staging an intermediate state where the file does not compile (e.g., `_TimePlan.prescriptionCodecJson` referenced before it exists, or vice versa). Both tasks' acceptance criteria are verified together by the same test run.

## Issues Encountered

None beyond the above.

## User Setup Required

None - no external service configuration required.

## Next Phase Readiness

- The generated `Programs.allowTimeSavingSetTechniques` and `ProgramDayExercises.prescriptionCodecJson` are now durable, real values for 18-03's live-workout gate and 18-04's resolver to read after generation — no further wiring needed from this plan's side.
- No blockers.

## Known Stubs

None.

## Threat Flags

None - this plan's changes stay within the trust boundary and STRIDE mitigations already declared in its own `<threat_model>` (T-18-09, T-18-10, T-18-11); no new network endpoints, auth paths, or schema changes were introduced.

## Self-Check: PASSED

- FOUND: lib/features/programs/data/smart_program_planner.dart
- FOUND: test/features/programs/smart_program_planner_test.dart
- FOUND: .planning/phases/18-workout-time-budget-warmups-set-method-prescriptions/18-05-SUMMARY.md
- FOUND commit: a82353e

---
*Phase: 18-workout-time-budget-warmups-set-method-prescriptions*
*Completed: 2026-09-15*
