---
phase: 16-exercise-programming-metadata-discipline-taxonomy
plan: 03
subsystem: programs
tags: [programs, eligibility, prerequisites, scaling, regression, progression-ladders, safety]

# Dependency graph
requires:
  - "16-01: Drift ExerciseCatalog schema v41 with 6 metadata columns and TableMigration"
  - "16-02: Curated exercise programming metadata v2 and two-layer eligibility gate"
provides:
  - "ExerciseProgrammingEligibility.verifyPrerequisites dual-check verification with movement-family alias resolution"
  - "ExerciseScalingResolver ascending progressive regression ladder traversal with strict group boundary enforcement"
  - "Automated unit test suites in test/exercise_programming_eligibility_test.dart and test/exercise_scaling_resolver_test.dart"
  - "Clean execution and verification of the full 6-suite regression test suite"
affects: [17-generator-core, 21-crossfit, 22-specialization]

# Tech tracking
tech-stack:
  added: []
  patterns:
    - "Dual-check prerequisite verification: Condition (a) experience check vs Condition (b) history check"
    - "Movement-family alias resolution (D-08): Prerequisite check resolves variant exercises sharing canonical movementSlug"
    - "Ascending progressive regression ladder traversal (D-13): Candidate with highest scalingOrder < target.scalingOrder satisfying all hard guardrails"
    - "Strict boundary enforcement (D-16): Never silently jump modalities or scaling groups; return noSafeCandidate with clear rationale"

key-files:
  created:
    - lib/features/programs/domain/exercise_scaling_resolver.dart
    - test/exercise_scaling_resolver_test.dart
  modified:
    - lib/features/programs/domain/exercise_programming_eligibility.dart
    - test/exercise_programming_eligibility_test.dart

key-decisions:
  - "Dual-check prerequisite verification model (D-05, D-06): Prerequisite satisfied if user's experience >= prereq difficulty, OR user completed prereq or its movement family in history. Hard gate with zero relaxation."
  - "Movement-family fallback (D-08): When user history does not match the exact exercise slug, checks completedMovementSlugs against prereqExercise.movementSlug."
  - "Strict scaling ladder boundary enforcement (D-16): If all regression candidates are disqualified by equipment or experience, returns noSafeCandidate with explainable rationale rather than silently crossing modalities or movement patterns."
  - "Descending traversal for regression: Filters candidates within the exact same scalingGroup having scalingOrder < target.scalingOrder, sorted descending to find the closest safe regression."

requirements-completed: [META-02, META-04]

# Metrics
duration: ~15m
completed: 2026-09-13
---

# Phase 16 Plan 03: Prerequisite Dual-Check Verification & Progressive Scaling Resolver Summary

Delivered prerequisite verification with movement-family alias resolution, dedicated progressive scaling resolver service with strict boundary enforcement, and completed full regression test suite verification across all Phase 16 components.

## Accomplishments

- **Prerequisite Dual-Check Verification (`lib/features/programs/domain/exercise_programming_eligibility.dart`):**
  - Implemented `verifyPrerequisites` adhering strictly to D-05 and D-06.
  - Condition (a): User experience level meets or exceeds the prerequisite exercise's difficulty.
  - Condition (b): User has logged completion of the prerequisite exercise slug OR its canonical `movementSlug` family (D-08) in workout history.
  - Zero-relaxation hard gate: If any prerequisite fails both checks, the movement is rejected.
  - Expanded `test/exercise_programming_eligibility_test.dart` to cover experience satisfaction, empty history rejection, slug completion, movement family alias resolution, and multi-prerequisite validation.
- **Progressive Scaling Resolver Service (`lib/features/programs/domain/exercise_scaling_resolver.dart`):**
  - Created `ExerciseScalingResolver` and `ScalingResolutionResult` domain models.
  - Implemented `regress` traversing down the scaling ladder (`scalingOrder < target.scalingOrder`, sorted descending).
  - Enforced all hard guardrails per candidate: difficulty ceiling (novices barred from intermediate/advanced), technical eligibility (`manual_only` skipped, `technical_review` skipped for novices), training style and equipment compatibility (`ExerciseProgrammingEligibility.allows`), equipment availability, and prerequisite satisfaction (`verifyPrerequisites`).
  - Strict group boundary enforcement (D-16): When all regression candidates are disqualified by equipment or experience, returns `noSafeCandidate` with clear rationale and `candidate == null`, preventing silent modal or pattern jumps.
  - Comprehensive unit test coverage in `test/exercise_scaling_resolver_test.dart` validating intermediate regressions, novice regressions, equipment-based fallbacks, missing equipment boundaries, and non-ladder movements.
- **Full Phase 16 Regression Suite Verification:**
  - Ran all 6 test suites: `test/migration_test.dart`, `test/exercise_programming_metadata_supabase_migration_test.dart`, `test/exercise_programming_metadata_test.dart`, `test/exercise_programming_eligibility_test.dart`, `test/exercise_scaling_resolver_test.dart`, and `test/smart_program_planner_test.dart`.
  - All 46 tests executed cleanly and passed in 15 seconds.
  - Zero regressions in existing program generation or schema migrations.

## Verification Results

```
flutter test test/migration_test.dart test/exercise_programming_metadata_supabase_migration_test.dart test/exercise_programming_metadata_test.dart test/exercise_programming_eligibility_test.dart test/exercise_scaling_resolver_test.dart test/smart_program_planner_test.dart
00:15 +46: All tests passed!
```
