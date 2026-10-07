---
phase: 27-herculex-ai-program-generation
plan: 13
subsystem: ui
tags: [flutter, riverpod, drift, gemini, ai]

# Dependency graph
requires:
  - phase: 27-herculex-ai-program-generation
    provides: "27-11's ProgramBuildMode.herculexAi, _acceptedHerculexBrief/_herculexBriefProvenance state fields, and the Generate/Regenerate flow; 27-09's HerculexAiBriefService.persistBrief()"
provides:
  - "Herculex AI mode is complete end-to-end: mode selection, generation, guardrail validation, pre-fill into existing editable Step 1-5 screens, user override capability preserved, persisted brief with provenance on creation, and per-day rationale visible on the review screen (27-12) before explicit confirmation"
  - "JointPainRepository.currentStatuses() — a one-shot equivalent of watchCurrentStatuses(), fixing a pre-existing FakeAsync-hang bug in _create()'s non-manual success path"
affects: [25]

# Tech tracking
tech-stack:
  added: []
  patterns:
    - "Accepted AI brief -> existing Dream Physique tuning seam (D-01): convert brief.musclePriorities to the same muscleId -> wireValue map _loadDreamPhysiquePriorities() would build, assign to _dreamPhysiquePriorities, call the unchanged _applyDreamPhysiqueTuning() — zero new apply logic"
    - "One-shot repository read (Future<T>) alongside an existing Stream<T> watch method, for imperative one-time call sites — same fix shape as 27-09/27-12's HerculexAiBriefService.readActiveBriefForProgram()"

key-files:
  created: []
  modified:
    - lib/features/programs/presentation/views/block_builder_view.dart
    - lib/features/programs/presentation/views/block_builder_view/actions.part.dart
    - lib/features/recovery/data/joint_pain_repository.dart
    - test/block_builder_view_test.dart
    - test/joint_pain_repository_test.dart

key-decisions:
  - "phaseIntent is surfaced via 27-11's existing mode-picker tile subtitle (already reads _acceptedHerculexBrief!.phaseIntent) rather than a new _herculexPhaseIntent state field — the plan's own suggested field was one option among several; reusing the object already held avoids a redundant field."
  - "_split/_model are assigned AFTER _applyDreamPhysiqueTuning() (which internally calls _applySmartDefaults() and would otherwise overwrite _model from _goal/_experience), so the brief's own periodizationModel wins, per the plan's explicit ordering requirement."
  - "persistBrief() failures are swallowed inside their own try/catch, never rethrown into _create()'s outer catch — a persistence failure must never delete an otherwise-successfully-created program (D-08, T-27-20)."
  - "Fixed JointPainRepository.watchCurrentStatuses().first hanging under widget-test FakeAsync by adding a one-shot currentStatuses() method and switching _create()'s single call site to it — this bug predates this plan but was only exposed once a test finally exercised the full non-manual create-block success path (no prior plan's tests did)."

requirements-completed: [AIP-01, AIP-02, AIP-04]

# Metrics
duration: ~90min (includes recovering a session-limit-interrupted prior attempt and diagnosing a pre-existing test-environment bug)
completed: 2026-09-30
---

# Phase 27 Plan 13: Herculex AI Brief Pre-fill and Persistence Summary

**Closes the loop from "brief accepted" (27-11) to "program actually created carrying that brief's design and provenance" — Herculex AI is now a complete, working build mode end-to-end, and Phase 27 (13/13 plans) is done.**

## Performance

- **Duration:** ~90 min
- **Completed:** 2026-09-30
- **Tasks:** 2/2 completed
- **Files modified:** 5

## Accomplishments

