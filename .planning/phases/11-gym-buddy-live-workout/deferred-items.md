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

## From plan 11-04

- **`test/buddy/rls_frozen_test.dart` does not exist in this worktree.** Plan 11-04's own
  acceptance criteria (Tasks 1-3) call for `flutter test test/buddy/rls_frozen_test.dart` to
  pass as a secondary verification signal that `supabase/migrations/0003_sync_rls.sql` was left
  untouched. That test file is plan 11-02's deliverable (wave 1, `test/buddy/rls_frozen_test.dart`
  — a sha256 pin of `0003_sync_rls.sql`'s bytes), and 11-02's artifacts are not present in this
  worktree/branch at the time 11-04 executed, even though 11-02 is nominally an earlier wave.
  Not fixed here: creating that file is explicitly out of scope for 11-04
  (`files_modified: [supabase/migrations/0011_buddy_sessions.sql]` only), and it carries a
  specific pinned hash and several sibling artifacts (`buddy_event.dart`, `buddy_scope.dart`,
  `buddy_event_publisher.dart`, `test/support/two_device.dart`,
  `test/buddy/fake_buddy_publisher.dart`, `test/buddy/buddy_scope_boundary_test.dart`) that belong
  entirely to 11-02. Substituting my own version here risks conflicting with 11-02's actual
  commit when it lands. 11-04's own automated frozen-policy scan (Task 3's `bash -c` loop over
  every `0003_sync_rls.sql` table name) independently proves the same claim the Dart test would
  have proven, and it passed. Whoever merges this wave should confirm 11-02 has landed (or lands
  before 11-05) so the Dart-level gate is exercised at least once before the migration is pushed
  to the live project.

**Note (resolved by orchestrator during wave-1 merge):** 11-02 landed in the same wave and is
present on `master` as of this merge, alongside 11-04. The Dart-level gate
(`flutter test test/buddy/rls_frozen_test.dart`) can now be run before 11-05 pushes the
migration to the live project.
