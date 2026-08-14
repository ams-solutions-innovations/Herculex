# FK Enforcement Remediation — Progress Log

This file tracks execution of the phased plan in
[`C:\Users\marti\.claude\plans\according-to-the-docs-app-audit-report-2-humming-valiant.md`](../../../../.claude/plans/according-to-the-docs-app-audit-report-2-humming-valiant.md)
(RB-04 — Database Foreign Keys & Cascading Deletes). Each phase is being
implemented in its own chat session, so this log is the persistent memory
across sessions — **read the plan doc and this log fully before starting
work on any phase.**

Source audit: `docs/app-audit-report-2026-08-10.md:136-166`, "Database
Foreign Keys Are Disabled".

## How to use this doc (for whichever Claude session picks up next)

1. Read the plan doc in full — it has the authoritative per-phase design
   (files, approach, verification steps, and non-obvious facts about why
   `beforeOpen` is the only correct pragma location).
2. Read the "Status" table below to see what's done.
3. Read the phase's own log entry for exact deviations from the plan,
   gotchas hit, and what was verified.
4. Do the next `pending` phase. Update this file's Status table and add a
   log entry when done, following the existing entries' format.
5. Before closing RB-04, run the dedicated device verification plan in
   `docs/rb04-device-verification-plan.md`.

## Status

| Phase | Theme | Status | Session date |
|---|---|---|---|
| 0 | Test harness + constraint golden test | **Done** | 2026-08-11 |
| 1 | Harden delete paths + RESTRICT pre-flights | **Done** | 2026-08-11 |
| 2 | Orphan repair migration (schema v23) | **Done** | 2026-08-11 |
| 3 | Flip the pragma | **Done** | 2026-08-11 |
| 4 | Schema tooling + doc bookkeeping | **Done** | 2026-08-11 |
| 5 | Manual device upgrade + UI delete-path verification | **Planned** | 2026-08-13 |

---

## Phase 0 — Test harness and constraint truth-check — DONE (2026-08-11)

**Goal:** make FK behavior testable and lock the constraint inventory,
with zero production-code changes.

**What was done:**

1. `test/support/test_database.dart` (new — first file in a `test/support/`
   dir; the suite was previously flat):
   - `openTestDatabase({bool foreignKeys = true})` — opens
     `AppDatabase.forTesting(NativeDatabase.memory())`, forces the
     migration to run first via a trivial `SELECT 1`, then issues
     `PRAGMA foreign_keys = ON` (skippable via the flag). This mirrors the
     exact pattern already proven correct in `test/schema_v21_test.dart`
     and `test/exercise_merge_test.dart` (force a query, then the pragma
     outside the migration transaction).
   - `foreignKeyViolations(db)` — wraps `PRAGMA foreign_key_check`, returns
     a typed `List<ForeignKeyViolation>` (table, rowId, parent, fkId).
   - `expectNoForeignKeyViolations(violations)` — thin `expect(..., isEmpty)`
     wrapper with a useful failure message.

