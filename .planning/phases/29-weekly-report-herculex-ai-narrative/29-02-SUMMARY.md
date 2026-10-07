---
phase: 29-weekly-report-herculex-ai-narrative
plan: 02
subsystem: weekly-report
tags: [drift, schema-v48, sync, migration, gdpr]

requires: []
provides:
  - "WeeklyReports drift table (WeeklyReportData) with local unique key (iso_year, iso_week)"
  - "schemaVersion 48 with sqlite_master-guarded v47 -> v48 upgrade branch"
  - "weekly_reports registered in syncedTableNames, syncTableSpecs and _fullyClearedTables"
  - "drift_schema_v48.json, schema_v48.dart (DatabaseAtV48) and retargeted migration/schema tests"
affects: [29-05, 29-06, 29-07]

tech-stack:
  added: []
  patterns:
    - "Guarded createTable + IF NOT EXISTS sync_uuid index + installSyncTriggers (v45 idiom)"

key-files:
  created:
    - drift_schemas/drift_schema_v48.json
    - test/generated_migrations/schema_v48.dart
  modified:
    - lib/data/local/tables.dart
    - lib/data/local/database.dart
    - lib/data/local/database.g.dart
    - lib/data/local/migrations/sync_backfill.dart
    - lib/data/sync/sync_table_specs.dart
    - lib/data/local/local_data_wipe.dart
    - test/generated_migrations/schema.dart
    - test/migration_test.dart
    - test/schema_v25_test.dart
    - test/schema_v27_test.dart
    - test/schema_v28_test.dart
    - test/schema_v29_test.dart

key-decisions:
  - "Chores 1-4 of the five-chore schema bump done in one plan; only chore 5 (Supabase SQL) remains for plan 06"
  - "WeeklyReports ends with a column-0 closing brace so plan 06's column-parity regex can match it"
  - "Replay/index/trigger tests assert nothing about the (iso_year, iso_week) unique key, so plan 05's OQ3 fallback can drop it and regenerate artifacts without touching them"

patterns-established:
  - "Existing-table guard test: copy the v48 DDL from schemaAt(48).rawDatabase onto a schemaAt(47) database, then migrateAndValidate(db, 48)"

requirements-completed: []

duration: ~1h (about 10 min of it build_runner)
completed: 2026-10-03
---

# Phase 29 Plan 02: weekly_reports table and schema v48 Summary

**Local drift schema v47 -> v48 adds the `weekly_reports` table (immutable measured payload JSON, write-once narrative and TDEE decision, unique per ISO year/week), registered in all four sync/wipe registries, with dump, generated helper and retargeted migration tests.**

## Performance

- **Tasks:** 3/3
- **Files:** 14 (2 created, 12 modified)

## Accomplishments

- `WeeklyReports` table (`@DataClassName('WeeklyReportData')`, `SyncColumns` + `SyncTombstone`) with `isoYear`, `isoWeek`, `weekStartIso`, `generatedAt`, `payloadVersion`, `payloadJson`, `narrativeJson?`, `narrativeAttempts`, `knowledgeVersion?`, `modelVersion?`, `tdeeDecision?`, `tdeeDecisionKcal?`, `viewedAt?`; `uniqueKeys` = `{isoYear, isoWeek}`.
- `schemaVersion` 48; `from < 48` branch creates the table only if absent (sqlite_master), then `idx_sync_uuid_weekly_reports`, then `installSyncTriggers`.
- Fourth registry covered: `_fullyClearedTables` so account deletion erases the aggregated health data (T-29-05).
- `drift_schema_v48.json` differs from v47 only by the new `weekly_reports` table (verified structurally). `schema_v48.dart` and the `schema.dart` aggregator generated.
- `test/migration_test.dart`: all `migrateAndValidate` calls target 48; new v47 -> v48 replay (table, index, triggers) and a guard test that pre-creates the exact v48 table on a v47 fixture and confirms the upgrade does not throw. `schema_v25` retargeted (48 and `PRAGMA user_version`), `schema_v27/28/29` retargeted to `DatabaseAtV48`.

## Task Commits

1. Task 1 (table, upgrade branch, registries, codegen): `7434b08`
2. Task 2 (schema dump + generated helper): `e19194c`
3. Task 3 (retarget tests, v47 -> v48 replay): `297205e`

## Verification

- `flutter test` (full): 2334 passed, 9 skipped, 0 failed.
- `flutter analyze`: 0 errors (81 pre-existing warnings/info; the one in `lib/data` is the pre-existing `TableMigration` experimental use at `database.dart` v40 branch).
- `dart run tool/check_structure.dart`: 57 violations, unchanged baseline, none in touched files.

## Deviations from Plan

None to the plan's intent. Notes:

- `dart run drift_dev schema dump` printed a warning that drift could not run the database code and fell back to static analysis (the temp-script URI has a space in the project path, `AMS d.o.o`). The v47 -> v48 diff shows only the new table, so the output is complete.
- The plan's "existing fixture already has the table" assertion was implemented with `schemaAt(48).rawDatabase` DDL copied onto a v47 database so it genuinely exercises the sqlite_master guard.
- `dart format` reflowed one line of the new class; folded into the Task 3 commit.
- `build_runner` took about 10 minutes on this machine (1571 outputs rewritten); `database.g.dart` was briefly deleted by `--delete-conflicting-outputs` and regenerated.

## Hand-off for later plans

- Plan 05 OQ3 fallback (drop local unique key): re-run `dart run drift_dev schema dump lib/data/local/database.dart drift_schemas/` then `dart run drift_dev schema generate drift_schemas/ test/generated_migrations/`, then rerun `flutter test test/migration_test.dart test/schema_v2*_test.dart`.
- Plan 06 (chore 5): Supabase SQL column list in snake_case: `id`-less sync columns plus `iso_year, iso_week, week_start_iso, generated_at, payload_version, payload_json, narrative_json, narrative_attempts, knowledge_version, model_version, tdee_decision, tdee_decision_kcal, viewed_at`. No remote unique constraint on (iso_year, iso_week). Migration is NOT applied; sync of `weekly_reports` will quarantine (PGRST204) until it is, so do not ship a build with local v48 before it is pushed.

## Known Stubs

None.

## Threat Flags

None beyond the plan's threat model (T-29-05..08 addressed: wipe entry, all four registries, guarded upgrade, unique key accepted).

## Self-Check: PASSED

- Files present: drift_schemas/drift_schema_v48.json, test/generated_migrations/schema_v48.dart, WeeklyReports in tables.dart, WeeklyReportData in database.g.dart.
- Commits present: 7434b08, e19194c, 297205e.
