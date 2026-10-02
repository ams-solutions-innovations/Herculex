---
phase: 22-primary-lift-strength-specialization
plan: 04
subsystem: ui
tags: [flutter, block-builder, primary-lift-specialization, guardrails, volume-bands]

# Dependency graph
requires:
  - phase: 22-primary-lift-strength-specialization
    provides: plan 22-01's ProgramGuardrails.validateVolumeFloor/validateKgIncrease and plan 22-03's weeks-picker warning precedent
affects: []

# Tech tracking
tech-stack:
  added: []
  patterns:
    - "Create-time non-blocking guardrail confirmation: compute issues after the existing blocking configIssues check, show one AlertDialog naming every issue via AiBriefRejectionBanner, 'Create anyway'/'Review' resolve a Future<bool>, a Review outcome is a clean early return (never a thrown StateError)"

key-files:
  created:
    - lib/features/programs/presentation/widgets/specialization_volume_floor_card.dart
    - test/specialization_volume_floor_card_test.dart
  modified:
    - lib/features/programs/presentation/views/block_builder_view.dart
    - lib/features/programs/presentation/views/block_builder_view/step_schedule_summary.part.dart
    - lib/features/programs/presentation/views/block_builder_view/actions.part.dart
    - test/program_muscle_volume_test.dart
    - test/block_builder_view_test.dart

key-decisions:
  - "SpecializationVolumeFloorCard uses hx.surfaceVariant for the unfilled bar track instead of the plan's suggested hx.surfaceContainerHigh token, which does not exist on HxColors — surfaceVariant is the closest existing 'recessed fill' token per its own doc comment"

patterns-established: []

requirements-completed: [SPEC-02]

# Metrics
duration: ~35min
completed: 2026-10-02
---

# Phase 22 Plan 04: Volume-Floor Live Preview + Create-Time Confirmation Summary

**The Schedule step now highlights any below-floor muscle group as "Light" whenever specialization is active and a template is linked, and Create block surfaces a single non-blocking confirmation naming every volume-floor/kg-increase issue, with "Create anyway" proceeding and "Review" cancelling cleanly.**

## Performance

- **Duration:** ~35 min
- **Tasks:** 2 completed
- **Files modified:** 7 (3 lib created/modified beyond the widget, 2 test files, 1 new widget, 1 new test file)

## Accomplishments

- `SpecializationVolumeFloorCard` (new, 113 lines): a regular-weight muscle-row list that computes `VolumeBands.forGroup(muscle).verdict(sets)` per row, tinting any `VolumeVerdict.low` group's name, bar fill, and sets text `hx.warning`, with a "Light — Below the volume that usually drives progress" line beneath it. Renders `SizedBox.shrink()` for an empty breakdown, mirroring `ProgramMuscleVolumeCard`'s own precedent.
- `step_schedule_summary.part.dart`'s `_summaryCard` now renders `SpecializationVolumeFloorCard` instead of `ProgramMuscleVolumeCard` for the same `FutureBuilder<ProgramVolumeBreakdown>` snapshot whenever `_useLiftSpecialization` is true; the non-specialization path is byte-for-byte unchanged.
- A new `computeFromTemplates` -> `VolumeBands.verdicts` integration test in `program_muscle_volume_test.dart` proves the full D-04 pipeline end-to-end against a real seeded database (one low-volume Chest template), closing the Wave 0 gap VALIDATION.md flagged (no prior test called `computeFromTemplates` at all).
- `actions.part.dart`'s `_create()` now computes `ProgramGuardrails.validateVolumeFloor` + `validateKgIncrease` immediately after the existing blocking `configIssues` check, whenever specialization is active. If either returns issues, a new `_confirmSpecializationWarnings` method shows one `AlertDialog` with one `AiBriefRejectionBanner` per issue (verbatim `issue.message`); "Create anyway" proceeds to `ProgramReviewView`, "Review" resets `_saving` and returns early — never a thrown error, never `createdProgramId` set.
- 4 new widget tests cover the kg-ceiling-exceeded dialog's both button outcomes, the within-ceiling no-dialog case, and the specialization-inactive regression case. All 6 pre-existing D-07 characterization tests continue to pass unchanged, confirming zero new dialogs appear outside specialization's own path.

## Task Commits

