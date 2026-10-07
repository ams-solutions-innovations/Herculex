---
phase: 22-primary-lift-strength-specialization
plan: 03
subsystem: ui
tags: [flutter, block-builder, primary-lift-specialization, guardrails]

# Dependency graph
requires:
  - phase: 22-primary-lift-strength-specialization
    provides: plan 22-01's ProgramGuardrails.validateKgIncrease/kgIncreaseCeilings and plan 22-02's split-flexible specialization UI
provides:
  - "Weeks picker auto-adjusts a too-short specialization pick to PrimaryLiftSpecialization.recommendedWeeks() with an inline SnackBar warning (D-08-D-10)"
  - "Weeks picker surfaces a 'That's a big jump' banner whenever the active specialization's kg increase exceeds ProgramGuardrails.kgIncreaseCeilings[_experience] (D-11)"
affects: [22-04]

# Tech tracking
tech-stack:
  added: []
  patterns:
    - "Picker-sheet guardrail banner: compute issues before HxSheet.show's builder runs, render AiBriefRejectionBanner as the sheet body's first child when non-empty, SizedBox.shrink() otherwise"

key-files:
  created: []
  modified:
    - lib/features/programs/presentation/views/block_builder_view.dart
    - lib/features/programs/presentation/views/block_builder_view/dialogs.part.dart
    - lib/features/programs/presentation/views/block_builder_view/step_parameters_specialization.part.dart
    - test/block_builder_view_test.dart

key-decisions:
  - "Added `double get _targetSquatKg;` to _BuilderStateBase's abstract stub surface (Rule 3) - the getter already existed in step_parameters_specialization.part.dart but was never exposed across the mixin boundary, so dialogs.part.dart's new onSelected callback could not reference it without this stub"
  - "Re-added the hx_geometry.dart import to block_builder_view.dart (Rule 3) - 22-02's own summary documents removing this import as unused at the time; this plan's new HxSpace.x3 banner padding needs it again"
  - "Widget tests scope ambiguous '<n> weeks' text finds to either the picker-length tile's key or the open HxSheet's type, since once a specialization pick is applied the background tile and the sheet's own option list can both render the same numeral simultaneously"

patterns-established: []

requirements-completed: [SPEC-03]

# Metrics
duration: ~45min
completed: 2026-10-02
---

# Phase 22 Plan 03: Weeks-Picker Timeline-Realism Warnings Summary

**The Weeks picker now auto-corrects a too-short specialization pick to the recommended weeks with an inline "Not enough time to progress safely" warning, and separately flags an unrealistic kg increase with a "That's a big jump" banner, both non-blocking and both absent when no specialization is active.**

## Performance

- **Duration:** ~45 min
- **Tasks:** 2 completed
- **Files modified:** 4 (3 lib, 1 test)

## Accomplishments

- `_showLengthPicker`'s `onSelected` callback now auto-adjusts `_weeks` to `_liftRecommendedWeeks` and shows a 6-second floating `SnackBar` (using the existing `AiBriefRejectionBanner` as content) whenever specialization is active and the tapped value falls short of the recommendation (D-08-D-10). No specialization, or a sufficient pick, behaves exactly as before (regression-safe).
- The same sheet now computes `ProgramGuardrails.validateKgIncrease` up front and renders a "That's a big jump" banner (verbatim `issue.message`) above the weeks list whenever the active specialization's current→target kg gap exceeds its experience-tier ceiling, independent of which weeks value the user taps (D-11).
- 6 new widget tests cover both checks' shortfall/sufficient and over-ceiling/under-ceiling/inactive cases.

## Task Commits

1. **Task 1: Weeks-picker shortfall warning and auto-adjust (D-08-D-10)** - `9254756` (feat)
2. **Task 2: Kg-increase ceiling warning inside the Weeks-picker sheet (D-11)** - `d1712e5` (feat)

## Files Created/Modified

- `lib/features/programs/presentation/views/block_builder_view.dart` - added `double get _targetSquatKg;` abstract stub; re-added `hx_geometry.dart` import
- `lib/features/programs/presentation/views/block_builder_view/dialogs.part.dart` - `_showLengthPicker`'s `onSelected` now branches on `_useLiftSpecialization && selected < _liftRecommendedWeeks` (shortfall SnackBar + auto-adjust); sheet body now has a conditional "That's a big jump" banner computed from `ProgramGuardrails.validateKgIncrease`
- `lib/features/programs/presentation/views/block_builder_view/step_parameters_specialization.part.dart` - marked the pre-existing `_targetSquatKg` getter `@override` to satisfy the new abstract stub
- `test/block_builder_view_test.dart` - 6 new widget tests (3 per task)

## Decisions Made

