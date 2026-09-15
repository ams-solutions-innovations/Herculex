---
phase: 17-deterministic-program-planner-hard-guardrails
plan: 04
subsystem: programs
tags: [drift, smart-program-planner, selection-explanation, program-slot-explanations]

# Dependency graph
requires:
  - phase: 17-01
    provides: "ProgramSlotExplanations table (schema v42), SelectionExplanation sealed filled/empty domain result type"
  - phase: 17-02
    provides: "SelectionExplanation.empty(...) produced by _resolveEmptyCandidatePool on hard-filter exhaustion, left unpersisted with a TODO(17-04) marker"
  - phase: 17-03
    provides: "the week-indexed RotationAssignments-building loop (assignments map) that Wave 3 reuses for the filled-slot rationale, plus the populate()-regeneration cascade-delete fix that keeps ProgramSlotExplanations consistent across regeneration"
provides:
  - "Every ProgramExerciseSlots row (filled or empty) gets a stable id, addressable by ProgramSlotExplanations' FK"
  - "_writeSlotExplanations (selection_explanation_writer.part.dart): one ProgramSlotExplanations row per slot per week, status 'filled'/'empty', chosenExerciseId set/null, rationale reused verbatim from RotationAssignmentData.reason or SelectionExplanation.rationale"
  - "PLAN-04 closed: the planner's selection rationale — for both a chosen exercise and a deliberate non-choice — is now queryable, not just implicit in whether a ProgramDayExercises row exists"
affects: [phase-19-program-wave-editor]

# Tech tracking
tech-stack:
  added: []
  patterns: ["part-file-scoped write helper (_writeSlotExplanations) shared by both the filled and empty call sites in _createStableSlots, mirroring the anchor_lock.part.dart / slot_candidate_resolution.part.dart split from prior waves"]

key-files:
  created:
    - lib/features/programs/data/smart_program_planner/selection_explanation_writer.part.dart
  modified:
    - lib/features/programs/data/smart_program_planner.dart
    - test/smart_program_planner_test.dart

key-decisions:
  - "The empty-slot ProgramExerciseSlots insert mirrors the filled-slot insert field-for-field (programId, slotKey, daySlotLabel, orderIndex, role, movementPattern, primaryMuscle, trainingMethod, rotationPolicyJson, fatigueBudget, waveOverrideWeeks) rather than a reduced field set, since the plan's own interfaces block specifies these describe the SLOT, not the chosen exercise, and are computable identically either way. This meant duplicating the small RotationPolicy computation (policy.forSlot + waveOverrideWeeks override + advanced-Max-Effort override) into the empty branch rather than hoisting it above the candidates.isEmpty check — hoisting would have changed the control flow more than necessary for a plan that only asked for persistence, not a restructure."
  - "_writeSlotExplanations takes the already-built assignments map (populated by 17-03's week loop) for the filled case rather than re-querying RotationAssignments, keeping it a pure in-memory write helper with one Future per Companion.insert, consistent with every other write in _createStableSlots."

requirements-completed: [PLAN-04]

# Metrics
duration: 45min
completed: 2026-09-15
---

# Phase 17 Plan 04: Persist ProgramSlotExplanations for Filled and Empty Slots Summary

**A new `_writeSlotExplanations` helper persists one `ProgramSlotExplanations` row per slot per week — `status: 'filled'` reusing the existing `RotationAssignments.reason`, or `status: 'empty'` reusing Wave 1's `SelectionExplanation.rationale` — and an empty slot now gets a stable `ProgramExerciseSlots` row so the explanation's FK has something to reference.**

## Performance

- **Duration:** 45 min
- **Started:** 2026-09-15T (worktree session start, approx)
- **Completed:** 2026-09-15
- **Tasks:** 1/1
- **Files modified:** 3 (1 created, 2 modified)

## Accomplishments
- A slot that hits Wave 1's (17-02) empty-candidate-pool path — every hard filter and the D-03 scaling-ladder regression exhausted — now gets a stable `ProgramExerciseSlots` row (mirroring the filled-slot insert field-for-field) instead of being skipped entirely, giving `ProgramSlotExplanations` a foreign key to reference.
- New `lib/features/programs/data/smart_program_planner/selection_explanation_writer.part.dart` defines `_writeSlotExplanations`, called from both the empty short-circuit and the filled-slot path after the week loop: for an empty slot it writes the identical rationale for every week of the program (the empty decision is made once per slot, before any week-specific resolution); for a filled slot it writes each week's already-persisted `RotationAssignmentData.reason` verbatim, not a newly invented string.
- Removed the `// TODO(17-04):` marker left by Wave 1 at the exact call site it flagged.
- PLAN-04 is closed: every generated slot, filled or empty, now has exactly one `ProgramSlotExplanations` row per program week, correctly reflecting status, chosen exercise (or null), and a human-readable rationale — enforced structurally by the `{slotId, weekIndex}` unique key from Wave 0 (17-01).