- **Task 1 (pre-fill):** In the success branch of `_generateHerculexBrief()`
  (`actions.part.dart`), an accepted brief's `musclePriorities` are converted
  to a `muscleId -> priority.wireValue` map and assigned to
  `_dreamPhysiquePriorities` (replacing, not merging, any prior Dream
  Physique load), then `_applyDreamPhysiqueTuning()` — unchanged — is
  called so its existing consumer logic fires (D-01, zero new apply logic).
  `_split = brief.splitType` and `_model = brief.periodizationModel` are
  assigned directly afterward, in that order, so the tuning call's internal
  `_applySmartDefaults()` doesn't overwrite the brief's own periodization
  choice (D-03). `phaseIntent` is already visible via 27-11's mode-picker
  subtitle — no new field needed. Every pre-filled value remains fully
  user-editable via the existing Step 1/4 pickers afterward.

- **Task 2 (persistence):** `_create()` now calls
  `HerculexAiBriefService.persistBrief(programId:, brief:, provenance:)`
  immediately after `createProgramFromSplit()` returns its new `programId`,
  gated on `_buildMode == ProgramBuildMode.herculexAi && _acceptedHerculexBrief != null`.
  Wrapped in its own try/catch so a persistence failure never rolls back or
  blocks an otherwise-successful program creation (D-08, T-27-20).

- **Pre-existing bug fix (Rule 1 — discovered via this plan's own test
  coverage, not introduced by it):** `_create()`'s non-manual follow-up path
  calls `JointPainRepository.watchCurrentStatuses().first`. No plan's tests
  before this one ever exercised the full success path for a non-manual
  build mode all the way to `ProgramReviewView` (the D-07 characterization
  tests all expect a guardrail throw; the manual-mode "does NOT throw" tests
  skip this code path entirely since manual mode is exempt from it). The
  first widget test that did reach this path (this plan's "Create block"
  tests) hung for the full 10-minute test timeout — `.first` on a live drift
  `watch()` stream does not resolve inside a widget test's `FakeAsync` zone,
  the exact class of bug 27-12 already found and fixed for
  `HerculexAiBriefService.watchBriefForProgram()`. Fixed the same way: added
  `JointPainRepository.currentStatuses()`, a one-shot `.get()`-based
  equivalent, and switched `_create()`'s one call site to it. Added a unit
  test proving output-shape parity with `watchCurrentStatuses().first`.