2. `test/fk_constraints_test.dart` (new) — a golden test over the schema:
   - `'PRAGMA foreign_keys is actually on'` is the **first** test, asserting
     the pragma reads back `1` — so a future regression that makes
     `openTestDatabase()` silently no-op the pragma can't make the rest of
     the file pass vacuously (the other tests only inspect *declared*
     schema via `PRAGMA foreign_key_list`/`table_info`, which don't care
     whether enforcement is actually on).
   - `'declared foreign key inventory matches exactly'` — iterates every
     table via `db.allTables`, runs `PRAGMA foreign_key_list('<table>')` on
     each, and compares the full set of `(table, from, parent, to,
     onDelete)` tuples against a hard-coded 36-row `_expectedEdges` list
     (both as a set, and as a length check to catch duplicates a set
     comparison alone would hide).
   - `'edge action counts are 18 CASCADE / 10 RESTRICT / 8 SET NULL'` —
     locks the exact counts the plan and audit both cite.
   - `'every SET NULL edge targets a nullable column'` — cross-checks each
     of the 8 SET NULL edges' child column against `PRAGMA
     table_info('<table>')`'s `notnull` flag.

**How the 36-row expectation was derived:** rather than hand-parsing the
generated DDL in `database.g.dart` (fragile — the DDL is drift's own
serialization, not something to eyeball), a throwaway discovery test
(`test/_fk_discovery_test.dart`, deleted after use — not committed) opened
`openTestDatabase()` and printed `PRAGMA foreign_key_list` for every table.
Its output was pasted directly into `_expectedEdges`, so the golden list is
byte-identical to what SQLite itself reports for the current schema, not a
transcription of the plan doc's prose description.

**Confirmed against the plan:** the plan's claim of "18 CASCADE / 10
RESTRICT / 8 SET NULL = 36 edges" is exactly correct — verified both via
`grep -c 'ON DELETE CASCADE|RESTRICT|SET NULL' database.g.dart` (18/10/8)
and via the live `PRAGMA foreign_key_list` dump (same 36 tuples, same
per-action counts). No discrepancy found.

**Gotchas:**
- SQLite silently ignores `PRAGMA foreign_keys` issued inside a
  transaction, and drift runs `onCreate`/`onUpgrade` inside one — confirmed
  by the pre-existing pattern in `schema_v21_test.dart`/
  `exercise_merge_test.dart`, which `openTestDatabase()` now centralizes.
  Forcing a trivial query (`customSelect('SELECT 1').getSingle()`) before
  issuing the pragma is what makes it stick.
- `PRAGMA foreign_key_check` returns a `rowid` column that isn't always
  present depending on table shape (e.g. `WITHOUT ROWID` tables would omit
  it) — `ForeignKeyViolation.rowId` is typed `int?` for this reason, though
  no table in this schema is currently `WITHOUT ROWID`.

**Verification:**
- `flutter test test/fk_constraints_test.dart` → 4/4 passed.
- `flutter test` (full suite) → **355 tests, 3 failures**, all
  pre-existing/unrelated (same three documented in
  `docs/wear-sync-remediation-progress.md`'s Phase 1/2/4 entries): the two
  `ongoing_workout_surface_snapshot_test.dart` failures ("82.5 kg x 8" vs
  "82.5 kg x 8 reps"; action order) and the date-sensitive
  `training_blocks_view_test.dart` "the week board shows real day names,
  not placeholders" test. Zero new failures; zero failures in any file this
  phase touched.
- `flutter analyze` (full repo) → 38 issues, none in either new file
  (`test/support/test_database.dart`, `test/fk_constraints_test.dart`).
  Consistent with the 32–41 baseline range already noted as fluctuating for
  unrelated reasons in the wear-sync progress log.

**Files touched this phase:**
- `test/support/test_database.dart` (new)
- `test/fk_constraints_test.dart` (new)
- `docs/fk-enforcement-remediation-progress.md` (new — this file)

**Not committed to git** — per instruction, do not commit unless asked.

---

## Phase 1 — Harden delete paths and RESTRICT pre-flights — DONE (2026-08-11)


**Goal:** make every delete path explicitly transactional and child-first,
mirroring what the declared cascade would do, so correctness does not depend
on `PRAGMA foreign_keys` — ships safely with the pragma still off.

**What was done:**

1. `workouts_repository.dart` — `deleteSession` now deletes
   `set_accessories`/`set_bands` → `set_entries` → `workout_exercises`, then
   NULLs `scheduled_workouts.completed_session_id` **and** resets that row's
   `status` off `'done'` back to `ScheduleStatus.planned` (imported from
   `features/programs/domain/schedule_status.dart` rather than repeating the
   string literal), before deleting the session. `removeWorkoutExercise` and
   `deleteSet` now clear `set_accessories`/`set_bands` before their set
   children.
2. `programs_repository.dart` — `deleteProgram` walks
   `program_day_exercises` → sweeps `scheduled_workouts` by **both**
   `program_id` and `program_day_id` (two distinct CASCADE edges into the
   same table) → `program_days` → `program_weeks` → `programs`.
   `deleteProgramDay` clears its day exercises and schedules first.
3. `rotations_repository.dart` — `deleteRotation` deletes `rotation_members`
   and NULLs `program_day_exercises.rotation_id` before the rotation.
4. `templates_repository.dart` — `deleteTemplate` clears `template_sets` →
   `template_exercises`, NULLs `program_days.template_id` and
   `scheduled_workouts.template_id_override`, then the template.
   `deleteFolder` NULLs `workout_templates.folder_id` first.
   `removeExerciseFromTemplate` clears its `template_sets` first.
5. `gyms_repository.dart` — `deleteGym` NULLs `workout_sessions.gym_id` and
   `machine_settings.gym_id` before deleting the gym; its doc comment (which
   claimed set-null behavior that had never actually executed) now matches
   reality.
6. `micro_workouts_repository.dart` — `delete` NULLs
   `workout_sessions.micro_workout_id` first.
7. `lib/data/local/db_exceptions.dart` (new) — `FoodInUseException` with
   `entryCount`/`recipeCount`. `nutrition_repository.dart`'s `deleteFood` is
   now a transactional pre-flight: counts `food_entries` and
   `recipe_ingredients` referencing the food, throws if either is non-zero,
   otherwise deletes `food_micros` then the food. `TODO(RB-05)` left pointing
   at soft-delete. `custom_foods_view.dart` catches the exception and shows a
   SnackBar ("Used in N logged entries and M recipes").
8. `food_catalogue_importer.dart` landmine fixed. The old bulk
   `DELETE FROM foods WHERE source = 'food_catalogue_v1'` would throw under
   FK enforcement for any user who had logged a catalogue food (RESTRICT via
   `food_entries`/`recipe_ingredients`), rolling back the whole migration.
   Now: rows still referenced by a `food_entry` or `recipe_ingredient` are
   never deleted; only unreferenced stale rows are swept. Every catalogue
   item is then either updated in place (matched by `catalogueId` against the
   surviving rows) or inserted, via `Batch.update`/`Batch.insert`, instead of
   delete-and-reinsert.

**Deviation from the plan:** the plan's prose said "match on catalogue id,
`insertOnConflictUpdate`". `insertOnConflictUpdate` targets a table's
declared primary/unique key for its `ON CONFLICT` clause, and `Foods.catalogueId`
has no unique constraint (only a plain index) — adding one is a schema change
out of Phase 1's "no production behavior change beyond delete-path hardening"
scope, and would need a migration + regeneration. Implemented the same
intent — update existing catalogue rows in place rather than
delete-and-reinsert — via an explicit `catalogueId → existing row` lookup and
`Batch.update`/`Batch.insert`, without touching the schema. Worth revisiting
in Phase 4 (schema tooling) if a real unique index on `catalogueId` turns out
to be wanted anyway.

**Tests added:**

- `test/repository_delete_paths_test.dart` (new, 16 tests) — one test per
  delete path building the full tree and asserting every descendant table is
  empty and every SET NULL column is actually null, plus
  `expectNoForeignKeyViolations` after each. `deleteSession` and
  `deleteProgram` additionally get the key "identical under `foreignKeys:
  true` and `foreignKeys: false`" test — the literal proof that correctness
  doesn't depend on the pragma. `NutritionRepository.deleteFood` gets three
  tests: succeeds and removes `food_micros` when unreferenced, throws
  `FoodInUseException` with the right counts when a `food_entries` row
  references it, and again for a `recipe_ingredients` reference.
- `test/food_catalogue_importer_test.dart` extended with a new test: log an
  entry against a seeded catalogue food, force a re-import under FKs ON, and
  assert it succeeds (doesn't throw), the row is updated in place (same
  primary key, new name/kcal), and the entry survives.
- `test/exercise_merge_test.dart` — **not modified**. Its `setUp` already
  opens the database with `PRAGMA foreign_keys = ON` for every test in the
  file, so "merge succeeds under FKs ON" (RESTRICT edges 1–5 and the two
  catalog cascades) was already locked in by Phase 0's baseline; re-ran it to
  confirm all 8 tests still pass unchanged.

**Gotchas:**
- `Batch.update`'s `where` clause takes `Expression<bool> Function(T table)`,
  matching `Batch.insert`'s call shape — confirmed against the installed
  `drift-2.29.0` source (`lib/src/runtime/api/batch.dart`) since there was no
  prior `batch.update` usage anywhere in this codebase to copy from.
- `expectNoForeignKeyViolations` (from Phase 0's `test_database.dart`) is a
  synchronous `void` function, not a `Future` — `await`-ing its call site is
  a compile error, unlike `await foreignKeyViolations(db)` which it wraps.
- `drift/drift.dart`'s `isNull`/`isNotNull` top-level matchers collide with
  `flutter_test`'s; every test file that imports both needs
  `import 'package:drift/drift.dart' hide isNull, isNotNull;` (the pattern
  `exercise_merge_test.dart` already used).
- `ScheduledWorkouts.programId` is nullable — `deleteProgram`'s sweep
  distinguishes "no day-linked rows to sweep" (`dayIds.isEmpty`, filter on
  `programId` alone) from the general case (`programId` OR `programDayId
  isIn`) rather than trying to express an always-false fallback branch as a
  drift `Expression<bool>` literal.

**Verification:**
- `flutter analyze` on every Phase 1 file (10 production + 1 new test) →
  0 issues.
- `flutter test test/repository_delete_paths_test.dart
  test/food_catalogue_importer_test.dart test/exercise_merge_test.dart` →
  **25/25 passed** (16 new delete-path tests + 2 importer tests + 7
  merge-engine tests; see full-suite count below for the authoritative
  total).
- `flutter analyze` (full repo) → **34 issues**, none in any Phase 1 file;
  same pre-existing categories as Phase 0's baseline (avoid_print,
  deprecated_member_use, unused_field/unused_element in
  `active_workout_view.dart`, unintended_html_in_doc_comment,
  use_null_aware_elements). Within the 32–41 fluctuation range already noted.
- `flutter test` (full suite) → **372 tests, 3 failures** — the same three
  pre-existing/unrelated failures as Phase 0's baseline (2×
  `ongoing_workout_surface_snapshot_test.dart`, 1×
  `training_blocks_view_test.dart` "the week board shows real day names, not
  placeholders" — date-sensitive). Test count rose from 355 → 372 (17 new:
  16 in `repository_delete_paths_test.dart` + 1 in
  `food_catalogue_importer_test.dart`). Zero new failures; zero failures in
  any file this phase touched.

**Files touched this phase:**
- `lib/features/workouts/data/workouts_repository.dart`
- `lib/features/programs/data/programs_repository.dart`
- `lib/features/programs/data/rotations_repository.dart`
- `lib/features/workouts/data/templates_repository.dart`
- `lib/features/gyms/data/gyms_repository.dart`
- `lib/features/workouts/data/micro_workouts_repository.dart`
- `lib/features/nutrition/data/nutrition_repository.dart`
- `lib/features/nutrition/data/food_catalogue_importer.dart`
- `lib/features/profile/presentation/custom_foods_view.dart`
- `lib/data/local/db_exceptions.dart` (new)
- `test/repository_delete_paths_test.dart` (new)
- `test/food_catalogue_importer_test.dart` (extended)
- `docs/fk-enforcement-remediation-progress.md` (this update)

**Not committed to git** — per instruction, do not commit unless asked.

---

## Phase 3 — Flip the pragma — DONE (2026-08-11)

**Goal:** actually turn `PRAGMA foreign_keys` on in production, now that
Phase 1 (hardened delete paths) and Phase 2 (orphan repair migration) have
made it safe to do so.

**What was done:**

1. `lib/data/local/database.dart` — added `beforeOpen: (details) async {
   await customStatement('PRAGMA foreign_keys = ON'); }` to
   `MigrationStrategy`, immediately after `onUpgrade`, with a comment
   explaining why this is the only correct location (`onCreate`/`onUpgrade`
   run inside drift's migration transaction, and SQLite silently ignores the
   pragma when set inside one — `beforeOpen` runs after that transaction
   commits, before the database is handed to any caller). Checked for the
   stale "deferred" comment the plan's Context section flagged at the old
   `database.dart:366-373` — that whole block belonged to
   `_logOrphanedExerciseReferences`, which Phase 2 already deleted; nothing
   stale remained. The comment actually present near the Phase 2 repair call
   site already correctly says "the pragma lives in beforeOpen" (written
   forward-looking in Phase 2), so no rewrite was needed there either.
   Deliberately did **not** add any `foreign_key_check` sweep on every open —
   Phase 2's migration already owns repair, and a sweep on every launch would
   duplicate that work for no benefit.

2. `test/support/test_database.dart` — `openTestDatabase()` updated for the
   new reality: `AppDatabase`'s own `beforeOpen` now turns FK enforcement on
   by default for *every* database, test or production, so the helper no
   longer needs to opt in. `foreignKeys: true` (the default) is now a no-op
   pass-through; `foreignKeys: false` forces the migration to run first (a
   trivial query, same as before) and then explicitly flips the pragma back
   *off* — inverted from Phase 0's version, which had to opt *in*.

3. Every remaining test file that opened `AppDatabase.forTesting(NativeDatabase.memory())`
   directly (13 files) migrated onto `openTestDatabase()`:
   `food_catalogue_importer_test.dart`, `catalog_cleanup_test.dart`,
   `phase4_programs_test.dart`, `exercise_merge_test.dart`,
   `exercise_importer_test.dart`, `movement_layer_test.dart`,
   `phase6_dashboard_test.dart`, `exercise_catalog_validation_test.dart`,
   `phase5_nutrition_test.dart` (7 call sites),
   `widgets/training_blocks_view_test.dart`,
   `workouts_repository_notification_target_test.dart` (setUp was
   synchronous — made async),
   `wear_workout_sync_service_test.dart`, `schema_v10_test.dart` (its local
   `_openDb()` helper was a near-duplicate of `openTestDatabase()`; reduced
   to a one-line delegation). Every now-redundant manual
   `await db.customStatement('PRAGMA foreign_keys = ON')` call and the
   `package:drift/native.dart` import each site pulled in only for
   `NativeDatabase` were removed.

4. `test/fk_repair_test.dart`'s `'v22 -> v23 migration'` test — the one
   remaining direct `AppDatabase.forTesting(NativeDatabase(dbFile))` call,
   deliberately not migrated to the helper because it needs a file-backed
   database to close and reopen across a version rewind. This test plants an
   orphan `workout_exercise` (bogus `exercise_id`) against a freshly
   `onCreate`'d database to simulate pre-Phase-3 data — but with `beforeOpen`
   now always turning enforcement on, that insert started throwing instead
   of landing as a plantable orphan. Fixed by adding an explicit
   `PRAGMA foreign_keys = OFF` right after the forced `onCreate` query and
   before planting the orphan, mirroring what `openTestDatabase(foreignKeys:
   false)` does. This was the one real regression Phase 3 caused in the
   existing suite; see Verification below.

5. `test/fk_enforcement_test.dart` (new) — the goal-post test for this phase:
   - `'PRAGMA foreign_keys reads 1 on a freshly opened database, unasked'` —
     opens `AppDatabase.forTesting` directly (bypassing `openTestDatabase()`
     on purpose) and asserts the pragma reads `1` with no test code ever
     having asked for it.
   - `'inserting a child row with a bogus parent id throws'` — a
     `workout_exercise` with a nonexistent `exercise_id` now throws
     `SqliteException` at insert time.
   - `'deleting a workout_session cascades to set_entries at the DB level'`
     — deletes a session via a raw `DELETE` statement (not through
     `WorkoutsRepository.deleteSession`, which already child-deletes itself
     per Phase 1) and asserts the DB's own CASCADE removed the child
     `workout_exercises`/`set_entries` rows — proof the enforcement is real,
     not just proof the repository is careful.
   - `'deleting a referenced food throws'` — a RESTRICT edge
     (`food_entries.food_id`) now actually blocks the delete.
   - `'PRAGMA foreign_keys is a no-op inside a transaction — why onUpgrade
     can't be where it's set'` — the test-only assertion the plan asked for.
     Rather than trying to observe `AppDatabase`'s own opaque migration
     transaction from outside (not possible without instrumenting production
     code, which felt like the wrong tool for a test), this re-creates the
     identical SQLite condition via `db.transaction()`: issues
     `PRAGMA foreign_keys = OFF` inside a transaction and asserts the pragma
     still reads `1` both *during* the transaction and *after* it commits —
     proving the write is a true no-op, not merely deferred. This is the
     exact mechanic `onUpgrade` runs under, demonstrated without needing a
     new dependency or a production-code hook.

