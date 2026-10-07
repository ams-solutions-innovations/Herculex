---
phase: 23-persistent-dream-physique-multi-phase-nutrition
plan: 05
subsystem: physique-domain
tags: [dart, domain, tdd, charts, verdict]
requires:
  - phase: 23-01
    provides: PhysiqueTuning constants, AssessmentConfidence
provides:
  - RoadmapExitEvaluator (PhaseProgress, ExitEvaluation) with advance offer and snooze
  - CheckInCapPolicy (7 calendar day window, DST-safe)
  - CheckInVerdict / CheckInBand / CheckInEvidence / CheckInVerdictClassifier
  - ChartRange, PhysiqueSeriesBuilder.weight, WeightTrendRate
  - StrengthSample, E1rmSeriesBuilder, TrainingLevelSeriesBuilder
affects: [23-06, 23-07, 23-10, 23-11, 23-12]
tech-stack:
  added: []
  patterns: [pure-dart domain, clock passed as parameter, calendar-day arithmetic via TrendSeries.dayNumber]
key-files:
  created:
    - lib/features/physique/domain/roadmap_exit_criteria.dart
    - lib/features/physique/domain/check_in_policy.dart
    - lib/features/physique/domain/check_in_verdict.dart
    - lib/features/physique/domain/physique_series.dart
    - lib/features/physique/domain/physique_strength_series.dart
    - test/features/physique/roadmap_exit_criteria_test.dart
    - test/features/physique/check_in_policy_test.dart
    - test/features/physique/check_in_verdict_test.dart
    - test/features/physique/physique_series_test.dart
  modified: []
key-decisions:
  - "Training level is a weekly step line from ExperienceLevel.recommend with RIR and structured-block flags false, so it caps at intermediate; no XP/gamification dependency"
  - "Trend can only downgrade an on-track verdict; off-track and inconclusive are never altered by it"
  - "Maingain uses the bulk-style weight criterion (>= target)"
metrics:
  tasks: 3
  files: 9
  completed: 2026-10-02
---

# Phase 23 Plan 05: Physique Domain Rules Summary

Pure-Dart exit-criteria evaluator, DST-safe 7-day check-in cap, deterministic three-state verdict classifier and windowed weight/e1RM/training-level series builders, all with fakeable time and no Flutter, data or XP imports.

## Tasks

| Task | Name | Commit |
| ---- | ---- | ------ |
| 1 | RoadmapExitEvaluator and CheckInCapPolicy | 1e58d9c |
| 2 | CheckInVerdictClassifier | 11d640e |
| 3 | Weight, e1RM and training-level series | 5596d0f |

## Verification

- `flutter test test/features/physique`: 108 pass
- `flutter analyze lib/features/physique test/features/physique`: no issues
- `dart format --set-exit-if-changed`: clean
- Greps for `DateTime.now`, `package:flutter/`, `/data/`, `gamification`, `percent|pct`, and kcal/calorie in the domain files: none
- `check_structure.dart` names no `features/physique` file (it lists two pre-existing profile files)

## Deviations from Plan

None - plan executed as written. A silent first draft of the training-level builder carried leftover scratch lines; they were removed before commit.

## Known Stubs

None.

## Threat Flags

None.

## Self-Check: PASSED
