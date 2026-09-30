---
phase: 27-herculex-ai-program-generation
plan: 04
subsystem: database
tags: [drift, sqlite, schema-migration, sync, supabase]

# Dependency graph
requires:
  - phase: 27-herculex-ai-program-generation
    provides: "27-03's ProgramBrief.toJson()/fromJson() shape (split, periodization, dayRoles-with-rationale, musclePriorities, phaseIntent) — the exact JSON this plan's briefJson column persists"
provides:
  - "Local drift schemaVersion 46 with HerculexAiProgramBriefs table (D-08), FK'd to Programs, registered for sync"
  - "drift_schema_v46.json + schema_v46.dart (DatabaseAtV46) fixtures for downstream plans"
  - "Every affected migration/schema-version test retargeted from v45 to v46, full suite green"
affects: [27-06, 27-09, 27-10, 27-12]

# Tech tracking
tech-stack:
  added: []
  patterns:
    - "Guarded onUpgrade branch (sqlite_master existence check before createTable, unique sync_uuid index, installSyncTriggers) — exact v45 TdeeEstimates template, now the v46 precedent for the next bump"

key-files:
  created:
    - drift_schemas/drift_schema_v46.json
    - test/generated_migrations/schema_v46.dart
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

key-decisions:
  - "HerculexAiProgramBriefs.programId is non-nullable (every brief belongs to exactly one program), unlike ExercisePreferences.programId which is nullable — per the plan's explicit instruction."
  - "Single briefJson blob + queryable metadata columns (programId, source, knowledgeVersion, modelVersion, confirmedAt, active), matching PhysiqueProgrammingProfiles' precedent exactly, per RESEARCH.md's Open Question 2 recommendation — no child table for per-day rationale."
  - "Chore 5 (Supabase migration) deliberately NOT done here — plan 27-10's job, sequenced after this plan. Local v46 would quarantine herculex_ai_program_briefs rows on push (PGRST204) until that migration lands and applies, same situation Phase 28's TdeeEstimates was in between its own plans 05 and 11."

requirements-completed: []  # AIP-04 intentionally left unchecked — see REQUIREMENTS.md annotation; this plan only builds the persistence target, not the brief generation or review-gate rendering.

# Metrics
duration: ~25min
completed: 2026-09-30
---

# Phase 27 Plan 04: HerculexAiProgramBriefs Schema Bump (v46) Summary

**Local drift schemaVersion 45 -> 46 adding HerculexAiProgramBriefs (programId FK to Programs, briefJson blob, source/knowledgeVersion/modelVersion provenance), completing CLAUDE.md's schema-bump chores 1-4 with every migration test retargeted and green.**

## Performance

- **Duration:** ~25 min
- **Completed:** 2026-09-30
- **Tasks:** 2/2 completed
- **Files modified:** 11 (2 new: drift_schema_v46.json, schema_v46.dart)

## Accomplishments
- `HerculexAiProgramBriefs` table declared in `lib/data/local/tables.dart`, modeled exactly on `PhysiqueProgrammingProfiles` per D-08, with a non-nullable `programId` FK (`onDelete: KeyAction.cascade`) per the plan's explicit deviation from the nullable `ExercisePreferences.programId` precedent.
- `schemaVersion` bumped 45 -> 46 with a new guarded `onUpgrade` branch (`if (from < 46 && to >= 46)`), byte-for-byte matching the v45 `TdeeEstimates` block's shape: `sqlite_master` existence guard, `m.createTable`, unique `idx_sync_uuid_herculex_ai_program_briefs` index, `installSyncTriggers`.
- Sync registration complete: `herculex_ai_program_briefs` added to `syncedTableNames` (positioned after `programs`/`exercise_preferences`) and to `sync_table_specs.dart` as a `SyncTableSpec` with `dateTimeColumns: ['confirmed_at']` and a `SimpleFk(localColumn: 'program_id', parentTable: 'programs')`.
- `dart run build_runner build --delete-conflicting-outputs` regenerated `database.g.dart` (874 outputs total) so the new table's generated companion/data classes exist.
- `dart run drift_dev schema dump` / `schema generate` produced `drift_schemas/drift_schema_v46.json` and `test/generated_migrations/schema_v46.dart` (`DatabaseAtV46`), with `schema.dart`'s `GeneratedHelper` wired for `case 46`.
- Every v45-referencing test retargeted to v46: `test/migration_test.dart` (18 `migrateAndValidate` call sites plus a new v45->v46 replay test asserting the new table's column set, sync_uuid index, and outbox triggers), `test/schema_v25_test.dart` (migrateAndValidate + hardcoded `PRAGMA user_version` assertion), `test/schema_v27/28/29_test.dart` (import alias, `newVersion:`, `createNew:` factory reference). `test/schema_v21_test.dart`/`schema_v24_test.dart` left untouched per the plan's confirmation that they assert against `db.schemaVersion` dynamically.

## Task Commits

Each task was committed atomically:

1. **Task 1: HerculexAiProgramBriefs table, schemaVersion 46, onUpgrade, sync registration** - `adaa942` (feat)
2. **Task 2: Regenerate drift schema snapshot/fixtures and retarget every v45-referencing test to v46** - `e2d6baa` (test)

## Files Created/Modified
- `lib/data/local/tables.dart` - New `HerculexAiProgramBriefs` table (`@DataClassName('HerculexAiProgramBriefData')`), doc comment explaining the D-08/D-09 shape and the non-nullable `programId` divergence from `ExercisePreferences`.
- `lib/data/local/database.dart` - `schemaVersion` 45 -> 46, `HerculexAiProgramBriefs` added to the `@DriftDatabase(tables: [...])` list, new v46 `onUpgrade` branch.
- `lib/data/local/database.g.dart` - Regenerated via `build_runner` (drift codegen for the new table).
- `lib/data/local/migrations/sync_backfill.dart` - `'herculex_ai_program_briefs'` appended to `syncedTableNames`.
- `lib/data/sync/sync_table_specs.dart` - New `SyncTableSpec('herculex_ai_program_briefs', ...)` with `SimpleFk` to `programs`, positioned in Level 1 (after `programs`/`exercise_preferences`).
- `drift_schemas/drift_schema_v46.json` - New drift schema dump snapshot.
- `test/generated_migrations/schema_v46.dart` - New `DatabaseAtV46` fixture.
- `test/generated_migrations/schema.dart` - `GeneratedHelper` extended for schema version 46.
- `test/migration_test.dart` - All `migrateAndValidate` targets retargeted to 46; new v45->v46 replay test.
- `test/schema_v25_test.dart`, `test/schema_v27_test.dart`, `test/schema_v28_test.dart`, `test/schema_v29_test.dart` - Retargeted to v46 per each file's own retarget convention.

## HerculexAiProgramBriefs Column List (snake_case)

For plan 27-10's Supabase migration and column-parity test to match exactly (drift's `SyncColumns`/`SyncTombstone` mixins contribute the sync-only columns):

