---
phase: 17-deterministic-program-planner-hard-guardrails
plan: 02
subsystem: programs
tags: [smart-program-planner, drift, exercise-eligibility, scaling-resolver]

# Dependency graph
requires:
  - phase: 17-deterministic-program-planner-hard-guardrails
    provides: "SelectionExplanation sealed filled/empty domain result type, JointModel.excludedMusclesFor, ProgramSlotExplanations table (17-01)"
provides:
  - "ExerciseProgrammingEligibility.allows extended with a hard, non-relaxable primaryMuscle/excludedMuscles gate (D-06)"
  - "SmartProgramConfiguration.excludedMuscles, resolved once per populate() call from JointPainRepository.watchCurrentStatuses() in block_builder_view.dart"
  - "verifyPrerequisites wired as a hard gate into both SmartProgramPlanner candidate-filter passes, backed by full 'ever completed' exercise/movement history"
  - "_resolveEmptyCandidatePool: a hard-filter-exhausted slot consults ExerciseScalingResolver for a safer regression before resolving to SelectionExplanation.empty(...) instead of throwing StateError"
  - "ProgramGenerationRequest deleted — SmartProgramConfiguration is the sole generation-parameter type"
affects: [17-03, 17-04, 17-05]

# Tech tracking
tech-stack:
  added: []
  patterns:
    - "part-file candidate-resolution logic (smart_program_planner/slot_candidate_resolution.part.dart) kept separate from the parent file's orchestration code"
    - "zero-equipment isolated-gym fixture pattern for synthetic, catalog-independent SmartProgramPlanner integration tests, since AppDatabase.forTesting's onCreate always seeds the full real exercise catalog"

key-files:
  created:
    - lib/features/programs/data/smart_program_planner/slot_candidate_resolution.part.dart
  modified:
    - lib/features/programs/domain/exercise_programming_eligibility.dart
    - lib/features/programs/domain/programming_models.dart
    - lib/features/programs/data/smart_program_planner.dart
    - lib/features/programs/presentation/views/block_builder_view.dart
    - test/exercise_programming_eligibility_test.dart
    - test/smart_program_planner_test.dart

key-decisions:
  - "A fresh AppDatabase.forTesting is not catalog-empty (onCreate always runs ExerciseImporter.runFromAsset); new fixture-based integration tests isolate synthetic exercises from the ~150-row real catalog via a default gym with allEquipment:false and zero gymEquipment rows, combined with requiredEquipmentKeys:'[]' on fixture rows — every real catalog exercise needs at least one equipment key (even bodyweight falls back to the modality), so this hard-excludes all of them via the ordinary equipment gate."
  - "The genuinely-empty-slot test targets the horizontal_pull movement pattern specifically because no real catalog exercise carries that pattern with a scaling ladder attached (verified against assets/data/exercise_programming_metadata.json), cleanly exercising the 'no ladder for this pattern' branch rather than the 'ladder exists but every regression fails equipment' branch."
  - "_ResolvedSmartSlot.id is a placeholder (-1) for an empty slot — never read, since populate()'s per-slot loop always `continue`s before reaching the row insert once anchorExerciseId is null. No ProgramExerciseSlots row is written for an empty slot yet; that lands in Wave 3 (17-04) per the plan's own TODO note."

patterns-established:
  - "Pattern: candidate-filter hard gates (injury/pain, prerequisites) apply identically in both the primary and pattern/muscle-relaxed fallback passes — only pattern/muscle itself is ever relaxed."

requirements-completed: [PLAN-01, PLAN-02]

# Metrics
duration: ~2h40min
completed: 2026-09-15
---

# Phase 17 Plan 02: Deterministic Planner Hard Guardrails Summary

**All five named hard filters (injury/pain, equipment, style, experience, prerequisites) are now genuinely absolute in `SmartProgramPlanner`, and a legitimately hard-filter-exhausted slot resolves to a graceful `SelectionExplanation.empty(...)` (after consulting the D-03 scaling ladder) instead of throwing `StateError` and aborting the whole program-generation transaction.**

## Performance

- **Duration:** ~2h40min
- **Started:** 2026-09-14T19:30:00Z (approx)
- **Completed:** 2026-09-15T02:10:00Z (approx)
- **Tasks:** 3/3 completed
- **Files modified:** 6 (1 created, 5 modified)

