---
phase: 29-weekly-report-herculex-ai-narrative
plan: 16
subsystem: weekly-report
tags: [tdee, nutrition-targets, riverpod, widgets, phys-04, tdd]

requires:
  - phase: 29-weekly-report-herculex-ai-narrative
    provides: "WeeklyReportRepository.recordTdeeDecision (29-06), TdeeSection and shift calculator (29-12), ReportText and SectionCardScaffold (29-13), weekly report providers (29-15)"
provides:
  - "TdeeTargetProposalCalculator.compute: pure, delta-preserving, floor- and eligibility-clamped target proposal"
  - "TdeeDecisionActions (update / keep), tdeeDecisionActionsProvider, tdeeTargetProposalProvider, savedTargetLabelProvider, isActionableWeek"
  - "TdeeShiftCard(record, section): actionable / decided / read-only card for the report view"
affects: [29-18]

tech-stack:
  added: []
  patterns:
    - "Single write path to targets: two user-tap methods, grep-gated to one file"
    - "Proposal provider is a record-keyed autoDispose family (oldKcal, newKcal)"

key-files:
  created:
    - lib/features/weekly_report/domain/tdee_target_proposal.dart
    - lib/features/weekly_report/application/weekly_report_tdee_actions.dart
    - lib/features/weekly_report/presentation/widgets/tdee_shift_card.dart
    - test/features/weekly_report/tdee_shift_card_test.dart
  modified:
    - test/features/weekly_report/tdee_shift_test.dart

key-decisions:
  - "OQ2 (user-confirmed 2026-10-03): X = saved rule kcal + (new - old estimate), rounded to nearest 10, protein and fat kept, carbs absorb the remainder, same appliesTo scope"
  - "A restricted member's increase goes through PhaseEligibility.clampDelta(maingain); a clamp to zero delta, a floor-clamp onto the current kcal, a result outside 800..6000 or no room for carbs offers no action"
  - "update() validates the decision range and the empty/decided row BEFORE upsertTarget, so a target is never written without its decision being recordable"
  - "The card is a ConsumerStatefulWidget (plan sketched ConsumerWidget) to hold the busy flag that disables both buttons while a call runs; busy stays true after success until the stored decision re-renders the card"

patterns-established:
  - "grep -rn upsertTarget lib/features/weekly_report matches only weekly_report_tdee_actions.dart (the other hit is its own header comment)"

requirements-completed: []
requirements-partial: [RPT-01, RPT-04]

duration: 40min
completed: 2026-10-03
---

# Phase 29 Plan 16: TDEE shift card Summary

**Self-contained D-11 card: a delta-preserving, PHYS-04-clamped "Update my target to X kcal" proposal whose only write path is two user-tap actions recording a write-once decision on the report row.**

## What was built

- `tdee_target_proposal.dart` (domain, plain Dart): `TdeeProposalStatus { proposed, noSavedRule, noChange, belowMacroFloor }`, `TdeeTargetProposal`, `TdeeTargetProposalResult` and `TdeeTargetProposalCalculator.compute`. The file header documents OQ2 and why maintenance replacement was rejected.
- `weekly_report_tdee_actions.dart`: `TdeeDecisionActions.update` (reads the row, refuses when absent or already decided, then `upsertTarget`, then `recordTdeeDecision('updated', kcal)`) and `.keep` (decision only, never touches targets); `isActionableWeek` (current ISO week or due week); `tdeeDecisionActionsProvider`; `tdeeTargetProposalProvider` (saved rule from `savedTargetForTodayProvider`, floor from `minimumTargetsProvider.effectiveMinCaloriesKcal`, eligibility from `physiqueEditorEligibilityProvider`); `savedTargetLabelProvider` (label of the saved row for the scope, fallback `Target`).
- `tdee_shift_card.dart`: `HxCard(accent: domainNutrition)` with heading, `{old} -> {new} kcal` at 28/600 and a signed delta label, always from the frozen `TdeeSection`. States: actionable (primary `PremiumButton` plus 48-high text button, both disabled while busy, snackbar on success), decided (one label line, no buttons), past week (read-only line), no saved rule (follows-estimate line), noChange / belowMacroFloor (no-suggestion line).
- 37 tests in `tdee_shift_test.dart` (calculator, actions on a real in-memory database, `isActionableWeek`, provider) and 11 in `tdee_shift_card_test.dart`.

