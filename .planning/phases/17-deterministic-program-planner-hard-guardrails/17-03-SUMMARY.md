---
phase: 17-deterministic-program-planner-hard-guardrails
plan: 03
subsystem: programs
tags: [drift, smart-program-planner, rotation-policy, anchor-lock, deterministic-generation]

# Dependency graph
requires:
  - phase: 17-02
    provides: hard filters (injury/pain exclusion, prerequisite verification, graceful empty-slot resolution) on the same _createStableSlots candidate pipeline
provides:
  - "lockedAnchors bookkeeping (anchor_lock.part.dart) that pins every SlotRole.main slot to a single exercise across all weeks of a generated block (D-09/D-10)"
  - "D-12 safety override: a locked anchor no longer present in the current week's hard-filter pool breaks the lock and re-resolves safely"
  - "populate() now clears stale ProgramExerciseSlots (and cascaded pool members/rotation assignments/explanations) before rebuilding, making program regeneration on the same programId safe"
affects: [phase-19-program-wave-editor, phase-17-04]

# Tech tracking
tech-stack:
  added: []
  patterns: ["part-file-scoped in-memory bookkeeping map (lockedAnchors) passed by reference through a resolver function, mirroring the slot_candidate_resolution.part.dart split from 17-02"]

key-files:
  created:
    - lib/features/programs/data/smart_program_planner/anchor_lock.part.dart
  modified:
    - lib/features/programs/data/smart_program_planner.dart
    - test/smart_program_planner_test.dart

key-decisions:
  - "Anchor lock applies uniformly to every SlotRole.main slot regardless of training method, including Max Effort/Conjugate — matching the plan's explicit D-09/D-10 text ('every main-role slot') rather than carving out an exception for Max Effort's traditional weekly lift rotation. Updated the pre-existing four-day Conjugate test's assertion accordingly."
  - "populate() now deletes existing ProgramExerciseSlots for the programId before rebuilding them, since _createStableSlots always inserts fresh rows keyed by (programId, slotKey) and a second populate() call on the same program previously violated that unique constraint. Cascades (onDelete: cascade) clear ProgramSlotPoolMembers/RotationAssignments/ProgramSlotExplanations for the stale slots."

requirements-completed: [PLAN-03]

duration: 55min
completed: 2026-09-15
---

# Phase 17 Plan 03: Anchor-Lift Guarantee & D-12 Safety Override Summary

**`lockedAnchors` bookkeeping in a new `anchor_lock.part.dart` pins every `SlotRole.main` slot to one exercise for a whole generated block, with a hard-filter exclusion on regeneration breaking the lock instead of keeping an unsafe pick.**

## Performance

- **Duration:** 55 min
- **Started:** 2026-09-15T00:00:00Z (approx, worktree session start)
- **Completed:** 2026-09-15
- **Tasks:** 2/2
- **Files modified:** 3 (1 created, 2 modified)

## Accomplishments
- `SlotRole.main` slots now resolve to the identical `exerciseId` across every week of a single generated block, regardless of periodization model or training method (D-09/D-10), while non-main slots keep their existing per-week `RotationPolicy` variation untouched.
- A locked anchor that is no longer present in the current week's hard-filter-passing candidate pool (e.g. a new injury/pain exclusion) automatically breaks the lock and re-resolves to a fresh, safe pick — proven end-to-end by regenerating the same program with a new `excludedMuscles` entry (D-12).
- Fixed a latent bug that made program regeneration on the same `programId` impossible: `populate()` never cleared prior `ProgramExerciseSlots`, so a second call always hit a `UNIQUE(program_id, slot_key)` constraint violation. This is required for D-12's "next time the program is generated" scenario to be exercisable at all, and is now safe thanks to `onDelete: cascade` on `ProgramSlotPoolMembers`/`RotationAssignments`/`ProgramSlotExplanations`.

## Task Commits

Each task was committed atomically:

1. **Task 1: lockedAnchors bookkeeping intercepting the week loop for SlotRole.main** - `3fff9b5` (feat)
2. **Task 2: D-12 — a newly-injury-excluded anchor breaks the lock on regeneration** - `299af44` (fix, includes the regression test)

**Plan metadata:** (this commit) `docs(17-03): complete anchor-lift guarantee and D-12 safety override plan`

## Files Created/Modified
- `lib/features/programs/data/smart_program_planner/anchor_lock.part.dart` - New part file defining `_resolveWeeklyAssignment`, the pure function deciding whether a week's `RotationAssignments` row reuses the locked anchor, breaks the lock (D-12), or leaves non-main roles' existing rotation untouched.
- `lib/features/programs/data/smart_program_planner.dart` - Added the `anchor_lock.part.dart` part directive, a method-local `lockedAnchors` map in `_createStableSlots`, wired the week loop to call `_resolveWeeklyAssignment` instead of indexing `pool` directly, and added a `_db.delete(_db.programExerciseSlots)` step at the top of `populate()`'s transaction so regeneration on the same `programId` no longer violates the slot-key unique constraint.
- `test/smart_program_planner_test.dart` - Added a multi-week (`weeks: 4`) test proving the `SlotRole.main` single-exercise invariant across weeks; added a D-12 regression test that populates a program twice with an evolving `excludedMuscles` set and asserts the second generation's main slot never reuses the now-excluded exercise and remains itself consistently locked; updated the pre-existing four-day Conjugate test's final assertion from "different exercise week to week" to "same exercise", reflecting the new anchor-lock behavior applying to Max Effort main slots too.