## Accomplishments
- `ExerciseProgrammingEligibility.allows` gained a hard, non-relaxable `primaryMuscle`/`excludedMuscles` gate (D-06); a missing muscle never participates either way. `SmartProgramConfiguration.excludedMuscles` threads it through `_isEligibleForAutomaticProgramming`, resolved once per `populate()` call in `block_builder_view.dart` from `JointPainRepository.watchCurrentStatuses()` via `JointModel.excludedMusclesFor` (D-05/D-07).
- Deleted the dead `ProgramGenerationRequest` class, closing PLAN-01: `SmartProgramConfiguration` is confirmed as the sole generation-parameter type in the codebase.
- Wired `ExerciseProgrammingEligibility.verifyPrerequisites` as a hard gate into both the primary and pattern/muscle-relaxed fallback candidate-filter blocks in `_createStableSlots`, backed by a new `_completedMovementHistory()` method resolving the full "ever completed" exercise/movement-slug set (not recency-bounded, mirroring `getRecentExerciseIds`'s join/where pattern without its 50-row limit).
- Replaced the `throw StateError(...)` crash-on-exhaustion path with `_resolveEmptyCandidatePool` (new `slot_candidate_resolution.part.dart`): when both candidate-filter passes are empty, it consults `ExerciseScalingResolver.regress` for a safer regression before accepting the slot is genuinely empty (D-01/D-03). `_ResolvedSmartSlot` gained an `.empty(...)` named constructor and a nullable `anchorExerciseId`; `populate()`'s per-slot loop now skips writing a `ProgramDayExercises` row for an empty slot instead of crashing, and every other slot on the same day/week still resolves normally.

## Task Commits

Each task was committed atomically:

1. **Task 1: Injury/pain hard gate on ExerciseProgrammingEligibility, and wire it end-to-end from block_builder_view** - `494f1f1` (feat)
2. **Task 2: Wire prerequisites verification into the planner's candidate filter** - `312a405` (feat)
3. **Task 3: Replace crash-on-exhaustion with a graceful empty-slot result, consulting the scaling ladder first (D-01/D-03)** - `18b73e2` (feat)

**Plan metadata:** committed separately per worktree-mode instructions (STATE.md/ROADMAP.md are NOT updated by this agent).

## Files Created/Modified
- `lib/features/programs/domain/exercise_programming_eligibility.dart` - `allows()` extended with `primaryMuscle`/`excludedMuscles` hard gate (D-06)
- `lib/features/programs/domain/programming_models.dart` - Deleted the unused `ProgramGenerationRequest` class and its now-unused imports
- `lib/features/programs/data/smart_program_planner.dart` - `SmartProgramConfiguration.excludedMuscles`; `_completedMovementHistory()`; prerequisite hard gate in both candidate-filter blocks; empty-slot resolution call site; `_ResolvedSmartSlot.empty(...)`; `part` directive for the new resolution file
- `lib/features/programs/data/smart_program_planner/slot_candidate_resolution.part.dart` - `_resolveEmptyCandidatePool`, consulting `ExerciseScalingResolver.regress` before declaring a slot empty
- `lib/features/programs/presentation/views/block_builder_view.dart` - Resolves `excludedMuscles` from `JointPainRepository` before every Smart/Guided `populate()` call
- `test/exercise_programming_eligibility_test.dart` - Three new tests covering the `excludedMuscles` hard gate's three `<behavior>` cases
- `test/smart_program_planner_test.dart` - New fixture-isolated integration test groups for prerequisite wiring (Task 2) and empty-slot/scaling-regression resolution (Task 3)

## Decisions Made
- Isolated new fixture-based integration tests from the real, always-seeded exercise catalog using a `allEquipment:false` gym with zero `gymEquipment` rows plus `requiredEquipmentKeys:'[]'` on fixture rows, rather than assuming a catalog-empty test database (see key-decisions above for the full rationale).
- Chose the `horizontal_pull` movement pattern for the "genuinely empty, no ladder" test specifically because it has zero real-catalog scaling-ladder entries, cleanly isolating the "no ladder for this pattern" code path from the "ladder exists but regression fails" path exercised by the companion "successful regression" test.
- `_ResolvedSmartSlot.empty`'s placeholder `id: -1` is intentional and never read (Wave 3/17-04 will add the `ProgramExerciseSlots` row for empty slots, per the plan's own `TODO(17-04)` marker left at that exact call site).

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 1 - Bug] Removed now-unused imports left behind by deleting `ProgramGenerationRequest`**
- **Found during:** Task 1, `flutter analyze` pass
- **Issue:** `programming_models.dart` imported `periodization.dart` and `split_template.dart` solely for the deleted `ProgramGenerationRequest` class's field types, triggering `unused_import` warnings after deletion.
- **Fix:** Removed both now-unused import lines.
- **Files modified:** `lib/features/programs/domain/programming_models.dart`
- **Verification:** `flutter analyze lib/features/programs/domain/programming_models.dart` — 0 issues.
- **Committed in:** `494f1f1` (Task 1 commit)

