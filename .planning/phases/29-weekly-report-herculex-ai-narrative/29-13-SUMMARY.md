---
phase: 29-weekly-report-herculex-ai-narrative
plan: 13
subsystem: weekly-report
tags: [flutter, widgets, design-system, ai-narrative, tdd]

requires:
  - phase: 29-weekly-report-herculex-ai-narrative
    provides: "WeeklyNarrative (29-01), section value classes (29-07), correlation/recovery/physique outputs (29-12)"
provides:
  - "NarrativeStatus enum (loading, ready, pending, offline, quotaExhausted)"
  - "SectionCardScaffold, ReportText (16/14/20 type roles), ReportTileGrid, signedNumber"
  - "NutritionSectionCard, TrainingSectionCard, RecoverySectionCard, PhysiqueSectionCard (nullable section in, provider-free)"
  - "AiNarrativeCard (provider-free, status/narrative/onRetry/retryEnabled)"
affects: [29-15, 29-16, 29-17, 29-18]

tech-stack:
  added: []
  patterns:
    - "Report widgets take plain data and an explicit status; controllers own all provider access"
    - "Disabled PremiumButton via Semantics + IgnorePointer + Opacity (the button has no disabled state)"

key-files:
  created:
    - lib/features/weekly_report/domain/narrative_status.dart
    - lib/features/weekly_report/presentation/widgets/section_card_scaffold.dart
    - lib/features/weekly_report/presentation/widgets/nutrition_section_card.dart
    - lib/features/weekly_report/presentation/widgets/training_section_card.dart
    - lib/features/weekly_report/presentation/widgets/recovery_section_card.dart
    - lib/features/weekly_report/presentation/widgets/physique_section_card.dart
    - lib/features/weekly_report/presentation/widgets/ai_narrative_card.dart
    - test/features/weekly_report/weekly_report_cards_test.dart
  modified: []

key-decisions:
  - "The AI footer note is shown in every state (plan truth: it always shows), not only in Ready"
  - "A ready status with a null narrative falls back to the pending face instead of an empty card"
  - "A PhysiqueSection with neither verdict nor bodyweight renders as no-data"
  - "Disabled Retry is built around PremiumButton (shared widget left untouched): dimmed, taps ignored, semantics enabled=false"

patterns-established:
  - "ReportText.heading/body/label give the UI-SPEC 20/16/14 roles without touching the global theme sizes"

requirements-completed: [RPT-01, RPT-02, RPT-05]

duration: 25min
completed: 2026-10-03
---

# Phase 29 Plan 13: Report Section Cards and Herculex AI Card Summary

**Four measured section cards (domain-tinted, payload-only) plus a separate provider-free Herculex AI card covering five states with per-day quota copy.**

## Tasks

| Task | Commits |
|------|---------|
| 1. Scaffold + four measured cards | b2673ed (RED), 66b2dc7 (GREEN) |
| 2. NarrativeStatus + AiNarrativeCard | 775c89e (RED), 5b97348 (GREEN) |

20 widget tests pass; `flutter analyze` on the feature and test dirs is clean; `check_structure` reports no weekly_report violations.

## Deviations from Plan

### Judgement calls (no rule triggered)

1. **Interpretation grep gate.** The acceptance grep `grep -rn "interpretation" lib/features/weekly_report/presentation` is not empty: it matches the required Semantics label `'Herculex AI interpretation'` in `ai_narrative_card.dart`. The intent (never read `BiometricCorrelationResult.interpretation`) holds; no such field is referenced.
2. **HxStatTile type sizes.** The plan mandates `HxStatTile` for headline numbers, but the shared tile renders values at 22 and labels at 12, not the UI-SPEC 28/14. The shared design-system component was left untouched; if the spec sizes matter, a follow-up should add a size option to `HxStatTile`.
3. **Disabled Retry.** `PremiumButton` has no disabled state; handled in the card rather than editing the shared button.

No auto-fix rules (1-3) were needed beyond a test-finder change: the Semantics label test uses a widget predicate because `bySemanticsLabel` does not see the merged container label.

## Known Stubs

None.

## Threat Flags

None. T-29-51/52/53 mitigations verified by grep: no `hx.primary` outside the AI card, no `this month`/`Gemini`, statements rendered verbatim (tested with exact-string finder).

## Self-Check: PASSED

All eight files exist and commits b2673ed, 66b2dc7, 775c89e, 5b97348 are in git history.
