---
phase: 21-crossfit-gpp-training-tracks
plan: 08
subsystem: training-programs
tags: [drift, program-generation, crossfit, safety-guardrails, flutter-test]

# Dependency graph
requires:
  - phase: 21-crossfit-gpp-training-tracks
    provides: "CrossfitScalingPolicy.complexityCheck (Plan 21-02), CrossfitProgramPlanner.segmentNeedsFor (Plan 21-04), _createStableSlots segment wiring (Plan 21-06)"
provides:
  - "Real production call site for CrossfitScalingPolicy.complexityCheck inside SmartProgramPlanner._createStableSlots"
  - "Candidate-pool substitution that prevents 2+ advanced/just-unlocked movements stacking in one CrossFit metcon (D-06 hard rule), with real fallback when a safe substitute exists"
  - "Explicit, non-silent rationale recorded in ProgramDayExercises.prescriptionWhy when no safe substitute exists"
affects: [21-verification, future-crossfit-gpp-work]

# Tech tracking
tech-stack:
  added: []
  patterns:
    - "Per-metconGroupKey movement/advanced-movement tracking maps scoped to a single _createStableSlots call, mirroring the existing `used`/`lockedAnchors` convention"
    - "Candidate-pool substitution filter applied immediately before scoring (not a post-hoc rejection), so the scorer is never even offered an unsafe second pick when a safe one exists"

key-files:
  created: []
  modified:
    - lib/features/programs/data/smart_program_planner.dart
    - test/features/programs/smart_program_planner_test.dart

key-decisions:
  - "Used ExerciseCatalogData.prerequisiteSlugs ('just-unlocked') rather than programmingDifficulty: 'advanced' to exercise the guard in tests at ExperienceLevel.novice, because ExerciseProgrammingEligibility.allows hard-excludes 'advanced'-difficulty exercises from a novice's candidate pool before the guard ever runs"
  - "Forced-exception test seeds every CrossFit-eligible fixture as just-unlocked (via a style-mismatched prereq anchor exercise that can never itself be picked for a CrossFit slot), since CrossFit/GPP segment needs share an identical role/pattern/muscle-less eligibility mask and any fixture can land in any segment slot"

patterns-established:
  - "When testing scorer-driven slot assignment for segment-tagged (CrossFit/GPP) days, structure fixture pools so the desired invariant holds under ANY scorer assignment permutation, rather than assuming slug names map to specific segments"

requirements-completed: [CF-02]

# Metrics
duration: 45min
completed: 2026-09-27
---

# Phase 21 Plan 08: D-06 Metcon Stacking Guard Wiring Summary

**Wired the previously-unused `CrossfitScalingPolicy.complexityCheck` into `_createStableSlots`'s metcon slot resolution, with real candidate-pool substitution and an explicit, non-silent exception record when no safe substitute exists.**

## Performance

- **Duration:** ~45 min
- **Started:** 2026-09-27T11:48:00Z (approx.)
- **Completed:** 2026-09-27T12:33:07Z
- **Tasks:** 2
- **Files modified:** 2

## Accomplishments
- `CrossfitScalingPolicy.complexityCheck` now has a real, reachable production call site inside `_createStableSlots`, closing VERIFICATION.md gap #1 for Phase 21.
- A metcon slot's own candidate pool is filtered to exclude a second advanced/just-unlocked movement once one is already committed for the same `metconGroupKey`, but only when a safe (non-advanced/non-just-unlocked) alternative genuinely exists in that pool — a real substitution, not a passive check.
- When no safe substitute exists, `complexityCheck`'s `exceedsCeiling` rationale plus an explicit "no safe substitute" note is appended to the slot's `why`, which flows unchanged into `ProgramDayExercises.prescriptionWhy` — the exception is now observable, not silently accepted.
- Two new regression tests prove both branches fire, independent of the scorer's jitter-based tie-break outcome.

## Task Commits

Each task was committed atomically:

1. **Task 1: Wire CrossfitScalingPolicy.complexityCheck into _createStableSlots with real substitution** - `34b070e` (feat)
2. **Task 2: Add regression tests proving the stacking guard and the accepted-exception rationale both fire** - `b688801` (test)

## Files Created/Modified
- `lib/features/programs/data/smart_program_planner.dart` - Added `metconGroupMovementCount`/`metconGroupAdvancedCount` tracking maps, `_isCrossfitAdvancedOrJustUnlocked` helper, a candidate-pool substitution filter before scoring, and a `complexityCheck` call site after anchor selection that appends an explicit exception note to `why` when unsafe.
- `test/features/programs/smart_program_planner_test.dart` - Extended `insertExercise` with `programmingDifficulty`/`prerequisiteSlugsJson` params; added two regression tests to the `'CrossFit/GPP segment wiring (CF-01/CF-02/CF-03)'` group.

