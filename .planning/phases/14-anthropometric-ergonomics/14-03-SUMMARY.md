---
phase: 14-anthropometric-ergonomics
plan: 03
subsystem: workouts
tags: [ui, ergonomics, hercul, rules, exercise-details]

# Dependency graph
requires:
  - plan: 14-01
  - plan: 14-02
provides:
  - "ErgonomicsCard in ExerciseDetailsView rendering tailored proportion guidance"
  - "Hercul coaching engine integration with anthropometric signals and ergonomics rules"
affects: []

# Tech tracking
tech-stack:
  added: []
  patterns:
    - "Dynamic display of biomechanical trade-offs conditioned on user proportion ratios"
    - "Graceful absence of advice when measurements are unknown"

key-files:
  created:
    - test/features/workouts/presentation/ergonomics_card_test.dart
  modified:
    - lib/features/workouts/presentation/views/exercise_details_view.dart
    - lib/features/hercul/domain/hercul_context.dart
    - lib/features/hercul/application/hercul_providers.dart
    - assets/data/hercul_rules.json

key-decisions:
  - "Guidance is hidden if the user has not provided required limb or torso measurements, avoiding speculative advice."
  - "Copy is framed as mechanical trade-offs (e.g. low-bar for long femurs) rather than form defects or corrections."
  - "Ergonomics rules in Hercul corpus integrated into the standard Hercul rule evaluation flow."

requirements-completed: [ERG-03]

# Metrics
duration: ~25m
completed: 2026-09-13
---

# Phase 14 Plan 03: UI and Hercul Integration Summary

Integrated anthropometric ergonomic guidance into exercise details UI and the Hercul coaching engine.

## Accomplishments
- Implemented `ErgonomicsCard` in `exercise_details_view.dart`, displaying guidance and citations tailored to the user's specific limb and torso proportions.
- Enforced ERG-03 constraint: guidance is hidden if measurements are missing or proportions are standard, and phrasing highlights biomechanical trade-offs.
- Expanded `HerculSignals` in `hercul_context.dart` with ergonomics proportion labels (`ergonomics.proportion.leg`, `ergonomics.proportion.arm`, `ergonomics.proportion.torso`, `workout.next_exercise_mechanics`).
- Populated proportion signals into `HerculContext` in `hercul_providers.dart` from `Profile` anthropometry.
- Authored and verified ergonomics rules in `assets/data/hercul_rules.json` with both normal and honest tones.
- Added automated widget tests in `test/features/workouts/presentation/ergonomics_card_test.dart` and verified against full test suite.