| Column | Type | Notes |
|---|---|---|
| `id` | integer, PK, autoincrement | local-only, not synced (standard drift PK pattern) |
| `program_id` | integer, FK -> `programs(id)` ON DELETE CASCADE | non-nullable |
| `brief_json` | text, not null | full brief: split, periodization, dayRoles-with-rationale, musclePriorities, phaseIntent |
| `source` | text, not null, default `'herculex_ai'` | |
| `knowledge_version` | text, nullable | |
| `model_version` | text, nullable | |
| `confirmed_at` | datetime, not null, default `currentDateAndTime` | dateTimeColumn for sync purposes |
| `active` | boolean, not null, default `true` | |
| `sync_uuid` | text, unique | from `SyncColumns` |
| `updated_at` | datetime | from `SyncColumns` |
| `deleted_at` | datetime, nullable | from `SyncTombstone` |

`SyncTableSpec` registration: `fkFields: [SimpleFk(localColumn: 'program_id', parentTable: 'programs')]`, `dateTimeColumns: ['confirmed_at']`.

## Decisions Made
- `programId` is non-nullable (every brief belongs to exactly one program) — the plan's explicit instruction, diverging from the nullable `ExercisePreferences.programId` FK precedent it otherwise mirrors.
- Single `briefJson` text blob rather than a child table for per-day rationale, matching `PhysiqueProgrammingProfiles`' `prioritiesJson` precedent and RESEARCH.md's Open Question 2 recommendation (low cardinality, ~7 entries max per program).
- Chore 5 (the matching `supabase/migrations/NNNN_*.sql`) intentionally deferred to plan 27-10, per the plan's own objective statement — this plan only completes chores 1-4.

## Deviations from Plan

None - plan executed exactly as written. `test/generated_migrations/schema.dart` was not explicitly named in the plan's `files_modified` list but is a mechanical side effect of `drift_dev schema generate` (adds `case 46` to `GeneratedHelper`) — not a deviation, just an artifact the plan's own action step implies.

## Issues Encountered
- `dart run drift_dev schema dump` hung after writing `drift_schemas/drift_schema_v46.json` to disk, exactly as CLAUDE.md's documented gotcha and the plan's own note predicted. Confirmed the file was fully written (169640 bytes) via `ls -la`, then killed the process (`kill -9`) and proceeded to `schema generate` as a separate step, per the prescribed workaround.
- `pwsh` (PowerShell Core) is not available in this Bash/Git-Bash environment, so `tool/codegen.ps1` could not be invoked directly. Read the script and ran its underlying command directly instead: `dart run build_runner build --delete-conflicting-outputs`. Same effect, no functional difference.

## User Setup Required

None - no external service configuration required. Local schema is now v46; Supabase-side sync for this table remains inactive until plan 27-10's migration is written and applied (documented in this plan's objective as an intentional sequencing choice, not a gap).

## Next Phase Readiness
- `HerculexAiProgramBriefs` is ready for plan 27-09 (the brief service) to write to, and for plan 27-10 to add the matching Supabase migration against.
- The exact snake_case column list above is recorded so plan 27-10's column-parity test can assert against it without re-deriving it from the Dart table.
- Full local migration/schema-version test suite (`migration_test.dart`, `schema_v21/24/25/27/28/29_test.dart`) is green — 43/43 passing. `flutter analyze` reports 0 errors on every touched file (one pre-existing, out-of-scope warning on `database.dart:1114`'s unrelated `TableMigration` experimental-API use, predating this plan).

## Self-Check: PASSED

All claimed files exist on disk (`drift_schemas/drift_schema_v46.json`, `test/generated_migrations/schema_v46.dart`, `lib/data/local/tables.dart`, `lib/data/local/database.dart`) and both task commits (`adaa942`, `e2d6baa`) are present in `git log`.

---
*Phase: 27-herculex-ai-program-generation*
*Completed: 2026-09-30*
