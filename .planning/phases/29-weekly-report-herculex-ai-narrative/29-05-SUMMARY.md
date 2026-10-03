---
phase: 29-weekly-report-herculex-ai-narrative
plan: 05
subsystem: weekly-report
tags: [sync, drift, schema-v48, oq3, gdpr, tests]

requires:
  - phase: 29-02
    provides: "weekly_reports table, v48 schema, registry entries"
provides:
  - "OQ3 settled by test: a duplicate (iso_year, iso_week) pull aborts the whole sync cycle when a local unique key exists"
  - "weekly_reports has NO unique key (local or remote); regenerated v48 drift code, schema dump and migration helper"
  - "Guard tests for sync registration (registry, spec, order, index, outbox) and local wipe"
affects: [29-06, 29-07]

key-files:
  created:
    - test/sync/weekly_reports_duplicate_pull_test.dart
    - test/features/weekly_report/weekly_report_sync_registration_test.dart
    - test/features/weekly_report/weekly_report_wipe_test.dart
  modified:
    - lib/data/local/tables.dart
    - lib/data/local/database.g.dart
    - drift_schemas/drift_schema_v48.json
    - test/generated_migrations/schema_v48.dart

key-decisions:
  - "OQ3 FALLBACK TAKEN: dropped the local unique key on (iso_year, iso_week)"
  - "Plan 06 repository must enforce one-per-week inside its insert transaction and read the earliest row by (generated_at, id)"

duration: ~1h30 (most of it build_runner / drift_dev on a slow machine)
completed: 2026-10-03
---

# Phase 29 Plan 05: Duplicate-week pull (OQ3) and sync/wipe guards Summary

**The duplicate-week pull test proved a local unique key on (iso_year, iso_week) would abort the entire sync cycle, so the key was dropped and v48 artifacts regenerated; sync registration and wipe of `weekly_reports` are now guarded by tests.**

## OQ3 evidence (branch chosen: FALLBACK, unique key dropped)

With the unique key present, the test (local row 2026/40; remote rows 2026/40 under another uuid, 2026/39, plus a `daily_summaries` row from a table later in `syncTableOrder`) failed on `pullAll()`:

`SqliteException(2067): UNIQUE constraint failed: weekly_reports.iso_year, weekly_reports.iso_week` thrown from `_applyPulledRow`.

Cause: `SyncService._pullTable` calls `_applyPulledRow` with no per-row catch and `pullAll` is `try/finally` only, so the exception escapes `pullAll`, the table cursor is never written (the same bad row is re-fetched every cycle, a permanent block), and all later tables in the order are skipped. That is the "abort for other rows / whole cycle" case in the decision rule, so the key was removed from `WeeklyReports`.

After the fallback the same test asserts: `pullAll` does not throw, both 2026/40 rows land locally (2), 2026/39 is applied, the later-table row is applied, and `sync.state.lastError` is null.

## Accomplishments

- `uniqueKeys` override removed from `WeeklyReports` (comment documents why); `build_runner` regenerated `database.g.dart`.
- `drift_schema_v48.json` re-dumped; structural diff against the previous v48 is exactly `unique_keys` removed from `weekly_reports`. `schema_v48.dart` regenerated (`schema.dart` unchanged).
- Registration test: `syncedTableNames`, `syncTableOrder`, `syncTableSpecsByName` (dateTimeColumns `generated_at`, `viewed_at`), `idx_sync_uuid_weekly_reports` on a fresh DB, insert enqueues exactly one `upsert` outbox row.
- Wipe test: `wipeAllLocalUserData` empties `weekly_reports` (GDPR Art. 9).

## Verification

- Plan verification set (`test/sync/`, `migration_test`, `schema_v25/27/28/29`, `test/features/weekly_report/`, `account_deletion_test`, `tdee_sync_registration_test`): 171 passed, 9 skipped. Plan-02 migration/schema tests passed unedited against the regenerated v48.
- Full `flutter test`: 2351 passed, 9 skipped, 0 failed.
- `flutter analyze`: 0 errors (45 pre-existing warnings/info).

## Task Commits

1. Task 1 (OQ3 test + unique-key fallback + regenerated artifacts): `1ee6296`
2. Task 2 (registration and wipe guard tests): `97180b1`

## Deviations from Plan

None to intent. Notes:

- `dart run drift_dev schema dump ... | tail` piped into `schema generate` hung after writing a valid JSON (the dump was verified by structural diff); I killed it and ran `schema generate` separately, which finished normally.
- Test fixture detail: remote `weekly_reports` rows must not carry a `created_at` key (the table has none), otherwise the pull INSERT fails for an unrelated reason; this is how remote rows will look given plan 06's SQL column list.

## Hand-off for plan 06 (important)

- Remote SQL: no unique constraint on (iso_year, iso_week) (unchanged). Table has no `created_at`.
- Repository must (a) check for an existing non-deleted row for the (iso_year, iso_week) inside its insert transaction and (b) when reading, choose deterministically: earliest by `generated_at`, then `id`. Cross-device duplicates now arrive as two rows and are tolerated, not rejected.
- Local schema v48 has not changed shape other than the dropped unique index; Supabase migration (chore 5) is still outstanding and unapplied.

## Known Stubs

None.

## Threat Flags

None. T-29-18 mitigated (fallback taken), T-29-19 and T-29-20 mitigated by the new guard tests, T-29-21 accepted.

## Self-Check: PASSED

- Files present: the three test files, regenerated v48 json and `schema_v48.dart`.
- Commits present: 1ee6296, 97180b1.
