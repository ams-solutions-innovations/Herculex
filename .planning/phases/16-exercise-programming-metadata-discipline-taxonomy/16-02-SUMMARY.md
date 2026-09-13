---
phase: 16-exercise-programming-metadata-discipline-taxonomy
plan: 02
subsystem: database
tags: [drift, sqlite, metadata, disciplines, progression-ladders, eligibility, basic-weights, safety]

# Dependency graph
requires:
  - "16-01: Drift ExerciseCatalog schema v41 with 6 metadata columns and TableMigration"
provides:
  - "Curated version 2 exercise_programming_metadata.json with 5 canonical disciplines, 7 progression chains, technical prerequisites, competition anchors, and specialization tags"
  - "ExerciseImporter companion mapping and profile parsing for all schema v41 columns with conservative 'manualOnly' defaults"
  - "ExerciseProgrammingEligibility two-layer hard gate for basic weights and strict novice ceiling barring intermediate/advanced movements"
  - "Test suites in test/exercise_programming_metadata_test.dart and test/exercise_programming_eligibility_test.dart"
affects: [16-03, 17-generator-core]

# Tech tracking
tech-stack:
  added: []
  patterns:
    - "Conservative default policy: uncurated rows default to manualOnly and advanced"
    - "Two-layer eligibility hard gate: commonness tier filter + modality/equipment whitelist/blacklist"
    - "1-indexed ascending progression ladders (1 = easiest regression, N = elite peak)"

key-files:
  created:
    - assets/data/exercise_programming_metadata.json
    - test/exercise_programming_metadata_test.dart
    - lib/features/programs/domain/exercise_programming_eligibility.dart
    - test/exercise_programming_eligibility_test.dart
  modified:
    - lib/data/local/exercise_importer.dart

key-decisions:
  - "Enforced 5 canonical disciplines (weights, calisthenics, crossfit, olympic, gpp) with set-based validation at import time."
  - "Structured 7 canonical progression chains (vertical_pull, horizontal_push, dips, handstand_pushup, pistol_squat, squat, hinge) with 1-indexed ascending scalingOrder."
  - "Updated ExerciseImporter to default uncurated legacy rows to 'manualOnly' with empty lists for disciplines and prerequisites."
  - "Implemented strict novice ceiling in ExerciseProgrammingEligibility: novice athletes are strictly barred from intermediate and advanced movements without relaxation."
  - "Implemented two-layer basicWeights filter: commonness must be basic or common, modality must match standard gym equipment, and specialty bars (SSB, Swiss bar, cambered bar, etc.) are explicitly blocked."

requirements-completed: [META-01, META-03]

# Metrics
duration: ~15m
completed: 2026-09-13
---

# Phase 16 Plan 02: Curated Asset Ingestion, Companion Mapping & Discipline Taxonomy Summary

Delivered curated Version 2 exercise programming metadata asset with canonical discipline taxonomy, 7 progression chains, companion mapping in `ExerciseImporter`, and a hardened two-layer eligibility gate in `ExerciseProgrammingEligibility`.

## Accomplishments
- **Version 2 Exercise Programming Metadata (`assets/data/exercise_programming_metadata.json`):**
  - Upgraded catalog metadata schema to version 2 covering 108 hand-curated exercises.
  - Curated canonical progression ladders:
    - `vertical_pull` (ranks 1–7 from assisted pull-up to ring muscle-up)
    - `horizontal_push` (ranks 1–6 from incline push-up to full planche)
    - `dips` (ranks 1–4 from bench dip to ring dips)
    - `handstand_pushup` (ranks 1–2 from pike push-up to handstand push-up)
    - `pistol_squat` (ranks 1–2 from TRX-assisted pistol squat to pistol squat)
    - `squat` (ranks 1–3 from dumbbell squat to barbell back squat)
    - `hinge` (ranks 1–3 from dumbbell RDL to conventional deadlift)
  - Curated technical prerequisites, competition anchors (`squat`, `bench`, `deadlift`, `overhead_press`), and sticking-point specialization tags.
  - Curated specialty bars (Swiss bar, Safety Squat Bar, cambered, pins, boards) as `specialty` and `manual_only`.
- **Exercise Importer Companion Mapping (`lib/data/local/exercise_importer.dart`):**
  - Expanded `_ProgrammingProfile` and `_programmingProfile()` to parse the 4 commonness tiers (`basic`, `common`, `specialty`, `manualOnly`), validating disciplines against the 5 canonical set.
  - Populated all 6 Drift schema v41 columns in `ExerciseCatalogCompanion` (`disciplines`, `prerequisiteSlugs`, `scalingGroup`, `scalingOrder`, `competitionAnchor`, `specializationTags`).
- **Two-Layer Basic Weights Hard Gate & Strict Novice Ceiling (`lib/features/programs/domain/exercise_programming_eligibility.dart`):**
  - Enforced strict novice ceiling: rank 0 (novice) cannot receive any intermediate or advanced movement, preventing premature escalation or injury.
  - Enforced manual-only exclusion: movements with commonness `manualOnly` or technical eligibility `manual_only` never enter automated program generation.
  - Implemented two-layer `basicWeights` filtering: Layer 1 requires `basic` or `common` commonness tier; Layer 2 enforces standard gym modalities (`barbell`, `dumbbell`, `cable`, `machine_plate`, `machine_selectorized`, `bodyweight`) and excludes barred specialty equipment (`safety_squat_bar`, `swiss_bar`, `cambered_bar`, `axle_bar`, `trap_bar`, `duffalo_bar`, `chains`, `reverse_hyper`, `ghr`, `belt_squat`).
- **Automated Verification:**
  - `test/exercise_programming_metadata_test.dart`: 3 tests passing, validating companion persistence, uncurated conservative `manualOnly` defaults, and idempotency.
  - `test/exercise_programming_eligibility_test.dart`: 5 tests passing, validating strict novice ceiling, 2-layer `basicWeights` hard gate, style compatibility, and uncurated row rejection.
