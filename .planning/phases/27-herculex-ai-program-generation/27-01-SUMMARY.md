---
phase: 27-herculex-ai-program-generation
plan: 01
subsystem: ui
tags: [flutter, dart-mixins, part-of, refactor, block-builder]

# Dependency graph
requires: []
provides:
  - block_builder_view.dart reduced from 3398 to 402 lines (thin shell: widget class,
    abstract _BuilderStateBase, concrete _BlockBuilderViewState)
  - 10 part files under lib/features/programs/presentation/views/block_builder_view/,
    each under 600 lines, holding the previously-inline builder logic
  - Stable, named file targets for every method Phase 27's later plans must edit
affects: [27-08, 27-11, 27-13]

# Tech tracking
tech-stack:
  added: []
  patterns:
    - "abstract-base-plus-on-constrained-mixins: the technique for splitting one
      Dart State class body across multiple part files when part/part-of alone
      only supports top-level declarations, not partial class bodies"

key-files:
  created:
    - lib/features/programs/presentation/views/block_builder_view/standalone_widgets.part.dart
    - lib/features/programs/presentation/views/block_builder_view/shared_helpers.part.dart
    - lib/features/programs/presentation/views/block_builder_view/dialogs.part.dart
    - lib/features/programs/presentation/views/block_builder_view/step_mode_and_split.part.dart
    - lib/features/programs/presentation/views/block_builder_view/step_parameters.part.dart
    - lib/features/programs/presentation/views/block_builder_view/step_parameters_specialization.part.dart
    - lib/features/programs/presentation/views/block_builder_view/step_pools.part.dart
    - lib/features/programs/presentation/views/block_builder_view/step_methods.part.dart
    - lib/features/programs/presentation/views/block_builder_view/step_schedule_summary.part.dart
    - lib/features/programs/presentation/views/block_builder_view/actions.part.dart
  modified:
    - lib/features/programs/presentation/views/block_builder_view.dart

key-decisions:
  - "Split step_parameters into two files (step_parameters.part.dart +
    step_parameters_specialization.part.dart) because the plan's own grouping,
    once the primary-lift-specialization modal and its helper getters were
    included, would have exceeded 600 lines - resolved per the plan's own
    step-5 instruction to split further rather than breach the cap."
  - "Three base-class members (_stepCount, _manualMuscleLabels, _today()) are
    `static`, and Dart does not inherit static members into subclasses or
    `on`-bound mixins - unqualified access from a mixin fails to resolve.
    Fixed by qualifying the 4 call sites as _BuilderStateBase.<member> rather
    than de-staticizing (which would have required calling an instance method
    from a field initializer, a separate risk)."
  - "Cross-mixin abstract stubs were discovered mechanically via iterative
    flutter analyze runs (3 iterations to zero errors), exactly as the plan's
    action step 3 prescribes, rather than pre-computed by hand - more reliable
    given ~30 distinct cross-mixin call sites."

patterns-established:
  - "abstract-base-plus-mixins for splitting an oversized StatefulWidget's
    State class: abstract class _XStateBase extends State<X> holds shared
    fields; each mixin is `on _XStateBase`; the concrete _XState extends the
    base and mixes in every group; any cross-mixin (or mixin-to-final-class)
    call needs a signature-only abstract stub declared on the base, added by
    running flutter analyze until 'isn't defined for the type' errors reach
    zero."

requirements-completed: [AIP-01]

# Metrics
duration: 35min
completed: 2026-09-29
---

# Phase 27 Plan 01: Split block_builder_view.dart into part/part-of mixins Summary

**Split the 3398-line block_builder_view.dart into a 402-line thin shell plus 10 part
files (abstract-base-plus-mixins technique), each under 600 lines, with zero behavior
change verified by the existing 4-test widget suite.**

## Performance

- **Duration:** ~35 min
- **Completed:** 2026-09-29T19:47:16Z
- **Tasks:** 2 (both `type="auto"`)
- **Files modified/created:** 11 (1 modified, 10 created)

## Accomplishments
- `block_builder_view.dart` reduced from 3398 to 402 lines — well under CLAUDE.md's
  600-line cap.
- All 10 part files (9 planned + 1 deviation split) are under 600 lines; the largest is
  `step_mode_and_split.part.dart` at 493 lines.
- Zero behavior change: all 4 tests in `test/block_builder_view_test.dart` pass
  unchanged, `flutter analyze` reports 0 issues across every touched file.
- Downstream plans 27-08, 27-11, and 27-13 now have exact, stable file targets instead
  of a monolith (see File-to-Method Map below).

## Task Commits

1. **Task 1: Extract standalone widget classes into their own part file** - `a86fec1`
   (refactor)
2. **Task 2: Split the big state class into an abstract field base plus 8 (+1)
   concern-grouped mixins** - `21abb6d` (refactor)

## Files Created/Modified