**Deviation from the plan:** none in intent. The one implementation choice
worth flagging is #5's last test — the plan's phrasing ("a test-only
assertion proving the pragma is off during onUpgrade") suggested observing
`onUpgrade` itself, but `AppDatabase`'s migration transaction isn't
independently observable from outside drift once `beforeOpen` always runs
immediately after it. Demonstrating the general SQLite mechanism via
`db.transaction()` proves the same fact `onUpgrade` depends on, using only
public API.

**Gotchas:**
- The regression in `fk_repair_test.dart` (#4 above) is a preview of a
  general pattern worth remembering for Phase 4 or any future work: any test
  fixture that plants pre-Phase-3-style dangling references by inserting
  directly (not through `openTestDatabase(foreignKeys: false)` or an
  equivalent explicit `PRAGMA foreign_keys = OFF`) will now fail at insert
  time instead of producing the orphan it wants. `fk_repair_test.dart`'s
  other group (`repairForeignKeyViolations`, testing the function directly
  rather than the full migration) already opened with `foreignKeys: false`
  from Phase 2 and needed no change.
- The plan's flagged highest-risk areas — (a) children written before
  parents inside a transaction, (b) `wear_workout_sync_service.dart`
  reconstructing sessions from the wire protocol with possibly-unknown
  catalog ids, (c) `pending_sync_ops` replay — produced zero new failures
  once `wear_workout_sync_service_test.dart` ran under real enforcement via
  the migration to `openTestDatabase()`. Nothing in the existing test
  coverage exercises a phone lacking a catalog exercise the watch references,
  so that specific scenario ((b)) is asserted safe only insofar as the
  existing tests exercise it — see the Phase 4 handoff note on the still-owed
  manual device upgrade pass.

**Verification:**
- `flutter analyze` on `lib/data/local/database.dart`,
  `test/support/test_database.dart`, `test/fk_enforcement_test.dart` → 0
  issues.
- `flutter test test/fk_enforcement_test.dart` → **5/5 passed**.
- `flutter test test/fk_repair_test.dart` → **4/4 passed** (after the
  `PRAGMA foreign_keys = OFF` fix in the migration test).
- `flutter analyze` (full repo) → **34 issues** (deduplicated). Zero in any
  Phase 3 file. The 5-issue rise over Phase 2's 29 is
  `test/wear_workout_sync_service_test.dart:470,483`
  (`use_null_aware_elements`, pre-existing code untouched by this phase's
  edits, well inside the codebase's own `if (x != null) 'k': v` map-literal
  style used throughout) — within the previously-noted fluctuation range,
  confirmed pre-existing by inspecting those exact lines (unrelated helper
  functions, no diff there this phase).
- `flutter test` (full suite) → **381 tests, 3 failures** — the same three
  pre-existing/unrelated failures as every prior phase's baseline (2×
  `ongoing_workout_surface_snapshot_test.dart`, 1×
  `training_blocks_view_test.dart` "the week board shows real day names, not
  placeholders" — date-sensitive). Test count rose from 376 → 381 (5 new, all
  in `fk_enforcement_test.dart`). Zero new failures once the
  `fk_repair_test.dart` fixture fix (#4 above) landed; the first full run
  before that fix showed exactly one additional failure, in that one test,
  confirming it was Phase 3's own regression and not something pre-existing.

**Manual verification still owed (this session cannot do it):** a real
device upgrade pass — install a pre-Phase-2 build, use the app long enough to
accumulate real data (including whatever orphans already exist on that
install), then upgrade straight to this Phase-3 build, and exercise every
delete path from the UI (delete workout, delete program, delete template,
delete gym, delete food, delete rotation, remove exercise from
template/workout, delete set). The full test suite proves the migration and
enforcement logic are correct against synthetic fixtures; it cannot prove
the *actual* shape of orphan data real users have accumulated over time
repairs cleanly, nor that no UI delete path outside the ones Phase 1 hardened
still writes a child before its parent. This should happen before Phase 3
ships, not before Phase 4 starts — Phase 4 is schema tooling and doc
bookkeeping, not further behavior change, so it doesn't block on this, but
shipping does.

**Files touched this phase:**
- `lib/data/local/database.dart`
- `test/support/test_database.dart`
- `test/fk_enforcement_test.dart` (new)
- `test/fk_repair_test.dart`
- `test/food_catalogue_importer_test.dart`
- `test/catalog_cleanup_test.dart`
- `test/phase4_programs_test.dart`
- `test/exercise_merge_test.dart`
- `test/exercise_importer_test.dart`
- `test/movement_layer_test.dart`
- `test/phase6_dashboard_test.dart`
- `test/exercise_catalog_validation_test.dart`
- `test/phase5_nutrition_test.dart`
- `test/widgets/training_blocks_view_test.dart`
- `test/workouts_repository_notification_target_test.dart`
- `test/wear_workout_sync_service_test.dart`
- `test/schema_v10_test.dart`
- `docs/fk-enforcement-remediation-progress.md` (this update)

**Not committed to git** — per instruction, do not commit unless asked.

---

## Phase 2 — Orphan repair migration (schema v22 → 23) — DONE (2026-08-11)

**Goal:** bring every existing device to zero `PRAGMA foreign_key_check`
violations, with `PRAGMA foreign_keys` still off. App behaves identically
afterward; the data is just clean.

**What was done:**

1. `lib/data/local/fk_repair.dart` (new) — `repairForeignKeyViolations(GeneratedDatabase db)`
   returns an `FkRepairReport` (`nulled`/`deleted` maps keyed by
   `'table.column'`/`table`, plus `residualViolations`). Written against raw
   `customStatement`/`customSelect`/`customUpdate` only, per the plan's
   "migration code must stay frozen against its shipped schema" rule. Two
   passes:
   - **NULL pass** — all 8 `SET NULL` edges, each an `UPDATE ... SET col =
     NULL WHERE col IS NOT NULL AND col NOT IN (SELECT id FROM parent)`.
     `scheduled_workouts.completed_session_id` additionally resets `status`
     off `'done'` back to `'planned'` in the same statement — the one repair
     that isn't a bare mirror of the declared FK action, called out
     specifically because Phase 1's repository-layer fix only prevents *new*
     `'done'`-with-orphan rows; it can't reach rows that went orphaned before
     Phase 1 shipped.
   - **Delete pass** — 19 tables, deepest-first, in the exact order the plan
     specifies (`set_accessories`/`set_bands` → `set_entries` →
     `workout_exercises` → `template_sets` → `template_exercises` →
     `program_day_exercises` → `program_days` → `program_weeks` →
     `scheduled_workouts` → `recipe_ingredients` → `food_micros` →
     `food_entries` → `rotation_members` → `micro_workouts` →
     `exercise_muscles`/`exercise_aliases` → `exercise_progressions` →
     `machine_settings`), one `DELETE ... WHERE col NOT IN (...) OR col2 NOT
     IN (...)` per table covering every RESTRICT/CASCADE edge that table
     owns (28 edges across the 19 tables, verified against the 36-edge
     inventory in `fk_constraints_test.dart` so nothing was missed).
   - Re-runs `PRAGMA foreign_key_check` as a post-condition; non-empty
     residue is logged via `dart:developer`'s `log()`, never thrown — per the
     plan, throwing would roll back the whole migration transaction and
     boot-loop the device.
2. `lib/data/local/database.dart`:
   - `schemaVersion` bumped 22 → 23.
   - `_logOrphanedExerciseReferences()` and its `from < 17` call site
     deleted — Phase 2 supersedes its 7-table report-only sweep with a real
     28-edge repair.
   - New `if (from < 23)` branch: calls `repairForeignKeyViolations(this)`,
     logs non-zero per-edge counts, then creates 34 `CREATE INDEX IF NOT
     EXISTS idx_fk_<table>_<column>` indexes — one per FK child column across
     all 36 edges, minus `set_accessories.set_entry_id` and
     `set_bands.set_entry_id`, which already have indexes from the v10
     migration (`idx_set_accessories_set`, `idx_set_bands_set`).
3. Regenerated via `dart run build_runner build --delete-conflicting-outputs`
   (343 outputs written; migration logic lives in hand-written
   `database.dart`, not the generated part, so the diff is additive schema
   metadata only).

**Deviation from the plan — both defensive, both required by the test
suite's existing fixture pattern:** every `customUpdate`/`customStatement`
call inside `repairForeignKeyViolations` and the new index-creation loop is
wrapped in `try { } catch (_) { }`, swallowing "no such table" the same way
the v17 sweep it replaces did. Reason: `test/schema_v21_test.dart`'s
`_V20Fixture` hand-stamps only 5 tables (the ones its own v21 migration
step touches) before reopening as the real `AppDatabase` — the upgrade chain
then runs every `if (from < N)` block for N > 20, including the new `from <
23` block, against a database that never had `gyms`, `foods`,
`exercise_catalog`, etc. On a real device this can't happen (every table here
was created by an earlier `onUpgrade` step long before v23), but the test
fixture pattern is established and reused across three migration test files
now — not something to redesign inside this phase.