## Task Commits

Each task was committed atomically:

1. **Task 1: Give empty slots a stable ProgramExerciseSlots row, and write ProgramSlotExplanations for both filled and empty slots, every week** - `3b2bf51` (feat)

**Plan metadata:** committed separately per worktree-mode instructions (STATE.md/ROADMAP.md are NOT updated by this agent — the orchestrator handles that after merge).

## Files Created/Modified
- `lib/features/programs/data/smart_program_planner/selection_explanation_writer.part.dart` - New part file defining `_writeSlotExplanations`, the single write helper for both the filled and empty `ProgramSlotExplanations` cases.
- `lib/features/programs/data/smart_program_planner.dart` - Added the new part directive; the empty-slot short-circuit now inserts a `ProgramExerciseSlots` row (duplicating the small `RotationPolicy` computation needed for `rotationPolicyJson`, since the slot's candidate pool is empty and the normal computation site is unreached) and calls `_writeSlotExplanations` with `emptyExplanation` before `continue`; the filled-slot path calls `_writeSlotExplanations` with the populated `assignments` map right after the week-indexed `RotationAssignments` loop completes. Updated two stale doc comments on `_ResolvedSmartSlot.empty` and its `explanation` field that referenced the now-resolved `TODO(17-04)`.
- `test/smart_program_planner_test.dart` - New test group `ProgramSlotExplanations persistence for filled and empty slots (17-04 Task 1, PLAN-04)`: a `weeks: 3` Pull Day program with one hard-filter-exhausted main slot (empty) and one normally-resolved supplemental slot (filled). Asserts all 5 slot-need rows exist in `ProgramExerciseSlots`; the empty slot has exactly 3 `ProgramSlotExplanations` rows, all `status: 'empty'`, `chosenExerciseId: null`, sharing one non-empty rationale; the filled slot has exactly 3 rows, all `status: 'filled'`, each `chosenExerciseId` matching that week's `RotationAssignments.exerciseId`; and the total `ProgramSlotExplanations` row count for the program equals `(ProgramExerciseSlots rows) * weeks`.

## Decisions Made
- Mirrored the filled-slot `ProgramExerciseSlots` insert's full field list into the empty-slot branch rather than trimming it, per the plan's explicit instruction that these fields describe the slot itself and are computable identically either way (see key-decisions in frontmatter for the full rationale).
- Kept `_writeSlotExplanations` a pure write helper over an already-built `assignments` map for the filled case, rather than having it re-query `RotationAssignments` itself, to avoid a redundant read inside a `_db.transaction`.

## Deviations from Plan

None — plan executed exactly as written. The only implementation choice not spelled out verbatim in the plan's `<action>` text was where exactly to duplicate the `RotationPolicy` computation for the empty branch (see key-decisions), which is a direct, literal application of the plan's own "computable identically" guidance rather than a deviation from it.

## Issues Encountered
None.

## User Setup Required
None - no external service configuration required.

## Next Phase Readiness
- PLAN-04 (Phase 17's fourth and final named requirement) is fully satisfied. Every slot in a generated program — filled or empty — is now addressable via `ProgramExerciseSlots`, and every week of every slot has a matching, correctly-populated `ProgramSlotExplanations` row.
- This closes out the four plans of Phase 17 (17-01 through 17-04): schema (v42), hard filters with graceful empty-slot resolution, the anchor-lift guarantee with its D-12 safety override, and now full selection-rationale persistence.
- Full test suite: 1278 passed, 9 skipped, 0 failed (baseline 1277 + 1 new integration test). `flutter analyze`: 0 errors (40 pre-existing warnings/info, none in files touched by this plan). `dart run tool/check_structure.dart`: 59 violations, unchanged in kind from the pre-plan baseline — `smart_program_planner.dart` was already flagged over the 600-line ceiling before this plan (as noted in 17-02's summary) and grows further here (1490 → 1586 lines), but this is not a *new* file added to the violation list.
- No blockers identified for subsequent phases (Phase 18: Workout Time Budget, Warmups & Set Method Prescriptions).

---
*Phase: 17-deterministic-program-planner-hard-guardrails*
*Completed: 2026-09-15*

## Self-Check: PASSED

- FOUND: lib/features/programs/data/smart_program_planner/selection_explanation_writer.part.dart
- FOUND: .planning/phases/17-deterministic-program-planner-hard-guardrails/17-04-SUMMARY.md
- FOUND commit: 3b2bf51 (Task 1)
