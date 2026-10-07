---
phase: 28-adaptive-tdee-activity-calibration
plan: 02
subsystem: nutrition
tags: [tdee, macro-targets, target-resolver, refactor, dart]

requires: []
provides:
  - "MacroTargets.bmr / multiplierFor / goalDeltaKcal / seedMaintenanceKcal / fromMaintenance (shared maintenance -> goal-adjusted macro path)"
  - "Characterization test pinning fromProfile output for all 32 ActivityLevel x FitnessGoal x BiologicalSex combinations"
  - "TargetResolver regression test proving a saved manual rule always beats the fallback (TDEE-04)"
affects: [28-07, 28-08]

tech-stack:
  added: []
  patterns:
    - "Characterization test holds an independent verbatim copy of the legacy formula, written and run green before the refactor"
    - "Goal delta lives in exactly one function (fromMaintenance); estimators persist pure maintenance"

key-files:
  created:
    - test/macro_targets_test.dart
    - test/target_resolver_test.dart
  modified:
    - lib/features/nutrition/domain/macro_targets.dart

key-decisions:
  - "Estimate is always PURE maintenance; fromMaintenance adds the -500/+300/0 goal delta exactly once when a daily fallback target is needed"
  - "seedMaintenanceKcal (bmr x onboarding multiplier, no goal delta) is the D-08 cold-start figure; fromProfile = fromMaintenance(seedMaintenanceKcal) preserves today's fallback behaviour"
  - "No isManual flag added to TargetRule; TDEE-04 is proven by test against the existing resolver"

patterns-established:
  - "fromMaintenance(profile, maintenanceKcal) is the entry point plan 07 uses for measured/classified estimates"

requirements-completed: [TDEE-02, TDEE-04]

duration: 8min
completed: 2026-09-28
---

# Phase 28 Plan 02: MacroTargets Split and Resolver Regression Summary

**`MacroTargets.fromProfile` split into bmr / multiplierFor / goalDeltaKcal / seedMaintenanceKcal / fromMaintenance with byte-identical output, plus a new TargetResolver test locking "manual target always wins".**

## Performance

- **Duration:** ~8 min
- **Started:** 2026-09-28T12:41:43Z
- **Completed:** 2026-09-28T12:46:00Z
- **Tasks:** 2
- **Files modified:** 3 (2 created, 1 modified)

## Accomplishments

- Wrote the characterization test first and ran it green against the untouched formula (32 combinations plus the null guard), then refactored. `fromProfile` is unchanged for every combination, so all 14 call sites keep working.
- `fromMaintenance` is now the single place the goal delta is added and the macro split lives. `goalDeltaKcal` appears only in its definition and in `fromMaintenance` (grep count 2).
- `test/target_resolver_test.dart` (7 cases): rule beats fallback, result identical across fallback values (1800 vs 3400), fallback used only when no rule matches, non-matching scopes ignored, specificity order, diet schedule still applied on top of the winning rule. No production change to `target_resolver.dart`.
- Fixed the stale "Assumes male" doc comment on `fromProfile`.

## Task Commits

1. **Task 1: Characterization test + split macro_targets.dart** - `a22007a` (refactor)
2. **Task 2: TargetResolver regression test** - `befd71f` (test)

## Files Created/Modified

- `lib/features/nutrition/domain/macro_targets.dart` - new public statics; `fromProfile` delegates.
- `test/macro_targets_test.dart` - characterization plus tests for every new static (11 tests).
- `test/target_resolver_test.dart` - TDEE-04 precondition (7 tests).

## Decisions Made

- Design note for CONTEXT D-08: the cold-start number is `seedMaintenanceKcal` (Mifflin-St Jeor x onboarding ActivityLevel, no goal delta). The goal delta appears only in `fromMaintenance` / `fromProfile` for the fallback daily target, which keeps today's behaviour for users with no saved target. Maintenance-labelled consumers (editor field, phase planner) read pure maintenance in plan 08.

## Deviations from Plan

None - plan executed as written. The plan's TDD RED step for Task 1 was folded into the same commit as the refactor (the characterization test was verified green before touching the source, and the new-API tests were verified failing to compile before implementation), so no separate `test(...)` commit precedes the `refactor(...)` commit.

## Issues Encountered

None. `flutter analyze` (whole repo) reports 42 issues, all info/warning level, 0 errors; none are in files this plan touched.

## Known Stubs

None.

## Threat Flags

None. T-28-05 (carbs clamp, null on missing weight), T-28-06 (rule-wins test) and T-28-07 (single goal-delta site, pinned by characterization test) are all mitigated as planned.

## Next Phase Readiness

`fromMaintenance` is available for plan 07 to turn measured/classified maintenance into fallback targets. TDEE-04's resolver guarantee is under regression test.

## Self-Check: PASSED

- FOUND: test/macro_targets_test.dart, test/target_resolver_test.dart, lib/features/nutrition/domain/macro_targets.dart
- FOUND commits: a22007a, befd71f
- `flutter test test/macro_targets_test.dart test/target_resolver_test.dart test/diet_phase_test.dart`: 35 passed.
