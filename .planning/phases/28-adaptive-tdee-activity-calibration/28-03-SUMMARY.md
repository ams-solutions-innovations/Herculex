---
phase: 28-adaptive-tdee-activity-calibration
plan: 03
subsystem: database
tags: [drift, schema-migration, sync, outbox, tdee]

requires:
  - phase: 28-adaptive-tdee-activity-calibration
    provides: "TdeeEstimateResult domain types (28-01) and MacroTargets split (28-02)"
provides:
  - "TdeeEstimates drift table (v45), synced, with a domain estimatedAt separate from updated_at"
  - "v44 to v45 onUpgrade branch: guarded createTable, sync_uuid unique index, outbox triggers"
  - "Registration in syncedTableNames and syncTableSpecs (estimated_at as dateTimeColumn)"
  - "drift_schema_v45.json and generated schema_v45.dart fixtures"
  - "tdee_sync_registration_test guarding against half-registered sync"
affects: [28-05 supabase migration, 28-06 repository, 29 weekly report, 25 sync hardening]

tech-stack:
  added: []
  patterns:
    - "New synced table = table + @DriftDatabase list + syncedTableNames + syncTableSpecs + onUpgrade (createTable guard, unique index, installSyncTriggers)"

key-files:
  created:
    - drift_schemas/drift_schema_v45.json
    - test/generated_migrations/schema_v45.dart
    - test/tdee_sync_registration_test.dart
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
  - "estimatedAt is a domain DateTimeColumn distinct from the sync-owned updated_at, so same-day estimates order deterministically (resolves D-11 timestamp conflict)"
  - "createTable in the v45 branch is guarded by a sqlite_master check because fixtures sit on both sides of a step"
  - "No index on date_iso; roughly one row per recalibration does not need it"

patterns-established:
  - "Sync registration guard test: registry membership + unique index + insert enqueues a pending_sync_ops upsert"

requirements-completed: [TDEE-05]

duration: ~60min (dominated by a 256s build_runner run and a hung drift_dev process)
completed: 2026-09-28
---

# Phase 28 Plan 03: TdeeEstimates Table and v45 Schema Bump Summary

**Synced `tdee_estimates` drift table (schema v44 to v45) with guarded upgrade branch, sync_uuid index, outbox triggers and generated fixtures; the Supabase SQL remains for plan 05.**

## Performance

- **Tasks:** 3/3
- **Files:** 3 created, 11 modified

## Accomplishments

- `TdeeEstimates` table with the exact column set from the plan interfaces block, placed after `JointPainLogs`, with a doc comment explaining why it syncs (Phase 29 diffs history, must survive reinstall) while `HealthSamples` does not.
- `from < 45 && to >= 45` onUpgrade branch creates the table only when absent, adds `idx_sync_uuid_tdee_estimates` and calls `installSyncTriggers`, so upgraded installs enqueue outbox rows the same as fresh ones.
- Registered in `syncedTableNames` and `syncTableSpecs`; drift codegen regenerated `database.g.dart` (`TdeeEstimateData`, `TdeeEstimatesCompanion`).
- Schema dump, generated fixtures, migration_test retargeted to 45 with a new v44 to v45 replay that asserts columns, unique index and an outbox trigger on `tdee_estimates`.
- The four `schema_v25/27/28/29` tests retargeted from stale v39 to v45 and are green.

## Task Commits

1. **Task 1: Table, v45 branch, sync registrations** - `a8c7ef8` (feat)
2. **Task 2: Schema dump/generate, migration_test retarget + v44 to v45 replay** - `cdc0b7f` (test)
3. **Task 3: schema_v2x retarget, sync-registration guard** - `a87fec5` (test)

## Baseline (recorded before any edit)

Run of `schema_v25/27/28/29_test.dart` and `migration_test.dart`: 17 passed, 7 failed.

| File | Before | After |
| ---- | ------ | ----- |
| test/schema_v25_test.dart | 4 failing (all 4 tests) | passing |
| test/schema_v27_test.dart | 1 failing | passing |
| test/schema_v28_test.dart | 1 failing | passing |
| test/schema_v29_test.dart | 1 failing | passing |
| test/migration_test.dart | passing (17) | passing (18) |

All seven failures were the stale hardcoded v39 target (schemaVersion was already 44), so all four files were retargeted; none had an unrelated failure.

## Verification

- Full `flutter test`: **1443 passed, 9 skipped, 0 failed** (exit 0).
- `flutter analyze`: 0 errors (42 pre-existing warnings/infos; `lib/data` shows only the known `TableMigration` experimental_member_use warning).
- `dart run tool/check_structure.dart`: 58 violations, all pre-existing oversize/layout entries; the only one in files this plan touched is `database.dart` (already over 600 lines before this plan, now 1246). No new violation category introduced.
- `migrateAndValidate(db, 44)` count in migration_test is 0; `migrateAndValidate(db, 45)` count is 18.

## Deviations from Plan

### Minor

**1. `migrateAndValidate(db, 45)` count is 18, not "at least 20"**
- The plan's estimate of "about 20" was approximate; the file had 17 call sites plus the one new v44 to v45 test gives 18. Every call was retargeted; none remain at 44.

**2. `drift_dev schema dump` process does not exit**
- The dump writes `drift_schema_v45.json` correctly but the process hangs afterwards (an identical stale hung process from 2026-09-26 was also present). I killed only my own process (PID 80956 and its child) and ran `schema generate` separately, which completed normally. No functional impact; note for future schema bumps that the dump can be interrupted once the JSON exists.

No Rule 1-4 auto-fixes were needed. The `sqlite_master` createTable guard specified by the plan was kept; no fixture actually triggered the "table already exists" case, so the guard is defensive only.

## Issues Encountered

None beyond the hung dump process above.

## Known Stubs

None.

## Threat Flags

None. `tdee_estimates` is the surface the plan's threat model already covers (T-28-08 to T-28-11). Note that the table is registered for sync locally but Postgres has no `tdee_estimates` yet: until plan 05 SQL is written and plan 11 applies it, pushing this table would hit PGRST204/404 and be quarantined by the outbox after 8 attempts. CLAUDE.md already records that migrations `0015`/`0016` are outstanding; this makes plan 05 and 11 mandatory before shipping a build carrying local v45.

## Next Phase Readiness

- Plan 05 (Supabase SQL) can use the exact Postgres column list from the plan interfaces block.
- Plan 06 (repository) can use `TdeeEstimateData` / `TdeeEstimatesCompanion` from `database.g.dart`.

## Self-Check: PASSED

- Files present: tdee_sync_registration_test.dart, drift_schema_v45.json, schema_v45.dart, 28-03-SUMMARY.md.
- Commits present: a8c7ef8, cdc0b7f, a87fec5.