**Tests added:**

- `test/fk_repair_test.dart` (new):
  - `repairForeignKeyViolations` group — one orphan per class (bogus
    `exercise_id` on a `workout_exercise`, a `set_entry` under a
    nonexistent `workout_exercise_id`, a `workout_session` with a bogus
    `gym_id`, a `food_entry` with a bogus `food_id`, a `template_exercise`
    with a bogus `exercise_id`, plus a `scheduled_workouts` row with a bogus
    `completed_session_id` **and** `status = 'done'` to specifically lock the
    sibling-column fix) — asserts `foreign_key_check` empty after repair,
    each orphan gone/nulled as appropriate, report counts match, and
    untouched real data (the seeded catalog exercise) survives. Idempotency
    test (second run repairs nothing, all counts 0). Clean-DB no-op test.
  - `v22 -> v23 migration` group — rather than hand-transcribing ~30 tables
    of DDL in `_V20Fixture`'s style (Phase 2 changes no table shapes, only
    adds a repair + indexes, so v22's shape is byte-identical to v23's),
    this builds a real, fully-shaped file-based database via the normal
    `onCreate` path, plants one orphan `workout_exercise`, rewinds
    `PRAGMA user_version` to 22, closes, and reopens as a fresh
    `AppDatabase.forTesting` — exercising the actual `from < 23` branch
    end-to-end. Asserts `user_version == 23`, `foreign_key_check` empty, and
    the planted orphan gone while the real session row survives.
