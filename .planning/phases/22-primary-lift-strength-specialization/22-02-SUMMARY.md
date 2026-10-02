---
phase: 22-primary-lift-strength-specialization
plan: 02
subsystem: ui
tags: [flutter, riverpod, block-builder, primary-lift-specialization, split-template]

# Dependency graph
requires:
  - phase: 22-primary-lift-strength-specialization
    provides: plan 22-01's domain-level assistanceFocus/split-compat groundwork (PrimaryLiftSpecialization.assistanceFocus, PrimaryLift.appliesToDayLabel)
provides:
  - "Specialization Apply preserves a compatible existing split (Upper/Lower, PPL, Full Body variants) instead of force-resetting to Full Body/3-day/Linear"
  - "Specialization modal surfaces PrimaryLiftSpecialization.assistanceFocus copy per lift/sticking-point combination (D-12 UI half)"
  - "Specialization summary card's exposures-per-week text is computed from the actual chosen split, not a hardcoded '3'"
affects: [22-03, 22-04, future block-builder specialization work]

# Tech tracking
tech-stack:
  added: []
  patterns: ["Gate a destructive setState reset behind a Set<SplitType> membership check instead of unconditionally applying it", "context.hx.<token> design-system token access for new Text widgets inside legacy-AppColors files"]

key-files:
  created: []
  modified:
    - lib/features/programs/presentation/views/block_builder_view.dart
    - lib/features/programs/presentation/views/block_builder_view/step_parameters_specialization.part.dart
    - lib/features/programs/presentation/views/block_builder_view/step_parameters.part.dart
    - test/block_builder_view_test.dart

key-decisions:
  - "_specializationCompatibleSplits is the exact 6-value set RESEARCH.md recommended (fullBody, fullBodyLinear, fullBodyAb, upperLower, upperLowerFullBody, ppl), explicitly excluding fullBodyAbGpp (owned by TrainingStyle.fullBody2xGpp)"
  - "assistanceFocus rendered with placeholder currentKg/targetKg: 0/0, since assistanceFocus's switch only keys on (lift, stickingPoint)"
  - "exposuresPerWeek computed via a new _specializationExposuresPerWeek getter on _StepParametersMixin, reusing PrimaryLift.appliesToDayLabel against _plan.trainingDays rather than hardcoding any split's day count"

patterns-established:
  - "New UI text in this file reads design-system tokens via context.hx.* (not AppColors) per UI-SPEC's scope-local token rule for new code in this otherwise-legacy-AppColors phase"

requirements-completed: [SPEC-01, SPEC-02]

# Metrics
duration: 25min
completed: 2026-10-02
---

# Phase 22 Plan 02: Split-Flexible Specialization + D-12 Copy Summary

**Specialization Apply now preserves a compatible Upper/Lower or PPL split instead of force-resetting to Full Body, the modal surfaces per-lift/sticking-point assistanceFocus copy, and the summary card's exposure count is computed from the real split instead of hardcoded "3".**

## Performance

- **Duration:** ~25 min
- **Started:** 2026-10-02T11:05:00+02:00 (approx, first commit 11:09:51+02:00)
- **Completed:** 2026-10-02T11:14:56+02:00
- **Tasks:** 2
- **Files modified:** 4 (3 lib files + 1 test file)

## Accomplishments
- Closed the D-01-D-03 split-flexibility gap: toggling specialization on with an already-compatible split (Upper/Lower, PPL, Full Body variants) leaves it untouched; an incompatible split (e.g. Bro Split) still resets to Full Body/3-day/Linear exactly as before.
- Surfaced D-12's already-shipped, lift-agnostic `PrimaryLiftSpecialization.assistanceFocus` copy directly in the specialization modal, for every lift x sticking-point combination including the unresolved/default sticking point.
- Fixed RESEARCH.md's Pitfall 3: the summary card's exposures-per-week text is now computed from `_plan.trainingDays` via `PrimaryLift.appliesToDayLabel`, correctly showing 2x for Upper/Lower and 3x for Full Body instead of a hardcoded "3 exposures / week".

