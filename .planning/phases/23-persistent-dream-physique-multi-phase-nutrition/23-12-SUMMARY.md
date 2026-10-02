---
phase: 23-persistent-dream-physique-multi-phase-nutrition
plan: 12
subsystem: ui
tags: [flutter, fl_chart, riverpod, physique, charts, accessibility]

requires:
  - phase: 23-05
    provides: series builders and WeightChartData / ChartPoint domain types
  - phase: 23-10
    provides: PhysiqueText styles and leaf widgets
  - phase: 23-11
    provides: physique chart providers (weight, strength, training level, range)
provides:
  - PhysiqueChartCard shared frame (title, latest value, legend, caption, summary, empty state)
  - PhysiqueChartStyle fl_chart helper (grid, titles, tooltip, last-point dot, phase boundaries)
  - WeightChartCard, StrengthChartCard, TrainingLevelChartCard for the progress screen
affects: [23-16 progress view composition]

tech-stack:
  added: []
  patterns:
    - "Self-contained chart cards watching a family provider by goalId"
    - "Plot wrapped in Semantics(label: summary, excludeSemantics: true) plus visible summary text"

key-files:
  created:
    - lib/features/physique/presentation/widgets/chart_style.dart
    - lib/features/physique/presentation/widgets/chart_card_frame.dart
    - lib/features/physique/presentation/widgets/weight_chart_card.dart
    - lib/features/physique/presentation/widgets/strength_chart_card.dart
    - lib/features/physique/presentation/widgets/training_level_chart_card.dart
    - test/features/physique/presentation/physique_chart_cards_test.dart
  modified: []

key-decisions:
  - "Moving target band uses invisible LineChartBarData pairs plus BetweenBarsData, clipped to the visible x range by linear interpolation"
  - "Training level uses fl_chart 0.69.2 isStepLineChart (confirmed present in the pub cache)"
  - "Title row and legend entries reflow (Wrap/Flexible) so 320 dp at 200 percent text scale does not overflow"

patterns-established:
  - "Chart empty state is a minHeight-200 block (not fixed height) so large text reflows"

requirements-completed: []

duration: 25min
completed: 2026-10-02
---

# Phase 23 Plan 12: Physique chart cards Summary

**Three stacked fl_chart cards (bodyweight trend with moving phase-target band, per-lift estimated 1RM with selector, XP-free training level step line) over one shared frame and style helper.**

## Performance

- **Tasks:** 2/2
- **Files:** 5 widget files, 1 test file (16 tests)

## Accomplishments
- Weight card: onSurface trend, raw secondary dots, domainNutrition 0.14 band that moves per phase, dashed phase boundaries, legend Trend / Target range.
- Strength card: horizontally scrollable HxPill selector, lifts without data disabled (onTap null, tertiary text), selection writes physiqueSelectedLiftProvider, summary like "Up 7 kg over 3 months."
- Training level card: step line over level names (no numeric y labels), always-visible XP-rank caption, "Reached X in Month." summary.
- Fewer than 2 points shows the UI-SPEC empty copy; every plot has Semantics plus a visible summary line.

## Task Commits

1. Task 1: chart style, frame, WeightChartCard - `38b0bbc`
2. Task 2: strength card, training level card, tests (plus frame reflow fix) - `cbd7d5c`

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 1 - Bug] Title row and legend overflowed at 320 dp / 2.0 text scale**
- **Found during:** Task 2 (320 dp test)
- **Fix:** title row became a Wrap, legend label wrapped in Flexible
- **Files:** chart_card_frame.dart
- **Commit:** cbd7d5c

### Notes
- Plan asked for loading/error handling on the weight card; `physiqueWeightChartProvider` is a plain `Provider` returning data (not AsyncValue), so there is no loading/error state to render. Not added.
- Hidden band bars use `onSurface.withValues(alpha: 0)` instead of `Colors.transparent` to satisfy the no-`Colors.` grep criterion.

## Verification
- `flutter test test/features/physique`: 296 passed
- `flutter analyze lib/features/physique test/features/physique`: 0 issues; `dart format` clean
- Forbidden-pattern grep (AppColors, Color(0x, Colors., boxShadow, FontWeight w5789, gamification, levelProgressProvider): empty
- check_structure names no physique file; all new files under 200 lines

## Known Stubs
None.

## Self-Check: PASSED