- `lib/features/programs/presentation/views/block_builder_view.dart` — now a thin shell:
  `BlockBuilderView` widget, abstract `_BuilderStateBase` (shared fields + `_today()` +
  `_plan` getter + the cross-mixin abstract-stub surface), and the concrete
  `_BlockBuilderViewState` (glue: `initState`, `dispose`, `_effectiveName`,
  `_recommendExperience`, `_applySmartDefaults`, `_applyDreamPhysiqueTuning`, `build`).
- `.../block_builder_view/standalone_widgets.part.dart` — `_RecommendedPill`,
  `_ManualMusclePlanSheet`/`_ManualMusclePlanSheetState` (+ `_focusRow`). Plain top-level
  classes, no mixin needed.
- `.../block_builder_view/shared_helpers.part.dart` (`_SharedHelpersMixin`) — `_title`,
  `_sectionLabel`, `_choiceChip`, `_pickerTile`, `_settingToggleTile`, `_sheetOptionCard`,
  `_radioCard`, `_footer`.
- `.../block_builder_view/dialogs.part.dart` (`_DialogsMixin`) —
  `_dreamPhysiqueAutoFillBanner`, `_showGoalPicker`, `_showTrainingStylePicker`,
  `_showExperiencePicker`, `_showLengthPicker`, `_showSpecializationInfoDialog`,
  `_showInfoDialog`.
- `.../block_builder_view/step_mode_and_split.part.dart` (`_StepModeAndSplitMixin`) —
  **`_stepBuildModeAndPriorities()` (the exhaustive `switch (mode)` plan 27-11 edits to
  add the 4th mode tile/case)**, `_stepSplit`, `_planPreview`, `_previewRow`,
  `_clearCustomWeeklyPlacement`, `_editWeeklyDay`, `_recoveryWarnings`, `_recoveryWarning`.
- `.../block_builder_view/step_parameters.part.dart` (`_StepParametersMixin`) —
  `_stepParameters`, `_modelDescriptions`, `_recommendedPeriodizationModel`.
- `.../block_builder_view/step_parameters_specialization.part.dart`
  (`_StepParametersSpecializationMixin`, **new file, not in the original plan** — see
  Deviations) — `_showSpecializationModal`, `_currentSquatKg`, `_targetSquatKg`,
  `_liftRecommendedWeeks`, `_primaryLiftSpecialization`, `_defaultTargetFor`.
- `.../block_builder_view/step_pools.part.dart` (`_StepPoolsMixin`) —
  `_stepExercisePools`, `_builderInputCard`, `_manualPlanSummary`, `_showManualMusclePlan`,
  `_slotCard`.
- `.../block_builder_view/step_methods.part.dart` (`_StepMethodsMixin`) —
  `_stepContentAndMethods`, `_programRhythmCard`, `_isConcurrentPreset`,
  `_defaultDayRole` (added — not in the plan's list but only used inside
  `_programRhythmCard`, same group), `_rotationPreview`, `_muscleFocusPreview`,
  `_concurrentPreset`.
- `.../block_builder_view/step_schedule_summary.part.dart`
  (`_StepScheduleSummaryMixin`) — `_stepSchedule`, `_summaryCard`.
- `.../block_builder_view/actions.part.dart` (`_BuilderActionsMixin`) — `_goBackStep`,
  `_loadDreamPhysiquePriorities`, **`_create()` (the exact method plans 27-08 and 27-13
  edit)**, `_manualPriorities`, `_manualWeights`, `_trainingStyleDescription`.

## File-to-Method Map (for plans 27-08, 27-11, 27-13)

| File | Contains |
|---|---|
| `actions.part.dart` | `_create()` — plan 27-08 retrofits the guardrail check here; plan 27-13 adds AI-brief pre-fill/persistence here |
| `step_mode_and_split.part.dart` | `_stepBuildModeAndPriorities()` — plan 27-11 adds the 4th ("Herculex AI") mode tile and its `switch (mode)` case here |
| `step_parameters.part.dart` / `step_parameters_specialization.part.dart` | Training-parameters step UI, periodization model picker, primary-lift-specialization modal |
| `step_pools.part.dart` | Exercise pools step, manual muscle plan sheet trigger |
| `step_methods.part.dart` | Content & methods step, per-day training method/role selection |
| `step_schedule_summary.part.dart` | Schedule and final summary steps |
| `dialogs.part.dart` | All `show*Picker`/`show*Dialog` sheets |
| `shared_helpers.part.dart` | Reusable widget builders (`_title`, `_radioCard`, `_pickerTile`, etc.) |

## Decisions Made

- Split `step_parameters` into two files (see Deviations) rather than exceed 600 lines.
- Qualified 3 static base-class members (`_stepCount`, `_manualMuscleLabels`, `_today()`)
  at their 4 cross-mixin call sites as `_BuilderStateBase.<member>` instead of
  de-staticizing them, avoiding the risk of calling an instance method from a field
  initializer (`_startDate = _today();`).