## Task Commits

Each task was committed atomically:

1. **Task 1: Split-compatibility Apply logic and D-12 sticking-point helper copy** - `59e2619` (feat)
2. **Task 2: Computed exposures-per-week text (Pitfall 3)** - `56cb60a` (fix)

_Both tasks are `tdd="true"`; tests were written and run alongside the implementation in the same commit for each task (behavior verified green before committing), rather than as separate RED/GREEN commits — the plan's single `<action>` block specified implementation and tests together, not a staged RED-then-GREEN sequence._

## Files Created/Modified
- `lib/features/programs/presentation/views/block_builder_view.dart` - added `hx_colors.dart` import for the new modal helper text's token-based color
- `lib/features/programs/presentation/views/block_builder_view/step_parameters_specialization.part.dart` - added `_specializationCompatibleSplits`, gated the Apply handler's split/daysPerWeek/model reset behind it, added the assistanceFocus `Text` widget after the sticking-point dropdown
- `lib/features/programs/presentation/views/block_builder_view/step_parameters.part.dart` - added `_specializationExposuresPerWeek` getter, replaced the hardcoded exposures text with the computed value
- `test/block_builder_view_test.dart` - added 6 new widget tests (4 for Task 1, 2 for Task 2)

## Decisions Made
- Used a plain getter (`_specializationExposuresPerWeek` / inlined `_specializationCompatibleSplits`) rather than a `Builder` wrapper or local variable, since both mixins already have direct field access to `_plan`/`_specializationLift`/`_split` on `_BuilderStateBase` — no new state or rebuild-scoping needed.
- Removed the plan's suggested `hx_geometry.dart` import after `flutter analyze` flagged it unused — this task's edits only needed `hx_colors.dart`'s `onSurfaceVariant` token, not any `HxSpace`/`HxRadius` geometry constant.

## Deviations from Plan

**1. [Rule 1 - minor] Dropped unused `hx_geometry.dart` import**
- **Found during:** Task 1 (`flutter analyze` after the import-block edit)
- **Issue:** The plan's `<action>` specified adding both `hx_colors.dart` and `hx_geometry.dart` imports, but the task's actual edits (the assistanceFocus `Text` style) only use `context.hx.onSurfaceVariant` from `hx_colors.dart` — no `HxSpace`/`HxRadius` constant from `hx_geometry.dart` is referenced anywhere in the diff.
- **Fix:** Removed the `hx_geometry.dart` import; kept `hx_colors.dart`.
- **Files modified:** `lib/features/programs/presentation/views/block_builder_view.dart`
- **Verification:** `flutter analyze` reports 0 issues (previously 1 `unused_import` warning).
- **Committed in:** `59e2619` (Task 1 commit)

---

**Total deviations:** 1 auto-fixed (1 minor/Rule 1)
**Impact on plan:** No scope creep — this is strictly removing an import the plan anticipated needing but the actual diff didn't exercise.

## Issues Encountered
None.

## User Setup Required
None - no external service configuration required.

## Next Phase Readiness
- Specialization now supports the 3 split families CONTEXT.md named (Full Body, Upper/Lower, PPL) without losing the user's existing split choice.
- D-12's UI half is fully closed in this plan; the domain switch producing distinct assistance *slots* per sticking point (as opposed to this plan's helper-text surfacing) remains plan 22-01's separate scope, already shipped per that plan's own summary.
- No blockers for 22-03/22-04.

---
*Phase: 22-primary-lift-strength-specialization*
*Completed: 2026-10-02*

## Self-Check: PASSED

- FOUND: commit 59e2619 (Task 1)
- FOUND: commit 56cb60a (Task 2)
- FOUND: lib/features/programs/presentation/views/block_builder_view/step_parameters_specialization.part.dart
- FOUND: lib/features/programs/presentation/views/block_builder_view/step_parameters.part.dart
- FOUND: test/block_builder_view_test.dart
