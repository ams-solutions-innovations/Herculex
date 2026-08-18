# Deferred Items — Phase 11 (gym-buddy-live-workout)

Out-of-scope discoveries found during execution, logged per the executor's
scope-boundary rule rather than fixed inline.

## 11-02: 25 pre-existing test failures unrelated to buddy work

**Found during:** Task 3 full-suite regression run (`flutter test`).

**Symptom:** 25 tests fail, all with the same root cause:

```
SqliteException(1): while preparing statement, no such table: exercise_catalog, SQL logic error (code 1)
  Causing statement: SELECT * FROM "exercise_catalog";
```

**Affected files (none touched by 11-02):**
- `test/migration_test.dart` (v25 and v26 fixture upgrades)
- `test/schema_v21_test.dart`
- `test/schema_v24_test.dart`
- and ~21 more schema/migration/repository-delete-path/nutrition tests that
  transitively open a full `AppDatabase` and touch `exercise_catalog`

**Why out of scope for 11-02:** None of 11-02's changes touch
`lib/data/local/database.dart`, any migration file, or any fixture. 11-02
only adds pure-Dart files under `lib/features/buddy/` and new files under
`test/buddy/` and `test/support/two_device.dart` — none reference
`exercise_catalog` or any migration. `test/buddy/` and
`test/support/two_device.dart` are unaffected: `flutter test test/buddy/`
and the analyzer over the plan's own paths are both green.

**Not fixed per the executor's scope-boundary rule:** "Only auto-fix issues
directly caused by the current task's changes... do NOT re-run builds hoping
they resolve themselves." This looks like a generated-database-schema/fixture
drift issue (likely `database.g.dart` needing regeneration via
`build_runner`, or a stale migration fixture) predating this plan — worth a
dedicated look before the next phase that touches migrations, but not a
11-02 concern.
