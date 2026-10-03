---
phase: 29-weekly-report-herculex-ai-narrative
plan: 06
subsystem: weekly-report
tags: [supabase, rls, schema-v48, chore-5, repository, drift, tdd]

requires:
  - phase: 29-weekly-report-herculex-ai-narrative
    provides: "WeeklyReports table at schema v48 (29-02), no-unique-key decision (29-05), IsoWeek (29-01)"
provides:
  - "supabase/migrations/20261003000000_weekly_reports_v48.sql: remote half of local v48 (WRITTEN, NOT applied)"
  - "test/weekly_reports_supabase_migration_test.dart: column parity derived from the drift class, comment-stripped negative assertions"
  - "WeeklyReportRepository + WeeklyReportRecord: sole writer of weekly_reports; immutable payload, write-once narrative and TDEE decision"
affects: [29-15, 29-20]

tech-stack:
  added: []
  patterns:
    - "Comment-stripped SQL helper (strip `--` per line on raw text, then lowercase and collapse) for negative assertions"
    - "App-level one-row-per-key enforcement in a transaction when the table has no unique key; reads pick earliest by (generatedAt, id)"

key-files:
  created:
    - supabase/migrations/20261003000000_weekly_reports_v48.sql
    - test/weekly_reports_supabase_migration_test.dart
    - lib/features/weekly_report/data/weekly_report_repository.dart
    - test/features/weekly_report/weekly_report_repository_test.dart
  modified:
    - docs/supabase-migrations.md

key-decisions:
  - "Followed 29-05 over the plan text: no unique key anywhere (local or remote); one-report-per-week is enforced inside insertSnapshot's transaction and reads take the earliest live row by (generated_at, id)"
  - "Mutators (saveNarrative, recordTdeeDecision, incrementNarrativeAttempts, markViewed) target the earliest live row by id, so a duplicate pulled from another device is never written to"
  - "Soft-deleted-only week: insertSnapshot hard-deletes the tombstoned rows and inserts fresh; a live row is never rewritten"
  - "incrementNarrativeAttempts returns 0 when the week has no live row"

patterns-established:
  - "WeeklyReportRecord carries raw JSON strings; decoding stays in callers behind try/catch"

requirements-completed: []
requirements-partial: [RPT-01, RPT-04]

duration: ~1h (interrupted once by a session rate limit)
completed: 2026-10-03
---

# Phase 29 Plan 06: weekly_reports Supabase migration and repository Summary

**Chore 5 of the v48 schema bump is written (owner-only RLS table, triggers, realtime, pull index, deliberately no unique constraint) with a drift-derived parity test, and `WeeklyReportRepository` is the single writer of an immutable, one-per-week, write-once snapshot row.**

## What was built

- `20261003000000_weekly_reports_v48.sql`: `create table weekly_reports` with the local columns snake_cased plus `user_id` (no `sync_uuid`, `synced_at` or `created_at`), RLS enabled with four `_own` policies, `t_set_updated_at_weekly_reports`, `t_record_tombstone_weekly_reports`, realtime publication and the `(user_id, updated_at, id)` index. Header states the PGRST204 mechanism, ordering after 0015, 0016 and the v45, v46, v47 files, written-not-applied (plan 20), project ref `ldzgyzigvbwofbswitrv` and why there is no unique constraint.
- `weekly_reports_supabase_migration_test.dart`: clone of the tdee test retargeted. The parity test regex-extracts `class WeeklyReports extends Table`, skips the `uniqueKeys` getter, and requires every snake_cased column in the SQL. `readExecutableSql()` strips `--` comments per line on the raw file before lowercasing, guards against an empty result, and is used for the `constraint`, `check (`, `unique` and policy-count assertions.
- `docs/supabase-migrations.md`: row marked "WRITTEN, NOT applied".
- `WeeklyReportRepository(AppDatabase, Clock)`: `insertSnapshot` (transactional get-or-create), `forWeek`, `watchWeek`, `watchHistory`, `incrementNarrativeAttempts`, `saveNarrative`, `recordTdeeDecision`, `markViewed`. `payloadJson: Value(...)` appears once, in `insertSnapshot`; there is no other payload writer.

## Task commits

| Task | Commit | Description |
| ---- | ------ | ----------- |
| 1 | 702ffcb | Supabase migration, parity test, docs row |
| 2 RED | 70e77d3 | failing repository test (26 cases) |
| 2 GREEN | 7a17738 | WeeklyReportRepository |

## Verification

- `flutter test test/weekly_reports_supabase_migration_test.dart test/features/weekly_report/weekly_report_repository_test.dart`: 26 passed (6 migration + 20 repository).
- `flutter analyze lib/features/weekly_report test/features/weekly_report test/weekly_reports_supabase_migration_test.dart`: no issues.
- `dart run tool/check_structure.dart`: no line mentions weekly_report.
- Acceptance greps: no non-comment `unique` in the SQL, exactly 4 `policy` lines, `jioesomepkauponjrena` only in the "different product" comment, `payloadJson: Value` count 1, `DateTime.now` count 0, no relative imports, `isNull()` write-once guards present.
- Full `flutter test` suite not re-run (new files are additive; no shared file changed beyond a docs row).

## Deviations from Plan

### Followed the prior summary over the plan text

**1. [Plan 29-05 hand-off] No unique key; repository enforces one-per-week**
- The plan's wording assumes one row per week is guaranteed; 29-05 dropped the local unique key. `insertSnapshot` therefore checks for a live row inside its transaction, and every read and mutator takes the earliest live row by `(generatedAt, id)`. The SQL has no unique constraint and no `created_at`, as 29-05 directed.

### Auto-fixed

**2. [Rule 3 - Blocking] `isNull` name clash in the test**
- Importing all of `package:drift/drift.dart` collided with the matcher `isNull`. The test imports `show Value` only. Folded into the RED commit.

### Notes

- Drift stores `DateTime` at second resolution, so tests that need ordering use distinct seconds, plus one test for the id tiebreak.
- The migration was NOT applied. CLAUDE.md still lists 0015 and 0016 as outstanding, but the STATE log records them applied remotely (27-10 note); the header keeps the conservative ordering text.

## Known Stubs

None.

## Threat Flags

None beyond the plan's register. T-29-22 and T-29-23 (no payload writer, write-once guards, tested), T-29-24 (4 policies asserted), T-29-25 (parity test), T-29-26 (raw strings, no decode in repository) and T-29-27 (file written only) are mitigated.

## Hand-off

- Plan 15 wires the repository provider; none created here.
- Plan 20 applies the migration (human-gated). Do not ship a build with local v48 before that.
- RPT-01 and RPT-04 stay unchecked in REQUIREMENTS.md (partial-completion convention).

## Self-Check: PASSED

- Files present: the SQL, both test files, the repository, the docs row.
- Commits present: 702ffcb, 70e77d3, 7a17738.