## Decisions Made
- **`prerequisiteSlugs` over `programmingDifficulty: 'advanced'` for novice-level test fixtures.** The plan's literal instruction was to mark test fixtures `programmingDifficulty: 'advanced'` at `ExperienceLevel.novice`. Investigation showed `ExerciseProgrammingEligibility.allows` hard-gates `'advanced'`-difficulty exercises out of a novice's candidate pool entirely (`_difficultyRank('advanced')=2 > _experienceRank(novice)=0`), so such fixtures would never reach `_createStableSlots`'s candidate list at all — the stacking guard could never be exercised this way. Switched to `prerequisiteSlugs` ("just-unlocked" per the plan's own interface notes), which passes the difficulty gate while still tripping `_isCrossfitAdvancedOrJustUnlocked`.
- **Forced-exception test seeds the entire CrossFit-eligible pool as just-unlocked.** `CrossfitProgramPlanner.segmentNeedsFor` gives every segment (warmup/skill/strength/metcon/cooldown) an identical role mask with no pattern/muscle hint, so the scorer's deterministic tie-break can route any generic fixture to any segment slot — slug names are cosmetic, not a routing guarantee. To make "no safe substitute exists" true regardless of which fixture the scorer assigns to which segment, every CrossFit-tagged fixture in that test references a real, satisfied, but never-CrossFit-eligible prerequisite anchor (style-mismatched so it can never itself be picked for a CrossFit slot).

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 1 - Bug] Test fixture design corrected to actually reach the code path under test**
- **Found during:** Task 2, first test run
- **Issue:** Following the plan's literal `programmingDifficulty: 'advanced'` fixture instruction at `ExperienceLevel.novice` produced fixtures that were filtered out of the candidate pool entirely by the pre-existing `ExerciseProgrammingEligibility.allows` difficulty gate, before `_createStableSlots`'s stacking guard ever ran. The forced-exception test additionally suffered from CrossFit segment needs sharing an identical eligibility mask (no pattern/muscle distinction), so a small mixed pool of "metcon-tagged" vs. "other-tagged" fixtures let the scorer route the two intentionally-unsafe fixtures into non-metcon slots, undershooting the intended stacked scenario.
- **Fix:** Switched to `prerequisiteSlugs`-based "just-unlocked" fixtures (satisfied via experience-rank match against a real prerequisite, no history needed) for both tests. For the forced-exception test, made every CrossFit-eligible fixture in the gym just-unlocked, referencing a style-mismatched (never-CrossFit-eligible) prerequisite anchor, so the invariant holds regardless of scorer assignment.
- **Files modified:** `test/features/programs/smart_program_planner_test.dart`
- **Verification:** `flutter test test/features/programs/smart_program_planner_test.dart` — 11/11 passing, confirmed via debug prints (since removed) that both branches actually execute.
- **Committed in:** `b688801` (Task 2 commit)

---

**Total deviations:** 1 auto-fixed (1 bug fix in test design)
**Impact on plan:** Necessary correction to make the tests actually exercise the guard's two branches; no production code (`lib/`) deviated from the plan's design.

## Issues Encountered
- Initial test runs (with `programmingDifficulty: 'advanced'` fixtures per the plan's literal wording) produced misleading failures: one showed rows silently disappearing (day's other segments were being resolved with the "advanced" fixtures never eligible for a novice at all, forcing empty-slot fallbacks and time-budget trimming to remove even more rows), and the other showed the intended rationale simply never appearing because the two "unsafe" fixtures landed in non-metcon segments. Both were resolved by switching to the `prerequisiteSlugs`-based approach described above.

## User Setup Required

None - no external service configuration required.

## Next Phase Readiness
- VERIFICATION.md gap #1 for Phase 21 is closed: `CrossfitScalingPolicy.complexityCheck` is now wired, tested, and observable end-to-end via `ProgramDayExercises.prescriptionWhy`.
- No further action needed on this gap; Phase 21 verification can proceed.

---
*Phase: 21-crossfit-gpp-training-tracks*
*Completed: 2026-09-27*

## Self-Check: PASSED

All claimed files (`lib/features/programs/data/smart_program_planner.dart`, `test/features/programs/smart_program_planner_test.dart`, this SUMMARY.md) exist on disk. Both task commits (`34b070e`, `b688801`) verified present in `git log`.