- Discovered the full cross-mixin abstract-stub surface (~30 stubs) mechanically via 3
  iterations of `flutter analyze`, exactly per the plan's prescribed methodology, rather
  than hand-computing every call graph edge up front.
- Added `@override` to every abstract-stub implementation across all part files (58
  `annotate_overrides` info-level lints were present after the mechanical split; fixed
  for code-quality even though they don't fail `flutter analyze`'s exit code).

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 3 - Blocking] Split step_parameters into two files, not one**
- **Found during:** Task 2
- **Issue:** The plan's `step_parameters.part.dart` grouping said "`_stepParameters`
  only," but `_stepParameters` calls `_showSpecializationModal` and 5 small helper
  getters (`_currentSquatKg`, `_targetSquatKg`, `_liftRecommendedWeeks`,
  `_primaryLiftSpecialization`, `_defaultTargetFor`) that the plan didn't assign to any
  group. Placing all of them in `step_parameters.part.dart` (their only real caller)
  would have produced a ~626-line file, over the 600-line cap.
- **Fix:** Created a 10th file, `step_parameters_specialization.part.dart`
  (`_StepParametersSpecializationMixin`), holding `_showSpecializationModal` and the 5
  orphaned helpers. This follows the plan's own step-5 instruction verbatim: "If any
  single group still exceeds 600 lines, split that group further along an internal
  method boundary... rather than exceeding the cap."
- **Files modified:** `block_builder_view.dart` (added the 10th `part` directive and 4
  more abstract stubs), new file
  `block_builder_view/step_parameters_specialization.part.dart`.
- **Verification:** `wc -l` confirms both files are under 600 lines (402 and 258
  respectively); `flutter analyze` and `flutter test test/block_builder_view_test.dart`
  both pass.
- **Committed in:** `21abb6d` (Task 2 commit).

**2. [Rule 2 - Missing critical functionality] `_defaultDayRole` was unassigned by the
plan**
- **Found during:** Task 2
- **Issue:** The plan's `step_methods.part.dart` group list omitted `_defaultDayRole`,
  a method called only from `_programRhythmCard` (which the plan does assign to
  `step_methods.part.dart`). Without it, the file would not compile.
- **Fix:** Added `_defaultDayRole` to `step_methods.part.dart` alongside its sole
  caller — no cross-mixin stub needed since both live in the same mixin.
- **Files modified:** `block_builder_view/step_methods.part.dart`.
- **Verification:** `flutter analyze` clean.
- **Committed in:** `21abb6d`.

**3. [Rule 3 - Blocking] Static base-class members not inherited by `on`-bound mixins**
- **Found during:** Task 2 (first `flutter analyze` iteration)
- **Issue:** `_stepCount`, `_manualMuscleLabels`, and `_today()` are declared `static`
  in `_BuilderStateBase`. Dart does not inherit static members into subclasses (or
  mixins constrained via `on`), so the 4 unqualified references from
  `shared_helpers.part.dart`, `step_methods.part.dart`, `step_pools.part.dart`, and
  `step_schedule_summary.part.dart` failed to resolve.
- **Fix:** Qualified each call site as `_BuilderStateBase._stepCount`,
  `_BuilderStateBase._manualMuscleLabels`, `_BuilderStateBase._today()`. Values and
  behavior are unchanged.
- **Files modified:** `shared_helpers.part.dart`, `step_methods.part.dart`,
  `step_pools.part.dart`, `step_schedule_summary.part.dart`.
- **Verification:** `flutter analyze` clean; widget test passes.
- **Committed in:** `21abb6d`.

---

**Total deviations:** 3 auto-fixed (2 blocking, 1 missing-critical). All were required
to make the plan's own prescribed technique compile; none change runtime behavior.
**Impact on plan:** No scope creep — every deviation is a mechanical consequence of the
plan's own grouping being incomplete or under-specified for a handful of methods, and
each was resolved the way the plan itself instructs (split further / iterate
`flutter analyze`).

## Issues Encountered

None beyond the deviations above.

## User Setup Required

None - no external service configuration required.

## Next Phase Readiness

- `block_builder_view.dart` and all part files are under the 600-line cap, with headroom
  in `actions.part.dart` (204 lines) and `step_mode_and_split.part.dart` (493 lines) for
  plans 27-08, 27-11, and 27-13's edits.
- `_create()` (actions.part.dart) and `_stepBuildModeAndPriorities()`
  (step_mode_and_split.part.dart) are confirmed as the exact, stable edit targets the
  plan's must-haves specified.
- No blockers for Phase 27's remaining plans.

---
*Phase: 27-herculex-ai-program-generation*
*Completed: 2026-09-29*

## Self-Check: PASSED

All 11 created/modified source files and the SUMMARY.md itself verified present on
disk; all 3 task/docs commit hashes (`a86fec1`, `21abb6d`, `d0b7de5`) verified present
in `git log --oneline --all`.