**2. [Rule 1 - Bug] Fixed `directives_ordering` lint in an existing, unrelated import block**
- **Found during:** Task 2, `flutter analyze` pass
- **Issue:** `test/smart_program_planner_test.dart`'s pre-existing import list was not fully alphabetized (`primary_lift_specialization.dart` after `squat_specialization.dart`), a pre-existing issue exposed once the file was touched.
- **Fix:** Reordered the two import lines alphabetically.
- **Files modified:** `test/smart_program_planner_test.dart`
- **Verification:** `flutter analyze` — 0 issues.
- **Committed in:** `312a405` (Task 2 commit)

**3. [Rule 1 - Bug] `_ResolvedSmartSlot`'s optional `explanation` parameter was unused on the primary constructor**
- **Found during:** Task 3, `flutter analyze` pass
- **Issue:** Adding `this.explanation` as an optional named parameter on the primary `const` constructor triggered `unused_element_parameter` since no call site outside `.empty(...)` ever passes it.
- **Fix:** Moved `explanation` off the primary constructor's parameter list; it is now set via an initializer (`explanation = null`) instead, keeping the field final and non-optional-parameter-shaped on the common path.
- **Files modified:** `lib/features/programs/data/smart_program_planner.dart`
- **Verification:** `flutter analyze` — 0 issues.
- **Committed in:** `18b73e2` (Task 3 commit)

---

**Total deviations:** 3 auto-fixed (all Rule 1 bugfixes/lint cleanups, all within this plan's own task files)
**Impact on plan:** All three fixes were required to satisfy this plan's own `<verify>`/acceptance criteria (`flutter analyze` 0 errors for touched files). No scope creep.

## Issues Encountered

**Test-fixture design required more care than the plan's action text anticipated.** `AppDatabase.forTesting`'s `onCreate` migration hook always runs `ExerciseImporter.runFromAsset`, so every "fresh" test database already contains the full ~150-row real exercise catalog — a hand-built two/three-exercise fixture is never actually catalog-*empty*, only catalog-*additional*. The plan's Task 2/3 action text (`db.into(db.exerciseCatalog).insert(...)`) is correct as written, but achieving deterministic, real-catalog-independent assertions required an additional isolation mechanism (the zero-equipment gym pattern documented above) not spelled out in the plan. This was worked out and validated empirically (including one throwaway diagnostic test, `test/zz_inspect_scaling_tmp_test.dart`, written to dump real scaling-ladder metadata and deleted before any commit — no trace remains in the three task commits) rather than being a plan defect requiring escalation.

**`smart_program_planner.dart` grew beyond its pre-plan line count.** The `<verification>` section states the file "does not grow past its current line count in this plan (new logic moves into the part file)." In practice, Tasks 1-3's own action text directs several additions squarely into the parent file itself (the `excludedMuscles` field and doc comment, `_completedMovementHistory()`, the prerequisite checks in both filter blocks, the empty-slot resolution call site, and `_ResolvedSmartSlot`'s new constructor/field) — only the `_resolveEmptyCandidatePool` function body itself was extractable into the part file. The file grew from 1353 to 1490 lines (+137); the new part file is a clean 71 lines. `smart_program_planner.dart` was already over the project's 600-line hand-written-file ceiling before this plan (one of the 51 files CLAUDE.md already tracks as exceeding it), so this does not introduce a *new* `dart run tool/check_structure.dart` violation — it was already flagged, and remains flagged, independent of this plan's change.

## User Setup Required

None - no external service configuration required.

## Next Phase Readiness

- Injury/pain, equipment, style, experience, and prerequisites are all real, wired, hard (never-relaxed) filters in `SmartProgramPlanner`'s candidate resolution.
- A hard-filter-exhausted slot now resolves gracefully (`SelectionExplanation.empty(...)` after a D-03 scaling-ladder consult) instead of aborting the whole `populate()` transaction — this is the exact mechanism Wave 3 (17-04) will persist into `ProgramSlotExplanations` via the `TODO(17-04)` marker left at the precise call site in `_createStableSlots`.
- `ProgramGenerationRequest` no longer exists; `SmartProgramConfiguration` is the confirmed single entry point for all program-generation parameters.
- Full test suite (`flutter test`) passes clean: 1275 passed, 9 skipped, 0 failed (baseline 1269 passed + 6 new tests added by this plan). `flutter analyze` reports 0 errors (9 pre-existing warnings, all in files untouched by this plan).

---
*Phase: 17-deterministic-program-planner-hard-guardrails*
*Completed: 2026-09-15*

## Self-Check: PASSED

All 7 files listed under "Files Created/Modified" verified present on disk.
All 3 task commit hashes (`494f1f1`, `312a405`, `18b73e2`) verified present
in `git log`. Full `flutter test` run: 1275 passed, 9 skipped, 0 failed.
`flutter analyze`: 0 errors (9 pre-existing warnings, none in files touched
by this plan).