- `test/schema_v21_test.dart` — `'reaches schema version 22'` renamed to
  `'reaches schema version 23'` and its assertion updated, since the full
  upgrade chain this test exercises now continues past v22 to v23.

**Gotchas:**
- SQLite's `NOT IN (SELECT ...)` against a nullable column evaluates to
  `NULL` (falsy) when the column itself is `NULL`, so `DELETE FROM t WHERE
  col NOT IN (...)` already skips legitimately-unset nullable FK columns
  without an explicit `col IS NOT NULL` guard — used bare in most delete
  statements, with an explicit guard only where it made the intent clearer
  to a reader (`food_entries`, `scheduled_workouts.program_id`).
- `db.customUpdate` (not `customStatement`) is what returns an affected-row
  count for `UPDATE`/`DELETE` — needed for the report; `customStatement`
  returns `void`.
- The `from < 23` branch's index-creation loop uses a `List<(String,
  String)>` of record types rather than a `Map` — column order matters for
  readability against the 36-edge inventory, and records destructure
  cleanly in the `for (final (table, column) in ...)` loop.

**Verification:**
- `dart run build_runner build --delete-conflicting-outputs` → 343 outputs,
  clean.
- `flutter analyze` on `lib/data/local/fk_repair.dart`,
  `lib/data/local/database.dart`, `test/fk_repair_test.dart`,
  `test/schema_v21_test.dart` → 0 issues.
- `flutter test test/fk_repair_test.dart test/schema_v21_test.dart` →
  **14/14 passed**.
- `flutter test` (full suite) → **376 tests, 3 failures** — the same three
  pre-existing/unrelated failures as Phase 0/1's baseline (2×
  `ongoing_workout_surface_snapshot_test.dart`, 1×
  `training_blocks_view_test.dart` "the week board shows real day names, not
  placeholders" — date-sensitive). Test count rose from 372 → 376 (4 new,
  all in `fk_repair_test.dart`). One additional failure
  (`wear_sync_contract_test.dart` "allocators with different keys do not
  collide") appeared on the first full-suite run but passed cleanly both in
  isolation and on a second full-suite run — flaky/unrelated (revision
  allocator test, no relationship to schema or FK code), not counted against
  Phase 2.
- `flutter analyze` (full repo) → **29 issues** (deduplicated; the raw CLI
  output doubles every line in this environment), down from Phase 1's 34 —
  removing `_logOrphanedExerciseReferences`'s `print` call accounts for the
  drop. Zero issues in any Phase 2 file. Within the previously-noted
  fluctuation range.

**Files touched this phase:**
- `lib/data/local/fk_repair.dart` (new)
- `lib/data/local/database.dart`
- `lib/data/local/database.g.dart` (regenerated)
- `test/fk_repair_test.dart` (new)
- `test/schema_v21_test.dart`
- `docs/fk-enforcement-remediation-progress.md` (this update)

**Not committed to git** — per instruction, do not commit unless asked.

---

## Phase 4 — Schema tooling and doc bookkeeping — DONE (2026-08-11)

**Goal:** stop hand-writing migration fixtures going forward, and fix the doc
drift the v10 → v23 bump exposed. No production-code behavior change.

**What was done:**

1. `dart run drift_dev schema dump lib/data/local/database.dart drift_schemas/`
   → `drift_schemas/drift_schema_v23.json` (new). As the plan flagged, `schema
   dump` only captures the **current** version — there is no retroactive
   v1–v22 snapshot, only forward coverage from v23 on.
2. `dart run drift_dev schema generate drift_schemas/ test/generated_migrations/`
   → `test/generated_migrations/schema.dart` (the `GeneratedHelper`) and
   `schema_v23.dart` (new, generated — both carry drift's own
   `// GENERATED CODE, DO NOT EDIT BY HAND` + `ignore_for_file: type=lint`
   headers).
