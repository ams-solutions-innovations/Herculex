# Deferred Items — Phase 11 (gym-buddy-live-workout)

Out-of-scope discoveries logged during execution, per the executor's scope-boundary rule
(only auto-fix issues directly caused by the current task's own changes).

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