## Task commits

| Task | Commit | Description |
| ---- | ------ | ----------- |
| 1 RED | c12b81b | failing calculator tests |
| 1 GREEN | df68ac0 | TdeeTargetProposalCalculator |
| 2 RED | 6d002be | failing actions / provider tests |
| 2 GREEN | 4cfff48 | actions, providers, isActionableWeek |
| 3 RED | 7533c1f | failing card tests |
| 3 GREEN | 9f5779a | TdeeShiftCard |

## Verification

- `flutter test test/features/weekly_report`: 360 passed.
- `flutter analyze lib/features/weekly_report test/features/weekly_report`: no issues. `dart format` clean. `check_structure` reports nothing for weekly_report.
- Greps: `upsertTarget` in `lib/features/weekly_report` appears only in `weekly_report_tdee_actions.dart` (call site plus its header comment); `TdeeDecisionActions` / `tdeeDecisionActionsProvider` used only in that file and `tdee_shift_card.dart`; no `AppColors.`, `Color(0x`, `appDatabaseProvider` or `package:drift` in the card; no `package:flutter` / drift / riverpod in the domain file.
- Tests assert: `nutrition_targets` unchanged after `keep()` and after a second `update()`; no buttons for a decided record, a past week, a no-rule state and noChange / belowMacroFloor.
- TDD gate: `test(...)` commit precedes `feat(...)` for all three tasks.

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 2 - Missing critical] Storable-range guard before the target write**
- **Found during:** Task 2
- **Issue:** `recordTdeeDecision` throws for kcal outside 800..6000. With the plan's order (upsert then record), an out-of-range proposal would have written the target and then thrown, leaving a changed target with no recorded decision.
- **Fix:** The calculator treats results outside 800..6000 as `noChange`, and `update()` also refuses such a proposal before any write (tested).
- **Files modified:** tdee_target_proposal.dart, weekly_report_tdee_actions.dart
- **Commits:** df68ac0, 4cfff48

### Judgement calls

- Widget is stateful (see key-decisions); the plan sketch said `ConsumerWidget`.
- `Keep current target` uses the saved rule's kcal (via `savedTargetForTodayProvider`), as the plan states, rather than the proposal.
- Acceptance grep `grep -c "DateTime.now" weekly_report_tdee_actions.dart` prints 1: the unescaped `.` matches the `DateTime now` parameter of `isActionableWeek`. No wall-clock read exists; the card takes time from `clockProvider`.
- The card shows a `Icons.bolt` glyph in `domainNutrition` next to the heading; the UI-SPEC does not name an icon for this card.

## Known Stubs

None.

## Threat Flags

None. T-29-64 to T-29-68 are mitigated as planned: single grep-gated write path, write-once decision, PHYS-04 clamp and floor, delta-preserving semantics with read-only no-rule state, actionable-week rule.

## Known limitations

- The proposal is computed against the saved rule that applies to TODAY (training day vs rest day matters). A scoped rule (`training_day`, `weekday:N`) is updated only for its own scope.
- The card is not mounted yet; plan 18 mounts it in the report view when `section.material` is true.

## Requirements

RPT-01 and RPT-04 stay unchecked (partial-completion convention): the report view and dashboard entry arrive in plans 17 and 18.

## Self-Check: PASSED

- Files present: tdee_target_proposal.dart, weekly_report_tdee_actions.dart, tdee_shift_card.dart, tdee_shift_test.dart, tdee_shift_card_test.dart.
- Commits present: c12b81b, df68ac0, 6d002be, 4cfff48, 7533c1f, 9f5779a.
