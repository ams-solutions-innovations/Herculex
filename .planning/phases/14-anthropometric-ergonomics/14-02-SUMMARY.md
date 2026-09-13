---
phase: 14-anthropometric-ergonomics
plan: 02
subsystem: workouts
tags: [ergonomics, exercise, corpus, json]

# Dependency graph
requires:
  - plan: 14-01
    provides: Anthropometry proportion definitions
provides:
  - "assets/data/exercise_ergonomics.json with movement guidance and citations"
  - "ExerciseErgonomics domain models and ExerciseErgonomicsRepository"
affects: [14-03]

# Tech tracking
tech-stack:
  added: []
  patterns:
    - "Offline JSON asset corpus loaded into in-memory repository cache"

key-files:
  created:
    - assets/data/exercise_ergonomics.json
    - lib/features/workouts/domain/exercise_ergonomics.dart
    - lib/features/workouts/data/exercise_ergonomics_repository.dart
    - test/features/workouts/data/exercise_ergonomics_repository_test.dart
  modified:
    - lib/features/workouts/application/workouts_providers.dart

key-decisions:
  - "Guidance is keyed on movementSlug (squat, deadlift, bench_press, overhead_press) rather than individual catalog exercises."
  - "Every guidance item records citations/sources to maintain evidence-based integrity."

requirements-completed: [ERG-02]

# Metrics
duration: ~15m
completed: 2026-09-13
---

# Phase 14 Plan 02: Exercise Ergonomics Corpus Summary

Created structured exercise ergonomics corpus with citations and repository loader.

## Accomplishments
- Authored `assets/data/exercise_ergonomics.json` covering major compound movements (`squat`, `deadlift`, `bench_press`, `overhead_press`) with specific guidance based on anthropometric proportion variations and literature citations (Starting Strength, etc.).
- Implemented `ExerciseErgonomics` and `ErgonomicGuidance` domain models with JSON deserialization.
- Implemented `ExerciseErgonomicsRepository` with asset loading and in-memory caching.
- Registered `exerciseErgonomicsRepositoryProvider` in `workouts_providers.dart`.
- Tested in `test/features/workouts/data/exercise_ergonomics_repository_test.dart`.