- 7 new widget tests in `test/block_builder_view_test.dart` covering all 4
  Task 1 behavior cases (musclePriorities apply + phaseIntent visible,
  split/model set directly, user can still hand-edit and it sticks) and all
  4 Task 2 behavior cases (persists once, never for non-AI modes, no
  persist when no brief was accepted, failure doesn't block creation) —
  24/24 total in the file, up from 17.

## Task Commits

1. **Tasks 1 + 2 (single commit, plus the JointPainRepository fix and its test)** — `b19d0ee` (feat)

## Files Created/Modified

- `lib/features/programs/presentation/views/block_builder_view/actions.part.dart` — pre-fill wiring in `_generateHerculexBrief()`'s success branch; `persistBrief()` call in `_create()`; switched to `JointPainRepository.currentStatuses()`.
- `lib/features/programs/presentation/views/block_builder_view.dart` — comment update on `_herculexBriefProvenance` (now read by `_create()`, no longer unused).
- `lib/features/recovery/data/joint_pain_repository.dart` — new `currentStatuses()` one-shot method.
- `test/block_builder_view_test.dart` — 7 new tests; 2 of the initially-written tests needed their `findsOneWidget` finders widened to `findsWidgets` (Step 6's schedule summary legitimately shows the split name in two places — a block-name suggestion and a caption line — both correctly containing the asserted substring).
- `test/joint_pain_repository_test.dart` — 1 new test proving `currentStatuses()` matches `watchCurrentStatuses().first`'s shape.

## Decisions Made

- phaseIntent surfaced via the existing mode-picker subtitle (27-11), not a new field.
- musclePriorities flows through the unchanged `_applyDreamPhysiqueTuning()` seam — confirmed via `grep` that no new apply-logic method was added.
- `_split`/`_model` assignment ordered after the tuning call so the brief's periodization choice isn't silently overwritten.
- persistBrief() failures are swallowed, not rethrown — matches the plan's explicit tolerance requirement.
- Fixed the pre-existing `.watch().first`-under-FakeAsync bug at its root (a new one-shot repository method) rather than working around it only in the test, since the same hang would affect any other future test — or a production scenario with an unusually slow-to-emit stream — that exercises this exact call site.

## Deviations from Plan

**Rule 1 (bug fix, in scope):** Added `JointPainRepository.currentStatuses()` and switched `_create()`'s pre-existing `watchCurrentStatuses().first` call to it. This file/method was not in the plan's `files_modified` list, and the bug predates this plan entirely — but it directly blocked this plan's own required test coverage (Task 2's acceptance criteria explicitly requires the full `flutter test` suite green as "the final phase-level check"), and no prior plan's tests had ever exercised the code path well enough to surface it. Fixing it at the root (rather than only patching the test) follows the exact precedent 27-12 already set for the identical bug class.

**Session interruption:** The initial attempt at this plan was cut off mid-Task-1/Task-2 by a session rate limit, leaving uncommitted working-tree changes. On resume, the partial work was inspected (not discarded) — Task 2's `persistBrief()` call and most of Task 1's pre-fill wiring were already correct and complete; only the phaseIntent field (found to be unnecessary, see Decisions) and the final test/commit/documentation steps remained.

## Issues Encountered

- Two of the newly-written tests used `find.textContaining(...)` + `findsOneWidget` for text that legitimately appears twice on Step 6 (a suggested block name like "8-week Push / Pull / Legs" and a separate schedule-summary caption). Fixed by widening to `findsWidgets` — the assertion's actual intent (the value is visible, not that it appears exactly once) was preserved.
- The `.watch().first`-under-FakeAsync bug (see Accomplishments) took the bulk of this plan's debugging time: initial full-file test runs showed the 2 finder failures plus 4 "Create block" tests failing with `found 0 widgets with type ProgramReviewView`, some paired with delayed `TimeoutException` messages misattributed by the test runner's interleaved output to whichever test was active when the 10-minute timeout fired. Isolated single-test runs (`--plain-name`) confirmed the finder fixes alone didn't resolve the Create-block failures, which led to tracing `_create()`'s non-manual path to the `watchCurrentStatuses().first` call — confirmed as root cause by re-running a single previously-hanging test immediately after the fix (5s, passing).

## Next Phase Readiness

- **Phase 27 (Herculex AI Program Generation) is complete: 13/13 plans.** AIP-01 through AIP-05 are all satisfied. The full user flow works: select Herculex AI mode -> Generate -> guardrail-validated brief pre-fills Step 1-5 (hand-editable) -> Create block -> persisted brief with provenance -> per-day rationale visible on the review screen (27-12) -> explicit confirmation via the unchanged `_confirm()`.
- Per the roadmap's non-numeric execution order (26 -> 28 -> 27 -> 22 -> 23 -> 29 -> 24 -> 25), Phase 22 (Primary Lift Strength Specialization) is next.
- The `JointPainRepository.currentStatuses()` fix is available for any other imperative call site that might hit the same FakeAsync-stream issue in future test coverage.

## Self-Check: PASSED

- `lib/features/recovery/data/joint_pain_repository.dart` — FOUND on disk, `currentStatuses()` present.
- `lib/features/programs/presentation/views/block_builder_view/actions.part.dart` — FOUND on disk, `persistBrief()` call and `currentStatuses()` call both present.
- `test/block_builder_view_test.dart` — FOUND on disk, 24/24 tests passing.
- `test/joint_pain_repository_test.dart` — FOUND on disk, 7/7 tests passing.
- Commit `b19d0ee` — FOUND in `git log --oneline -5`.

---
*Phase: 27-herculex-ai-program-generation*
*Completed: 2026-09-30*
