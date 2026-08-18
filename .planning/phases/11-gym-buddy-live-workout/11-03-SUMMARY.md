---
phase: 11-gym-buddy-live-workout
plan: 03
subsystem: database
tags: [drift, sqlite, migration, schema, sync]

# Dependency graph
requires:
  - phase: 10-assisted-rep-tracking
    provides: "the v26 local-only-table precedent (RepTrackingSettings et al.) this plan's BuddySessionsLocal/BuddyChoreographySlots follow exactly, and the schemaVersion=28/from<28&&to>=28 addColumn idiom this plan's v29 blocks mirror"
provides:
  - "Drift schema v29: BuddySessionsLocal and BuddyChoreographySlots (local-only mirror tables, no outbox trigger) plus WorkoutSessions.buddySessionId (nullable synced column)"
  - "Regenerated drift_schemas/drift_schema_v29.json and test/generated_migrations/schema_v29.dart fixtures"
  - "migration_test.dart repointed to v29 with a new startAt(28) replay; test/schema_v29_test.dart data-integrity test"
  - "Positive proof (sqlite_master query) that the two buddy tables carry no outbox trigger and are absent from both sync lists"
  - "Proof that buddySessionId round-trips through SyncService's generic push/pull payload derivation"
affects: [11-04, 11-05, 11-06, 11-07, 11-08, 11-09, 11-10, 11-11]

# Tech tracking
tech-stack:
  added: []
  patterns:
    - "Local-only Drift table: no SyncColumns/SyncTombstone mixin, absent from syncedTableNames and syncTableSpecs, proven via sqlite_master trigger query rather than source grep (v26 rep-tracking precedent, now also v29 buddy)"
    - "Nullable synced column on an existing table needs no SyncTableSpec entry — SyncService._buildRemotePayload derives it generically from any local column not already consumed by a rename/FK/dateTime rule"

key-files:
  created:
    - drift_schemas/drift_schema_v29.json
    - test/generated_migrations/schema_v29.dart
    - test/schema_v29_test.dart
    - test/buddy/buddy_local_only_test.dart
  modified:
    - lib/data/local/tables.dart
    - lib/data/local/database.dart
    - lib/data/local/database.g.dart
    - test/migration_test.dart
    - test/sync/sync_payload_test.dart
    - test/fk_constraints_test.dart

key-decisions:
  - "buddySessionId inserted directly via WorkoutSessionsCompanion.insert in the round-trip test rather than insert-then-update — functionally equivalent to the plan's 'start a session, set its buddySessionId' and avoids an unnecessary extra write path in the test."
  - "schema_v29_test.dart's createItems inserts a workout_sessions row (not gyms) as the primary canary per the plan's explicit instruction, plus keeps the gyms canary for the untouched-table proof; validateItems also confirms both new tables exist and are empty (no backfill) rather than only checking column presence."

requirements-completed: [BUD-02, BUD-04]

# Metrics
duration: 35min
completed: 2026-08-18
---

# Phase 11 Plan 03: Gym Buddy Drift Schema v28 -> v29 Summary

**Local Drift schema v29 adds two local-only Gym Buddy mirror tables (BuddySessionsLocal, BuddyChoreographySlots) and a nullable synced `WorkoutSessions.buddySessionId`, with every generated schema artifact, migration test, and local-only/round-trip proof updated to match.**

## Performance

- **Duration:** ~35 min
- **Started:** 2026-08-18T15:17:00+02:00 (worktree setup) / 2026-08-18T15:45:00+02:00 (implementation start)
- **Completed:** 2026-08-18T16:16:00+02:00
- **Tasks:** 3/3
- **Files modified:** 9 (3 created, 6 modified — plus 1 test file fixed as a Rule 1/3 deviation)

