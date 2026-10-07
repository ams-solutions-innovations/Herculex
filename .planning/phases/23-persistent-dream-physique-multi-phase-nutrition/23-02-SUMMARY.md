---
phase: 23-persistent-dream-physique-multi-phase-nutrition
plan: 02
subsystem: database
tags: [drift, schema-v47, supabase, sync, physique]
requires: []
provides:
  - "four synced drift tables: physique_goals, physique_assessments, physique_roadmap_phases, physique_photos (local schema v47)"
  - "supabase/migrations/20261002000000_physique_v47.sql (written, NOT applied)"
affects: [23-03, 23-06, 23-07, 23-17]
tech-stack:
  added: []
  patterns: ["guarded onUpgrade createTable via sqlite_master", "text-level Supabase parity test derived from drift classes"]
key-files:
  created:
    - drift_schemas/drift_schema_v47.json
    - test/generated_migrations/schema_v47.dart
    - supabase/migrations/20261002000000_physique_v47.sql
    - test/physique_sync_registration_test.dart
    - test/physique_supabase_migration_test.dart
  modified:
    - lib/data/local/tables.dart
    - lib/data/local/database.dart
    - lib/data/local/database.g.dart
    - lib/data/local/migrations/sync_backfill.dart
    - lib/data/sync/sync_table_specs.dart
    - test/generated_migrations/schema.dart
    - test/migration_test.dart
    - test/schema_v25_test.dart
    - test/schema_v27_test.dart
    - test/schema_v28_test.dart
    - test/schema_v29_test.dart
    - test/fk_constraints_test.dart
key-decisions:
  - "Photos sync metadata only (relative_path, pose, date); no bytes column anywhere"
  - "estimated_months / target_bf_percent nullable, target_aesthetic_style defaults '' so a photos-only legacy_import goal is storable (D-08)"
  - "No CHECK constraints on text vocabularies; validation stays at the Plan 06 repository boundary"
requirements-completed: []
duration: ~45min
completed: 2026-10-02
---

# Phase 23 Plan 02: Physique schema v47 Summary

Four synced physique tables at drift schema v47 with a guarded upgrade, sync registration, regenerated drift artifacts, retargeted migration tests, and a Supabase migration (written, not applied) guarded by a snake_case parity test.

## Tasks

| Task | Commit | What |
| ---- | ------ | ---- |
| 1 | fea9dc0 | Tables, schemaVersion 47, guarded `from < 47` block, sync_backfill + sync_table_specs (goals L0, assessments/phases L1, photos L2), codegen, schema dump v47, generated fixture |
| 2 | 73b498c | migration_test retargeted to 47 plus a v46 to v47 replay (tables, sync_uuid indexes, outbox triggers); schema_v25/27/28/29 retargeted; new physique_sync_registration_test |
| 3 | 73b6c3f | Supabase SQL (4 tables, 16 policies, triggers, realtime, pull indexes) and parity test |

## Verification

- `flutter test` on migration_test, schema_v21/24/25/27/28/29, physique_sync_registration, tdee_sync_registration, fk_constraints, test/sync: all pass (61 passed, 9 skipped live-Supabase).
- physique/tdee/briefs Supabase migration tests: 21 pass.
- `flutter analyze lib/data` and touched tests: 0 errors; one pre-existing `TableMigration` experimental warning at database.dart:1119 (v40 block, not this plan).
- schema_v21_test and schema_v24_test assert `db.schemaVersion` dynamically, so left untouched.

## Deviations from Plan

**1. [Rule 3 - Blocking] test/fk_constraints_test.dart FK inventory**
- **Found during:** Task 2 (grep of `tdee_estimates`/`herculex_ai_program_briefs` registration points; confirmed by a failing run)
- **Issue:** The hard-coded FK edge inventory lacked the four new edges (goal_id x3, assessment_id), failing the edge-set and action-count tests.
- **Fix:** Added the four edges and updated counts to 32 CASCADE / 13 RESTRICT / 13 SET NULL / 1 NO ACTION = 59 edges.
- **Commit:** 73b498c

**2. [Tooling] `tool/codegen.ps1` not run directly** (no pwsh in Bash); ran its underlying `dart run build_runner build --delete-conflicting-outputs`. `schema dump` ran as a separate step as CLAUDE.md advises. `test/generated_migrations/schema.dart` was also regenerated (tracked, committed).

None otherwise. Nothing was applied to Supabase; applying remains Plan 17.

## Notes for downstream plans

- Local columns (snake_case) are exactly those in the SQL file; Plan 06 repository must enforce non-null `estimated_months`/`target_bf_percent` for `ai_analysis` and `manual` goals.
- CLAUDE.md "0015 and 0016 outstanding" note is stale (already applied remotely); not edited here.
- `database.g.dart` shows a huge whitespace/CRLF diff stat; use `git diff --ignore-all-space`.

## Known Stubs

None.

## Threat Flags

None beyond the plan's threat model (RLS 16 policies, no bytes column, relative path only; Plan 03 owns path-traversal rejection on read).

## Self-Check: PASSED

Files and commits fea9dc0, 73b498c, 73b6c3f verified present.