- **`_targetSquatKg` abstract stub added to `_BuilderStateBase` (Rule 3 - blocking compile fix).** The plan's `<action>` for Task 1 directly references `_targetSquatKg` from `dialogs.part.dart`, but that getter was only ever declared inside `step_parameters_specialization.part.dart`'s mixin and never exposed via an abstract stub on `_BuilderStateBase`. Since `_DialogsMixin` is declared `on _BuilderStateBase` only, Dart's mixin typing does not let it see a sibling mixin's members without that stub — this would have been a compile error. Added `double get _targetSquatKg;` alongside the pre-existing `_currentSquatKg`/`_liftRecommendedWeeks`/`_primaryLiftSpecialization` stubs and marked the concrete getter `@override`, mirroring the exact pattern already used for `_currentSquatKg`.
- **`hx_geometry.dart` import re-added to `block_builder_view.dart` (Rule 3 - blocking compile fix).** Plan 22-03's interfaces section asserted both `hx_colors.dart` and `hx_geometry.dart` were "already present" per plan 22-02's Task 1 — but 22-02's own SUMMARY.md documents a deviation removing the `hx_geometry.dart` import as unused immediately after adding it, since that plan's actual diff never used `HxSpace`/`HxRadius`. This plan's Task 2 banner padding (`EdgeInsets.only(bottom: HxSpace.x3)`) does need it, so the import was re-added.
- **Test finder scoping for ambiguous "N weeks" text.** Several of this plan's new tests apply a specialization and then open the Weeks picker; because `_weeks` is already set to the recommendation before the sheet opens, the background "Block length" tile and the sheet's own list of weeks options can simultaneously render an identical numeral (e.g. "24 weeks" appearing twice). Assertions scope the finder to either `find.byKey(const ValueKey('picker-length'))` (for the closed-sheet, post-tap state) or `find.byType(HxSheet)` (for taps while the sheet is still open), rather than a bare `find.text(...)`.

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 3 - Blocking] Added `double get _targetSquatKg;` abstract stub to `_BuilderStateBase`**
- **Found during:** Task 1, writing the `onSelected` callback edit specified by the plan's `<action>`
- **Issue:** The plan's action text references `_targetSquatKg` from `dialogs.part.dart`, but that getter existed only in `step_parameters_specialization.part.dart`'s mixin with no corresponding abstract stub on `_BuilderStateBase` — `_DialogsMixin` (declared `on _BuilderStateBase`) could not statically resolve the member, which would fail `flutter analyze`/compilation.
- **Fix:** Added `double get _targetSquatKg;` to the "Implemented in step_parameters_specialization.part.dart" stub block in `_BuilderStateBase`, and marked the concrete getter `@override`.
- **Files modified:** `lib/features/programs/presentation/views/block_builder_view.dart`, `lib/features/programs/presentation/views/block_builder_view/step_parameters_specialization.part.dart`
- **Verification:** `flutter analyze` reports 0 issues; `flutter test test/block_builder_view_test.dart` passes.
- **Committed in:** `9254756` (Task 1 commit)

**2. [Rule 3 - Blocking] Re-added `hx_geometry.dart` import to `block_builder_view.dart`**
- **Found during:** Task 2, writing the kg-ceiling banner's `Padding(padding: const EdgeInsets.only(bottom: HxSpace.x3), ...)`
- **Issue:** The plan's interfaces section claimed this import was already present from plan 22-02's Task 1, but 22-02's own SUMMARY.md documents removing it (as unused at the time) in the same plan. Without it, `HxSpace` is undefined in this file.
- **Fix:** Re-added `import 'package:herculex/design_system/tokens/hx_geometry.dart';` to `block_builder_view.dart`'s import block.
- **Files modified:** `lib/features/programs/presentation/views/block_builder_view.dart`
- **Verification:** `flutter analyze` reports 0 issues.
- **Committed in:** `d1712e5` (Task 2 commit)

---

**Total deviations:** 2 auto-fixed (2 blocking/Rule 3)
**Impact on plan:** Both deviations are compile-correctness fixes required by the plan's own specified action text (which referenced a not-yet-exposed getter and assumed an import that a prior plan's own summary documents removing). No scope creep — no behavior beyond what the plan's `<action>`/`<behavior>` sections specify.

## Issues Encountered

- The first attempt at the shortfall/sufficient-pick widget tests used a bare `find.text('24 weeks')` to assert the post-tap state. Once a specialization pick auto-adjusts `_weeks` to the recommendation (24, in the test fixtures used), the background "Block length" summary tile and the still-closing bottom sheet's own list item could both render "24 weeks" at the same pump, making the finder ambiguous (`findsOneWidget` failures and a `tap()` ambiguity failure). Resolved by scoping finders to `find.byKey(const ValueKey('picker-length'))` for post-close assertions and `find.byType(HxSheet)` for the tap itself.

## User Setup Required

None - no external service configuration required.

## Next Phase Readiness

- Both halves of SPEC-03's timeline-realism gap are now closed: the weeks-shortfall auto-adjust/warning (D-08-D-10) and the kg-increase ceiling warning (D-11), both non-blocking, both absent when specialization is inactive or picks are realistic.
- `dialogs.part.dart` is 391 lines, well under the 600-line cap.
- No blockers for 22-04.

---
*Phase: 22-primary-lift-strength-specialization*
*Completed: 2026-10-02*

## Self-Check: PASSED

- FOUND: lib/features/programs/presentation/views/block_builder_view/dialogs.part.dart
- FOUND: test/block_builder_view_test.dart
- FOUND: .planning/phases/22-primary-lift-strength-specialization/22-03-SUMMARY.md
- FOUND commit: 9254756 (Task 1)
- FOUND commit: d1712e5 (Task 2)