## Accomplishments
- Declared `BuddySessionsLocal` and `BuddyChoreographySlots` exactly per the plan's `<interfaces>` block — neither mixes in `SyncColumns`/`SyncTombstone`, and `WorkoutSessions.buddySessionId` is the only change to a synced table.
- Bumped `schemaVersion` 28 -> 29 with a `from < 29` createTable block and a `from < 29 && to >= 29` addColumn block (mirroring the v26/v28 idioms and their `to >=` guard reasoning), then regenerated `database.g.dart` via `build_runner`.
- Regenerated `drift_schemas/drift_schema_v29.json` and `test/generated_migrations/schema_v29.dart` via the two `drift_dev schema` commands, repointed all six pre-existing `migrateAndValidate(db, 28)` call sites in `migration_test.dart` to 29, and added a new `startAt(28)` replay.
- Wrote `test/schema_v29_test.dart` (`testWithDataIntegrity`): a pre-existing `workout_sessions` row survives the migration with `buddy_session_id` reading NULL, `gyms` stays untouched, and both new tables exist but are empty (no backfill).
- Wrote `test/buddy/buddy_local_only_test.dart`, a direct clone of `test/rep_local_only_test.dart`: a `sqlite_master` trigger query (with an `isNotEmpty` guard so it can't pass vacuously) proves neither buddy table has an outbox trigger, both are absent from `syncedTableNames` and `syncTableOrder`, and `buddy_sessions_local` carries none of `sync_uuid`/`updated_at`/`deleted_at`.
- Extended `test/sync/sync_payload_test.dart` with a test named exactly `buddy_session_id`: pushes a session with `buddySessionId` set, asserts the remote payload carries `buddy_session_id` (proving `SyncService._buildRemotePayload`'s generic pass-through needs no `SyncTableSpec` entry — research assumption A8), and asserts the value round-trips onto a second device on pull.

## Task Commits

Each task was committed atomically:

1. **Task 1: Declare the tables and the v29 migration block** - `61ab365` (feat)
2. **Task 2: Regenerate the schema artifacts and extend the migration tests** - `bdd41d0` (test)
3. **Task 3: Prove the buddy mirror tables are local-only and buddy_session_id round-trips** - `e99cf57` (test)

_Note: worktree mode — no separate plan-metadata commit; this SUMMARY.md is committed directly by the executor per the wave's shared-file exclusion._

## Files Created/Modified
- `lib/data/local/tables.dart` - Added `BuddySessionsLocal`, `BuddyChoreographySlots`, and `WorkoutSessions.buddySessionId`
- `lib/data/local/database.dart` - Registered the two new tables, bumped `schemaVersion` to 29, added the `from < 29` and `from < 29 && to >= 29` migration blocks
- `lib/data/local/database.g.dart` - Regenerated via `build_runner`
- `drift_schemas/drift_schema_v29.json` - Generated v29 schema snapshot
- `test/generated_migrations/schema_v29.dart` - Generated v29 migration fixture (and `schema.dart` now registers v29)
- `test/migration_test.dart` - Repointed to v29, added `startAt(28)` replay
- `test/schema_v29_test.dart` - New v28 -> v29 data-integrity test
- `test/buddy/buddy_local_only_test.dart` - New positive local-only proof for the two buddy tables
- `test/sync/sync_payload_test.dart` - New `buddy_session_id` push/pull round-trip test
- `test/fk_constraints_test.dart` - Updated the hard-coded FK inventory for the two new CASCADE edges (deviation, see below)

## Decisions Made
- Inserted `buddySessionId` directly on `WorkoutSessionsCompanion.insert` in the round-trip test rather than insert-then-update; functionally equivalent to the plan's "start a session, set its buddySessionId" and simpler.
- `schema_v29_test.dart`'s data-integrity `createItems` inserts a `workout_sessions` row as the primary canary (per the plan's explicit instruction) while retaining the `gyms` canary from the v28 precedent for the untouched-table proof.

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 1/3 - Bug/Blocking] Updated `test/fk_constraints_test.dart`'s hard-coded FK inventory**
- **Found during:** Task 3 (running the full offline suite to check for regressions)
- **Issue:** `test/fk_constraints_test.dart`'s "declared foreign key inventory matches exactly" test hard-codes every FK edge in the schema (36 edges: 18 CASCADE + 10 RESTRICT + 8 SET NULL) and fails loudly on any addition — this plan's two new CASCADE edges (`buddy_sessions_local.workout_session_id -> workout_sessions.id`, `buddy_choreography_slots.workout_exercise_id -> workout_exercises.id`) were not yet in the list, so the test failed with an edge-count mismatch (38 actual vs 36 expected).
- **Fix:** Added both new edges to `_expectedEdges` and updated the count assertion from 18/10/8 to 20/10/8 CASCADE/RESTRICT/SET NULL and the doc comment.
- **Files modified:** `test/fk_constraints_test.dart`
- **Verification:** `flutter test test/fk_constraints_test.dart` — all 4 tests pass.
- **Committed in:** `e99cf57` (Task 3 commit)

