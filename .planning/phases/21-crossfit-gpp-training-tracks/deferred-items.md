# Deferred Items — Phase 21

Out-of-scope discoveries logged during plan execution. Not fixed per the
SCOPE BOUNDARY rule (pre-existing issues unrelated to the current task's
changes).

## Stale hardcoded schema-version targets in `test/schema_v2*.dart`

**Found during:** 21-01, Task 2 (schemaVersion 43 -> 44 bump), while running
the full `flutter test` suite for extra verification beyond the plan's
required `test/migration_test.dart` check.

**Files affected (confirmed pre-existing, predates this plan):**
- `test/schema_v25_test.dart` — hardcodes `migrateAndValidate(db, 39)` and
  `expect(row.data.values.first, 39)` against `PRAGMA user_version`.
- `test/schema_v27_test.dart` — hardcodes `newVersion: 39`, `createNew:
  v39.DatabaseAtV39.new`.
- `test/schema_v28_test.dart` — same pattern, hardcoded to v39.
- `test/schema_v29_test.dart` — same pattern, hardcoded to v39.

**Root cause:** CLAUDE.md's five-chores checklist says step 4 is "Retarget
the tests: `test/migration_test.dart` ... and `test/schema_v2*.dart`
(`newVersion:`, `DatabaseAtVNN`, and one hardcoded `PRAGMA user_version`)" on
every schemaVersion bump. These four files were last retargeted at the v39
bump and never updated through v40, v41, v42, or v43 — so they were already
failing against `AppDatabase.schemaVersion => 43` before this plan (21-01)
touched anything. Verified via `git show HEAD~3:test/schema_v25_test.dart`
and `git show HEAD~3:test/schema_v27_test.dart` (i.e. the state immediately
before this plan's first commit): both already hardcoded `39`.

**Why not fixed here:** Not caused by this plan's changes (SCOPE BOUNDARY:
"Only auto-fix issues DIRECTLY caused by the current task's changes.
Pre-existing warnings, linting errors, or failures in unrelated files are
out of scope"). `21-01`'s own `<verification>` block only requires
`flutter test test/migration_test.dart` and `flutter analyze`, both of which
pass cleanly (0 analyzer errors; all 17 migration_test.dart cases green,
including the new v43->v44 replay).

**Recommended fix (future plan/chore):** Retarget all four files' hardcoded
`39` to the current `schemaVersion` (now 44), matching the pattern already
used correctly in `test/migration_test.dart` and `test/schema_v26_test.dart`.
This is pure test-target churn, no production code changes, and should be
folded into whichever future plan next touches the schema-bump checklist, or
done as a standalone chore.
