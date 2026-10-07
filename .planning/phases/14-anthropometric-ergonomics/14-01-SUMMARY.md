---
phase: 14-anthropometric-ergonomics
plan: 01
subsystem: profile
tags: [profile, anthropometry, ratios, measurements]

# Dependency graph
requires:
  - phase: 12-catalogue-integrity-and-logging-metrics
    provides: exercise movements and units
provides:
  - "Profile fields: inseamCm, armSpanCm, torsoCm"
  - "AnthropometryRatios domain service calculating Ape Index, leg-to-height, and torso-to-height ratios"
affects: [14-02, 14-03]

# Tech tracking
tech-stack:
  added: []
  patterns:
    - "Pure Dart domain calculation of proportion ratios from user profile measurements"

key-files:
  created:
    - lib/features/profile/domain/anthropometry.dart
    - test/features/profile/domain/anthropometry_test.dart
  modified:
    - lib/features/profile/domain/profile.dart
    - lib/features/profile/presentation/profile_view/_body.part.dart

key-decisions:
  - "Proportions categorize into short, average, long based on standard biomechanical thresholds (Ape Index < 0.98 / > 1.02; Leg ratio < 0.44 / > 0.48; Torso ratio < 0.32 / > 0.36)."
  - "Measurements default to null and return null ratios if missing (no defaulted guesses)."

requirements-completed: [ERG-01]

# Metrics
duration: ~15m
completed: 2026-09-13
---

# Phase 14 Plan 01: Anthropometry Ratios & Profile Extensions Summary

Extended profile model with optional anthropometric measurements and created proportion ratio calculations.

## Accomplishments
- Added `inseamCm`, `armSpanCm`, and `torsoCm` to `Profile` entity and serialization.
- Added input fields to `_body.part.dart` in the profile view for user input and editing.
- Created `AnthropometryRatios` in `lib/features/profile/domain/anthropometry.dart` calculating Ape Index, leg-to-height ratio, and torso-to-height ratio, evaluating proportion categories.
- Added unit tests in `test/features/profile/domain/anthropometry_test.dart` verifying calculation accuracy across different body builds and handling missing measurements.
