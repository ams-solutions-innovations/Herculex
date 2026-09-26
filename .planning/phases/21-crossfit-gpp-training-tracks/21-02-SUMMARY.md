---
phase: 21-crossfit-gpp-training-tracks
plan: 02
subsystem: programs-domain
tags: [dart, domain-service, crossfit, gpp, scaling-policy, pure-dart]

# Dependency graph
requires:
  - phase: 21-crossfit-gpp-training-tracks
    provides: "Plan 21-01's SessionSegment enum / CrossfitSlotNeed descriptor (referenced conceptually, no direct import)"
provides:
  - "CrossfitScalingPolicy.timeCapFor — per-level AMRAP/EMOM/For Time time caps"
  - "CrossfitScalingPolicy.movementCeilingFor — public per-level movement-count ceiling accessor"
  - "CrossfitScalingPolicy.complexityCheck — movement-count and advanced-movement-stacking guard"
  - "CrossfitScalingPolicy.recoveryReserveWarning — advisory back-to-back CrossFit/GPP day-spacing warnings"
affects: [21-04-crossfit-program-planner, 21-05-gpp-program-planner, 21-06-smart-program-planner-wiring]

# Tech tracking
tech-stack:
  added: []
  patterns:
    - "Rationale-bearing result-object pattern (CrossfitTimeCapResult / CrossfitComplexityResult) mirroring ExerciseScalingResolver's ScalingResolutionResult — every branch returns an explicit, human-readable rationale, never a silent default"
    - "Public accessor over private constant map (movementCeilingFor / _movementCountCeiling) so downstream files never re-declare their own copy of a shared policy number"

key-files:
  created:
    - lib/features/programs/domain/crossfit_scaling_policy.dart
    - test/features/programs/crossfit_scaling_policy_test.dart
  modified: []

key-decisions:
  - "Split the single implementation into two atomic commits (time-cap/complexity-ceiling, then recovery-reserve) by temporarily removing Task 2's method/tests before the Task 1 commit and re-adding them for Task 2, since both tasks share the same files_modified list."
  - "recoveryReserveWarning is documented as weekly-ScheduleMode-only by doc comment (not enforced by a type), matching the plan's explicit scope boundary since both shipped CrossFit/GPP split templates use ScheduleMode.weekly."

patterns-established:
  - "Pattern: CrossFit/GPP policy axes (time caps, complexity, spacing) live in one pure static-method service file, independent of drift/catalog, consulted by planner files rather than re-implemented inline."

requirements-completed: [CF-02]

# Metrics
duration: 25min
completed: 2026-09-26
---

# Phase 21 Plan 02: CrossFit Level-Policy Domain Service Summary

**Pure-Dart `CrossfitScalingPolicy` service providing per-level AMRAP/EMOM/For-Time time caps, a publicly-readable movement-count ceiling with advanced-movement-stacking guard, and an advisory back-to-back CrossFit/GPP day-spacing warning — all rationale-bearing, none silently defaulting.**

## Performance

- **Duration:** ~25 min
- **Started:** 2026-09-26T09:48:20Z
- **Completed:** 2026-09-26T10:08:28Z
- **Tasks:** 2 completed
- **Files modified:** 2 (both created new)

## Accomplishments
- `timeCapFor` scales AMRAP (base 600s) and For Time (base 720s) caps, and EMOM (base 12min) length, by a per-level multiplier (novice 0.75x, intermediate 1.0x, advanced 1.25x), with an explicit `.noCap` result for any other `SetType`.
- `movementCeilingFor` is the single public source of truth for the per-level movement-count ceiling (novice 2, intermediate 3, advanced 4) that `complexityCheck` enforces internally and that `crossfit_program_planner.dart` (Plan 21-04) will read directly.
- `complexityCheck` enforces the ceiling and a hard, level-independent rule blocking two or more advanced/just-unlocked movements from being stacked in one metcon.
- `recoveryReserveWarning` flags back-to-back CrossFit/GPP-labeled days (both adjacent days CrossFit-or-GPP-labeled) on weekly schedules as advisory warnings, explicitly scoped to `ScheduleMode.weekly`.

## Task Commits

Each task was committed atomically:

1. **Task 1: Time-cap-by-level and complexity-ceiling policy** - `5a8ebe5` (feat)
2. **Task 2: Recovery-reserve day-spacing check** - `8132a65` (feat)

**Plan metadata:** (this commit, to follow)

## Files Created/Modified
- `lib/features/programs/domain/crossfit_scaling_policy.dart` - `CrossfitScalingPolicy` pure static-method domain service: `timeCapFor`, `movementCeilingFor`, `complexityCheck`, `recoveryReserveWarning`, plus `CrossfitTimeCapResult`/`CrossfitComplexityResult` result types.
- `test/features/programs/crossfit_scaling_policy_test.dart` - 13 tests covering all four methods across all 3 experience levels and the adjacent/non-adjacent/mixed-label day-spacing cases.

## Decisions Made
- Committed Task 1 and Task 2 as two separate atomic commits despite both listing the same `files_modified` in the plan frontmatter, by temporarily stripping Task 2's method/tests, committing Task 1, then restoring and committing Task 2 — preserves per-task commit granularity without a messy partial-file state.
- No `ExperienceRecommendation`/catalog dependency was introduced; the file imports only `programming_models.dart` (for `ExperienceLevel`) and `set_type.dart` (for `SetType`), keeping it pure per the plan's threat model ("no DB, no I/O").

## Deviations from Plan

None - plan executed exactly as written. All behavior cases in the plan's `<behavior>` blocks (AMRAP/EMOM/For-Time caps at 3 levels, movement ceiling at 3 levels, complexity success/failure cases, advanced-movement-stacking guard, and all 3 recovery-reserve cases) are covered by passing tests.

## Issues Encountered
None.

## User Setup Required
None - no external service configuration required.

## Next Phase Readiness
- `CrossfitScalingPolicy.movementCeilingFor`, `.timeCapFor`, `.complexityCheck`, and `.recoveryReserveWarning` are ready for Plan 21-04 (`crossfit_program_planner.dart`) and Plan 21-06 (`smart_program_planner.dart` wiring) to consult directly.
- No blockers for subsequent Phase 21 plans.

---
*Phase: 21-crossfit-gpp-training-tracks*
*Completed: 2026-09-26*

## Self-Check: PASSED

- FOUND: lib/features/programs/domain/crossfit_scaling_policy.dart
- FOUND: test/features/programs/crossfit_scaling_policy_test.dart
- FOUND: 5a8ebe5 (Task 1 commit)
- FOUND: 8132a65 (Task 2 commit)
