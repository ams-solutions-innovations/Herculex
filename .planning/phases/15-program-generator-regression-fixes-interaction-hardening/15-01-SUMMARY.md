---
phase: 15-program-generator-regression-fixes-interaction-hardening
plan: 01
subsystem: programs
tags: [programs, generator, linear, dynamic-effort, set-parity, guardrails]

# Dependency graph
requires: []
provides:
  - "Prescription guardrails in SmartProgramPlanner forbidding dynamic effort for novice or linear programs"
  - "Prescription guardrails in PlannedSessionResolver preventing expansion into 8x3 dynamic effort sets"
  - "Set parity between program review target sets and active workout materialized sets"
affects: [15-02, 15-03]

# Tech tracking
tech-stack:
  added: []
  patterns:
    - "Early defensive normalization of SlotTrainingMethod based on PeriodizationModel and ExperienceLevel"

key-files:
  created: []
  modified:
    - lib/features/programs/data/smart_program_planner.dart
    - lib/features/workouts/data/planned_session_resolver.dart
    - test/smart_program_planner_test.dart
    - test/planned_session_resolver_test.dart

key-decisions:
  - "Novice and linear periodization splits strictly normalize SlotTrainingMethod.dynamicEffort back to SlotTrainingMethod.straightSets."
  - "Full body splits (full_body, full_body_linear, full_body_ab, full_body_ab_gpp) never assign DayStressRole.dynamicTechnique."
  - "PlannedSessionResolver respects explicit.targetSets on linear programs and does not expand to Westside dynamic 8x3 sets."

requirements-completed: [FIX-01]

# Metrics
duration: ~15m
completed: 2026-09-13
---

# Phase 15 Plan 01: Program Generator Prescription Guardrails & Set Parity Summary

Hardened `SmartProgramPlanner` and `PlannedSessionResolver` against accidental Dynamic Effort (8x3) generation in novice and linear programs, ensuring complete set count parity between plan review and materialized workouts.

## Accomplishments
- Fixed test harness in `test/smart_program_planner_test.dart` to import catalog, movement, and programming metadata in `setUp`.
- Hardened `_stressRole`, `_methodFor`, and `_createStableSlots` in `SmartProgramPlanner` so full body linear programs cannot assign `DayStressRole.dynamicTechnique` or `SlotTrainingMethod.dynamicEffort`.
- Added defense-in-depth in `PlannedSessionResolver` and `_resolvePrescription` to normalize `SlotTrainingMethod.dynamicEffort` to `SlotTrainingMethod.straightSets` when `PeriodizationModel.linear` is configured.
- Added regression test `linear novice workout session resolves straight sets matching targetSets and never 8x3` to `test/planned_session_resolver_test.dart`.
- Verified all 8 unit tests in `test/smart_program_planner_test.dart` and all 4 unit tests in `test/planned_session_resolver_test.dart` pass.