1. **Task 1: SpecializationVolumeFloorCard widget and Schedule-step live preview (D-04, D-06 live half, D-07)** - `93b947e` (feat)
2. **Task 2: Create-time, non-blocking volume-floor + kg-increase confirmation (D-06 Create-time half, D-07, D-11 Create-time half)** - `d473ac1` (feat)

## Files Created/Modified

- `lib/features/programs/presentation/widgets/specialization_volume_floor_card.dart` - new widget, 113 lines
- `lib/features/programs/presentation/views/block_builder_view.dart` - added the new widget's import
- `lib/features/programs/presentation/views/block_builder_view/step_schedule_summary.part.dart` - `_summaryCard`'s `FutureBuilder` builder now branches on `_useLiftSpecialization`
- `lib/features/programs/presentation/views/block_builder_view/actions.part.dart` - added `_confirmSpecializationWarnings`; `_create()` now runs the combined volume-floor/kg-increase check and confirmation between the existing blocking-issue throw and `repo.createProgramFromSplit`
- `test/specialization_volume_floor_card_test.dart` - new, 3 widget tests
- `test/program_muscle_volume_test.dart` - 1 new integration test appended to the existing `ProgramVolumeCalculator` group
- `test/block_builder_view_test.dart` - 4 new widget tests in a new `D-06/D-11 Create-time specialization warnings (22-04)` group, inserted after the pre-existing `D-07 characterization` group per the plan's sequencing note (22-03's own test-group additions already landed in the file; this plan's group is appended after, not interleaved)

## Decisions Made

- **`hx.surfaceVariant` used for the unfilled volume-bar track, not `hx.surfaceContainerHigh`.** The plan's `<action>` text suggested a `hx.surfaceContainerHigh`-style token for the track background, but `HxColors` (read in full before writing the widget) has no such field — its closest "recessed fill: inputs, progress tracks, inactive segments" token is `surfaceVariant`, which is what every other progress-track usage in this codebase already reads. No behavior or visual-intent change, just matching the actual token surface.

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 1 - minor] Corrected the volume-bar track color token**
- **Found during:** Task 1, writing `SpecializationVolumeFloorCard`
- **Issue:** The plan's `<action>` implied a `surfaceContainerHigh`-shaped token for the unfilled bar track; `HxColors` has no such field.
- **Fix:** Used `hx.surfaceVariant` instead — the existing "recessed fill" token, matching every other progress-track usage in the codebase.
- **Files modified:** `lib/features/programs/presentation/widgets/specialization_volume_floor_card.dart`
- **Verification:** `flutter analyze` reports 0 issues.
- **Committed in:** `93b947e` (Task 1 commit)

---

**Total deviations:** 1 auto-fixed (1 minor/Rule 1)
**Impact on plan:** No scope creep — a token-name correction only, discovered by reading the actual `HxColors` class before writing new code that references it.

## Issues Encountered

- Worktree was initially checked out at a stale, unrelated base commit (`d0c152a`, a pre-Phase-11-era history) rather than the expected `f02fc2a`. Corrected via the mandatory `<worktree_branch_check>` base-correction reset (clean working tree, no uncommitted work lost) before any plan work began.

## User Setup Required

None - no external service configuration required.

## Next Phase Readiness

- Both halves of D-04–D-07's maintenance-volume-floor gap (live preview + Create-time confirmation) and D-11's Create-time kg-increase half are closed. Combined with plan 22-03's weeks-picker kg-increase warning, D-11 is now fully closed across both of its required surfaces.
- SPEC-02 (non-target muscle groups checked against a maintenance floor) is satisfied end-to-end: computed, surfaced live, and confirmed at Create time, always advisory, never blocking.
- No blockers. Phase 22's remaining scope (if any) is tracked in `.planning/phases/22-primary-lift-strength-specialization/` outside this plan.

---
*Phase: 22-primary-lift-strength-specialization*
*Completed: 2026-10-02*

## Self-Check: PASSED

- FOUND: lib/features/programs/presentation/widgets/specialization_volume_floor_card.dart
- FOUND: test/specialization_volume_floor_card_test.dart
- FOUND: lib/features/programs/presentation/views/block_builder_view/actions.part.dart (modified)
- FOUND: test/block_builder_view_test.dart (modified)
- FOUND: test/program_muscle_volume_test.dart (modified)
- FOUND commit: 93b947e (Task 1)
- FOUND commit: d473ac1 (Task 2)