---

**Total deviations:** 1 auto-fixed (Rule 1/3 — a hard-coded FK inventory test needed updating as a direct, mechanical consequence of this plan's new FK columns)
**Impact on plan:** No scope creep — the fix is exactly the maintenance the test's own doc comment calls for ("Any future `tables.dart` edit that adds... an edge must update this list deliberately — that is the point of the test").

## Issues Encountered

**Pre-existing, out-of-scope test failures (not fixed, per explicit instruction).** The full offline suite (`flutter test`) shows 657 passed, 4 skipped, 25 failed. All 25 failures are the same pre-existing condition the sibling plan 11-02 (running earlier in this wave) already flagged: `ExerciseImporter`'s `beforeOpen` seed step conflicts with the `exercise_catalog` table shape in several older generated migration fixtures (v20/v21, v23/v24, v25, v26, v27), producing either "no such table: exercise_catalog" or "ON CONFLICT clause does not match any PRIMARY KEY or UNIQUE constraint" depending on which fixture version. Confirmed this is fully independent of this plan's schema/migration work by reproducing the identical failure on `test/schema_v26_test.dart` (a pure v25 -> v26 test with zero v29/buddy code in its execution path) and on `test/schema_v21_test.dart`/`schema_v24_test.dart`/`schema_v27_test.dart` (versions this plan never touches). Three additional widget-test load failures (`theme_tokens_test.dart`, `hx_nav_bar_test.dart`, `hx_screen_shell_test.dart`, `widget_test.dart`) are also part of this same pre-existing set and unrelated to database/schema code. Left unfixed per the explicit scope boundary for this task.

**Narrowly scoped verification confirms no regression:** `flutter test test/migration_test.dart test/schema_v29_test.dart test/buddy/ test/sync/sync_payload_test.dart` is green except the same two pre-existing failures (`startAt(25)`, `startAt(26)` in `migration_test.dart`). `git diff --stat lib/data/local/migrations/sync_backfill.dart lib/data/sync/sync_table_specs.dart` is empty — both files are byte-unchanged, confirming no accidental sync-list entry was added for the buddy tables or `buddySessionId`.

## User Setup Required

None - no external service configuration required. This plan is entirely local Drift schema/migration work with no live Supabase connection.

## Next Phase Readiness

- Schema v29 is in place; plans 11-07 (choreography applier) and 11-11 can read/write `BuddySessionsLocal`/`BuddyChoreographySlots` directly.
- `WorkoutSessions.buddySessionId` round-trips through push/pull, satisfying BUD-07's only dependency on this phase.
- No blockers. The pre-existing exercise_catalog fixture-seeding failures (25, unrelated to buddy work) remain open from before this plan and are tracked as a pre-existing condition, not a new blocker.

---
*Phase: 11-gym-buddy-live-workout*
*Completed: 2026-08-18*

## Self-Check: PASSED

All 10 files listed under "Files Created/Modified" (plus this SUMMARY.md) exist on disk, and all 3 task commits (`61ab365`, `bdd41d0`, `e99cf57`) are present in `git log --oneline`.
