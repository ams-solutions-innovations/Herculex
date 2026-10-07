---
phase: 16-exercise-programming-metadata-discipline-taxonomy
plan: 01
subsystem: database
tags: [drift, sqlite, supabase, schema-v41, migrations, metadata, disciplines, scaling]

# Dependency graph
requires: []
provides:
  - "Asset packaging of exercise_programming_metadata.json in pubspec.yaml flutter.assets"
  - "Drift ExerciseCatalog schema v41 with disciplines, prerequisiteSlugs, scalingGroup, scalingOrder, competitionAnchor, specializationTags"
  - "Drift schema dump snapshot drift_schema_v41.json and generated migration code schema_v41.dart"
  - "Drift TableMigration-based table rewrite on ExerciseCatalog updating programmingCommonness default to manualOnly and adding v41 columns"
  - "Supabase migration 20260913000000_exercise_programming_metadata_v41.sql with 1:1 parity and check constraints"
  - "Automated migration replay test suite in test/migration_test.dart and cloud schema test in test/exercise_programming_metadata_supabase_migration_test.dart"
affects: [16-02, 16-03]

# Tech tracking
tech-stack:
  added: []
  patterns:
    - "Drift TableMigration for clean SQLite table rewrite updating column defaults and adding non-destructive columns"
    - "Mirroring Drift local SQLite schema with Supabase cloud PostgreSQL migration"

key-files:
  created:
    - drift_schemas/drift_schema_v41.json
    - test/generated_migrations/schema_v41.dart
    - supabase/migrations/20260913000000_exercise_programming_metadata_v41.sql
    - test/exercise_programming_metadata_supabase_migration_test.dart
  modified:
    - pubspec.yaml
    - lib/data/local/tables.dart
    - lib/data/local/database.dart
    - lib/data/local/database.g.dart
    - test/generated_migrations/schema.dart
    - test/migration_test.dart

key-decisions:
  - "Packaged assets/data/exercise_programming_metadata.json explicitly under flutter.assets in pubspec.yaml to prevent silent degradation in release builds."
  - "Updated ExerciseCatalog.programmingCommonness default conservatively to 'manualOnly' and added 6 new programming metadata columns."
  - "Used Drift's TableMigration in database.dart onUpgrade (from < 41 && to >= 41) to cleanly rewrite exercise_catalog, applying new column defaults and avoiding SQLite ALTER TABLE limitations."
  - "Created PostgreSQL Supabase migration with 4-tier check constraint (basic, common, specialty, manualOnly) and idx_exercise_catalog_scaling index."

requirements-completed: [META-01]

# Metrics
duration: ~15m
completed: 2026-09-13
---

# Phase 16 Plan 01: Schema v41 Migration, Drift Codegen & Asset Packaging Summary

Delivered Drift and Supabase schema v41 with first-class exercise programming metadata, 5 canonical disciplines, technical prerequisite chains, ascending scaling ladders, and explicit asset packaging.

## Accomplishments
- **Asset Packaging (pubspec.yaml):** Declared `assets/data/exercise_programming_metadata.json` under `flutter.assets:`, eliminating runtime asset bundling failures in production APK/bundles.
- **Drift Table Definitions (tables.dart):** Updated `ExerciseCatalog` to default `programmingCommonness` to `'manualOnly'`, and added `disciplines`, `prerequisiteSlugs`, `scalingGroup`, `scalingOrder`, `competitionAnchor`, and `specializationTags`.
- **Database Schema v41 & Migration (database.dart):** Bumped `schemaVersion` to 41, added `idx_exercise_catalog_scaling` index in `onCreate` and `onUpgrade`, and implemented table migration via `m.alterTable(TableMigration(exerciseCatalog, newColumns: newColumns))` for robust upgrade replay.
- **Drift Schema Tooling & Codegen:** Generated schema snapshot `drift_schemas/drift_schema_v41.json`, migration code `test/generated_migrations/schema_v41.dart`, and regenerated `lib/data/local/database.g.dart`.
- **Supabase Parity Migration:** Authored `supabase/migrations/20260913000000_exercise_programming_metadata_v41.sql` with column definitions matching Drift v41, updated 4-tier check constraint, and scaling index.
- **Automated Validation:**
  - `test/migration_test.dart`: All 15 tests passed cleanly, validating migrations from fixtures v23, v24, v25, v26, v27, v28, v29, v30, v31, v32, v34, v37, v39, and v40 into v41.
  - `test/exercise_programming_metadata_supabase_migration_test.dart`: Both v40 and v41 schema assertion tests passed.