## Decisions Made
- Anchor lock has no method-based exception (applies to Max Effort/Conjugate main slots as well as every other periodization model), per the plan's literal D-09/D-10 wording ("every main-role slot"). This changes the observable behavior of the pre-existing "four-day Conjugate" test, which previously asserted week-to-week ME rotation; that assertion was updated to match the new, explicitly-specified behavior rather than left failing or worked around.
- `populate()`'s new `ProgramExerciseSlots` delete-before-rebuild step is scoped to the whole `programId` (not per-day), mirroring the granularity at which the table's unique constraint operates, and relies entirely on existing FK cascades rather than manual multi-table deletes.

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 1 - Bug] Pre-existing "four-day Conjugate" test asserted the exact rotation behavior this plan explicitly redefines**
- **Found during:** Task 1, running `flutter test test/smart_program_planner_test.dart` after wiring `_resolveWeeklyAssignment` into the week loop
- **Issue:** The existing test `four-day Conjugate maps to two ME and two dynamic days` asserted `rotation[0].exerciseId` differs from `rotation[1].exerciseId` for a `SlotRole.main` Max Effort slot — the old week-to-week ME rotation behavior. The plan's D-09/D-10 text unconditionally anchors every `SlotRole.main` slot regardless of method, so this assertion is now testing behavior the plan intentionally removes.
- **Fix:** Updated the assertion to `expect(rotation[0].exerciseId, rotation[1].exerciseId)` with a comment explaining the D-09/D-10 supersession.
- **Files modified:** test/smart_program_planner_test.dart
- **Verification:** `flutter test test/smart_program_planner_test.dart` passes with the updated assertion; no other assertions in that test changed.
- **Committed in:** 3fff9b5 (Task 1 commit)

**2. [Rule 1/3 - Bug/Blocking] `populate()` could not be called twice on the same `programId`**
- **Found during:** Task 2, writing the D-12 regression test (which calls `SmartProgramPlanner.populate()` twice on the same `programId` per the task's explicit action)
- **Issue:** `populate()` never deleted existing `ProgramExerciseSlots` rows before re-inserting new ones inside `_createStableSlots`. A second `populate()` call on the same program threw `SqliteException(2067): UNIQUE constraint failed: program_exercise_slots.program_id, program_exercise_slots.slot_key`. This directly blocked Task 2, whose entire test scenario requires regenerating the same program.
- **Fix:** Added `await (_db.delete(_db.programExerciseSlots)..where((t) => t.programId.equals(programId))).go();` at the top of `populate()`'s transaction, before the week loop. Existing `onDelete: KeyAction.cascade` foreign keys on `ProgramSlotPoolMembers`, `RotationAssignments`, and `ProgramSlotExplanations` (all referencing `ProgramExerciseSlots.id`) clear their rows automatically.
- **Files modified:** lib/features/programs/data/smart_program_planner.dart
- **Verification:** `flutter test test/smart_program_planner_test.dart` passes, including the new D-12 test that calls `populate()` twice; full `flutter test` run (1277 passed, 9 skipped, 0 failed) confirms no regression elsewhere.
- **Committed in:** 299af44 (Task 2 commit)

**3. [Rule 1 - Bug] Test fixture's default `cnsScore` accidentally made a filler exercise main-eligible**
- **Found during:** Task 2, first run of the D-12 regression test
- **Issue:** The new test's local `insertExercise` helper defaulted `cnsScore: 5`, which combined with the default `modality: 'barbell'` and `mechanics: 'compound'` made the `horizontal-pull-accessory-filler` exercise unintentionally satisfy `SlotRole.main` eligibility alongside the two intended candidates, producing a three-candidate pool instead of two and breaking the test's "the other candidate" assertion.
- **Fix:** Changed the helper's default `cnsScore` to `3` (below the `SlotRoleEligibility` main-eligibility threshold of 5) and explicitly set `cnsScore: 5` only on the two intended main-eligible candidates, matching the same pattern already used by the Task 3 (17-02) fixture group in this file.
- **Files modified:** test/smart_program_planner_test.dart
- **Verification:** `flutter test test/smart_program_planner_test.dart` passes deterministically.
- **Committed in:** 299af44 (Task 2 commit, test was not yet committed separately)

---

**Total deviations:** 3 auto-fixed (1 test-update-for-redefined-behavior, 1 blocking bug fix, 1 test-fixture bug)
**Impact on plan:** All three were necessary to make the plan's own explicitly-specified behavior (D-09/D-10 applying to every main-role slot, and D-12's regeneration scenario) actually testable and correct. No scope creep beyond what Task 1/2's own `<action>` blocks required.

## Issues Encountered
None beyond the deviations documented above.

## User Setup Required
None - no external service configuration required.

## Next Phase Readiness
- Anchor-lift guarantee (D-09/D-10) and its D-12 safety override are complete and covered by tests; Wave 3 (17-04, `ProgramSlotExplanations` persistence for empty slots) can build on this without further changes here.
- The `populate()` regeneration fix (clearing stale `ProgramExerciseSlots`) is a prerequisite for any future "regenerate this program" UI flow (e.g. Phase 19's editor) and is now safe to call repeatedly on the same `programId`.
- No blockers identified for subsequent phases.

---
*Phase: 17-deterministic-program-planner-hard-guardrails*
*Completed: 2026-09-15*

## Self-Check: PASSED

- FOUND: lib/features/programs/data/smart_program_planner/anchor_lock.part.dart
- FOUND: .planning/phases/17-deterministic-program-planner-hard-guardrails/17-03-SUMMARY.md
- FOUND commit: 3fff9b5 (Task 1)
- FOUND commit: 299af44 (Task 2)