3. `test/migration_test.dart` (new) — uses `SchemaVerifier` from
   `package:drift_dev/api/migrations_native.dart` (the non-deprecated import;
   `api/migrations.dart` re-exports the same thing but is marked
   `@Deprecated`) to assert `AppDatabase`'s live schema (opened via the
   existing `openTestDatabase()` helper from Phase 0) matches the
   `drift_schemas/drift_schema_v23.json` snapshot via `migrateAndValidate(db,
   23)`. Since only v23 is dumped, this proves "the hand-written `tables.dart`
   matches what was last dumped" — a drift detector for future schema edits —
   not a full v1→v23 migration-chain replay. The file's own doc comment
   states this limitation and the "re-dump on every schemaVersion bump"
   obligation, so it doesn't need re-deriving from this log later.
4. `test/schema_v21_test.dart` — kept as-is, unmodified this phase, per the
   plan's step 2 ("keep until generated fixtures cover the same ground") —
   generated fixtures don't cover v1–v22 at all, so this stays the only test
   exercising the real upgrade chain from an old on-disk schema.
5. `README.md:25` — `(schema v10)` → `(schema v23)`. Verified with `grep -n
   "schema v10" README.md` → no hits.
6. `docs/v2/02-SCHEMA-AND-MIGRATION.md` — added a note block right after the
   file's opening paragraph: schema is at v23 (this doc's body still only
   describes up through v12 — intentionally left alone rather than
   backfilling v13–v22 prose that has no bearing on future work), FK
   enforcement is ON via `beforeOpen`, migrations still run with FKs OFF and
   why, and a pointer to the `legacy_alter_table` rebuild recipe + the new
   `drift_schemas/` snapshot requirement for any future constraint change
   (the thing RB-05's deferred soft-delete work will need).
7. `docs/app-audit-report-2026-08-10.md` — added an "Addressed" callout
   directly under the "4. Database Foreign Keys Are Disabled" heading,
   pointing at this progress doc, naming what's deferred to RB-05, and
   flagging the still-owed manual device upgrade pass so it isn't lost by a
   reader who only skims the audit report and never opens this file.

**Deviation from the plan:** the plan listed `build.yaml (new)` as a Phase 4
file. Investigated `drift_dev 2.29.0`'s own `build.yaml` (the package's
builder manifest, read directly from the pub cache) — its builder set
(`preparing_builder`, `drift_dev`, `not_shared`, `modular`, `analyzer`) has no
builder that hooks `schema dump`/`schema generate` into `build_runner build`;
those are both standalone CLI subcommands, not build.yaml-configurable in
this drift_dev version, and adding an empty/inert `build.yaml` would add pure
risk (the plan's own Phase 4 "Risk" line: "introducing build.yaml can perturb
codegen") for zero functional benefit. **Skipped it.** This phase never ran
`dart run build_runner build --delete-conflicting-outputs`, so
`database.g.dart` is untouched — there was nothing to regenerate since no
`tables.dart` change occurred. If a real future need for build.yaml-
configurable drift_dev options (e.g. codegen naming style) shows up, add it
then, scoped to that need, rather than speculatively now.

**Tests added:**
- `test/migration_test.dart` (new, 1 test) — see #3 above.

**Gotchas:**
- `package:drift_dev/api/migrations.dart` is `@Deprecated` in favor of
  `package:drift_dev/api/migrations_native.dart` (same API, re-exported) —
  used the non-deprecated import directly to avoid an avoidable analyzer
  info-level hit.
- `SchemaVerifier.migrateAndValidate(db, expectedVersion)` opens a *second*,
  independent in-memory database from the `test/generated_migrations/`
  snapshot at `expectedVersion`, diffs its collected schema against `db`'s,
  and throws `SchemaMismatch` on any difference — it does not need or use
  `db`'s own `schemaVersion` getter, only whatever `expectedVersion` you pass
  it, which is why passing `23` (matching the one dumped snapshot) rather
  than reading `AppDatabase().schemaVersion` was the correct and only choice
  here.

**Verification:**
- `dart run drift_dev schema dump lib/data/local/database.dart drift_schemas/`
  → wrote `drift_schemas/drift_schema_v23.json`, clean.
- `dart run drift_dev schema generate drift_schemas/ test/generated_migrations/`
  → "Wrote 2 files into test\generated_migrations", clean.
- `flutter test test/migration_test.dart` → **1/1 passed**.
- `flutter analyze` (full repo) → **34 issues** (deduplicated), identical
  count to Phase 3's baseline, zero in any Phase 4 file (including the two
  generated files under `test/generated_migrations/`, which carry drift's own
  lint-suppression header).
- `flutter test` (full suite) → **382 tests, 3 failures** — the same three
  pre-existing/unrelated failures as every prior phase's baseline (2×
  `ongoing_workout_surface_snapshot_test.dart`, 1×
  `training_blocks_view_test.dart` "the week board shows real day names, not
  placeholders" — date-sensitive). Test count rose from 381 → 382 (the one
  new `migration_test.dart` test). Zero new failures; zero failures in any
  file this phase touched.
- `grep -n "schema v10" README.md` → no hits.

**Manual verification still owed — restated, not performed by this or any
prior session:** a real device upgrade pass (install a pre-Phase-2 build, use
the app long enough to accumulate real data including whatever orphans
already exist on that install, upgrade straight to this Phase-4 build, and
exercise every UI delete path — workout, program, template, folder, gym,
rotation, custom food both deletable and in-use, remove exercise from
template/workout, delete set). Every phase's synthetic-fixture test suite
proves the migration and enforcement logic are correct against constructed
data; none of it can prove the actual shape of orphan data real users have
accumulated repairs cleanly, nor that no UI delete path outside the ones
Phase 1 hardened still writes a child before its parent. **This blocks
shipping the RB-04 workstream regardless of Phase 4's own completion** — it
was owed before Phase 3 shipped per that phase's own log entry, remains owed
now, and no chat session run so far has had device access to perform it.

**Files touched this phase:**
- `drift_schemas/drift_schema_v23.json` (new)
- `test/generated_migrations/schema.dart` (new, generated)
- `test/generated_migrations/schema_v23.dart` (new, generated)
- `test/migration_test.dart` (new)
- `README.md`
- `docs/v2/02-SCHEMA-AND-MIGRATION.md`
- `docs/app-audit-report-2026-08-10.md`
- `docs/fk-enforcement-remediation-progress.md` (this update)

**Not committed to git** — per instruction, do not commit unless asked.

---
