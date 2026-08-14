---
phase: 10-assisted-rep-tracking
plan: 01
subsystem: database
tags: [drift, sqlite, migration, riverpod, consent, privacy, rep-tracking]

# Dependency graph
requires:
  - phase: 09-analytics-consolidation
    provides: merge-order only — Phase 9 added no tables, so v26 is free
provides:
  - Schema v26 with three local-only tables (rep_tracking_settings, rep_tracking_exercise_prefs, rep_set_observations)
  - RepMovement enum — the single declaration in the repository
  - eligibleRepSlugs / isEligible / movementFor — the closed slug registry
  - RepTrackingRepository — consent, per-exercise opt-in, observation write + training query
  - repTrackingRepositoryProvider / repTrackingSettingsProvider / repTrackingEnabledForProvider
  - test/rep_local_only_test.dart — the positive sqlite_master proof of REP-04
affects: [10-02, 10-03, 10-04, 10-05]

# Tech tracking
tech-stack:
  added: []
  patterns:
    - "Local-only Drift table: no SyncColumns/SyncTombstone mixin, absent from syncedTableNames and syncTableSpecs, asserted positively against sqlite_master"
    - "Consent-first short-circuit: the master gate is read before any per-entity preference row"
    - "Single-owner enum file: RepMovement lives alone so downstream plans import it without pulling in the slug list"

key-files:
  created:
    - lib/features/reps/domain/rep_movement.dart
    - lib/features/reps/domain/rep_tracking_eligibility.dart
    - lib/features/reps/data/rep_tracking_repository.dart
    - lib/features/reps/presentation/rep_tracking_providers.dart
    - drift_schemas/drift_schema_v26.json
    - test/generated_migrations/schema_v26.dart
    - test/schema_v26_test.dart
    - test/rep_local_only_test.dart
    - test/rep_tracking_eligibility_test.dart
    - test/rep_tracking_repository_test.dart
  modified:
    - lib/data/local/tables.dart
    - lib/data/local/database.dart
    - lib/data/local/database.g.dart
    - test/migration_test.dart
    - test/generated_migrations/schema.dart

key-decisions:
  - "RepSetObservations.setEntryId is a plain nullable int, not a references() edge — calibration history must survive a discarded set, and a cascade would erase it"
  - "revokeConsent deletes prefs as well as observations, so a later re-consent starts from every exercise off rather than a forgotten opt-in"
  - "setExerciseEnabled throws ArgumentError on an ineligible slug rather than silently no-op'ing, because a silent write looks like a working opt-in in the UI"
  - "The eligibility registry stores no exercise IDs — slug is the only identity that survives a catalogue re-import"

patterns-established:
  - "Local-only table proof: query sqlite_master for triggers rather than grepping source, because installSyncTriggers writes DDL from a name list that no source grep over tables.dart would reach"
  - "Schema-version bump checklist: build_runner -> drift_dev schema dump -> drift_dev schema generate -> repoint every migrateAndValidate call -> add a fixture replay from the previous version"

requirements-completed: [REP-01, REP-04]

# Metrics
duration: 71min
completed: 2026-08-14
---

# Phase 10 Plan 01: Rep Tracking Persistence and Consent Summary

**Schema v26 lands three sync-exempt tables, a closed seven-slug eligibility registry keyed on catalogue slug, and the repository whose consent-first gate every later Phase 10 plan reads through.**

## Performance

- **Duration:** ~71 min
- **Tasks:** 3 of 3
- **Files modified:** 15 (10 created, 5 modified)
- **Tests:** 28 new/updated passing; full suite 538 passed, 4 skipped, 0 failed

## Accomplishments

- **REP-04 is decided and proven here.** `RepTrackingSettings`, `RepTrackingExercisePrefs` and `RepSetObservations` mix in neither `SyncColumns` nor `SyncTombstone`, appear in neither `syncedTableNames` nor `syncTableSpecs`, and `test/rep_local_only_test.dart` asserts against `sqlite_master` on a fully-migrated database that no outbox trigger names any of them. The test also sanity-checks that triggers *do* exist on that database, so the assertion cannot pass vacuously.
- **No column in `RepSetObservations` can hold a raw sample array.** Only `featuresJson` (derived vector, schema owned by 10-02) and the confirmed outcome persist. A test enumerates forbidden column names and additionally asserts the table declares no `BLOB` column at all.
- **`RepMovement` has exactly one declaration**, in `lib/features/reps/domain/rep_movement.dart`, verified by `grep -rn "enum RepMovement" lib/` returning a single line. 10-02, 10-03b and 10-05 import it; a redeclaration is a compile error.
- **Consent is the single authority.** `isEnabledFor` reads `settings()` first and returns false when `consentGrantedAt` is null regardless of the per-exercise row — proven by a test that writes `enabled: true` directly to the prefs table, bypassing the repository, and still gets false.
- **`revokeConsent()` is a real erase, not a hide.** One transaction clears the gate and deletes every prefs row and every observation row; the test grants consent, enables two exercises, records three observations, revokes, and asserts both child tables are empty.
- The full migration suite now validates at 26 across four replays (current-schema, v23, v24 and a new v25 fixture).

## Task Commits

1. **Task 1: Three local-only tables, schema bump to v26, migration suite repointed** — `33ec560` (feat)
2. **Task 2: RepMovement and the closed eligibility registry** — `78669bf` (feat)
3. **Task 3: Rep tracking repository and Riverpod providers** — `1412832` (feat)

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 1 - Bug] `setExerciseEnabled` threw `UNIQUE constraint failed` on the second toggle of the same slug**

- **Found during:** Task 3 (caught by the plan's own "is idempotent for an eligible slug" test)
- **Issue:** The implementation used drift's `insertOnConflictUpdate`, which derives its conflict target from the **primary key**. `RepTrackingExercisePrefs` has an autoincrement `id` primary key and a *separate* unique key on `exerciseSlug`. A fresh companion supplies no `id`, so the `ON CONFLICT("id")` clause never matched, and the insert hit the `exercise_slug` unique index instead — `SqliteException(2067)`. In practice this meant a user could enable an exercise but never turn it off again, which is a consent-control failure, not just an inconvenience.
- **Fix:** Replaced with an explicit `onConflict: DoUpdate(..., target: [_db.repTrackingExercisePrefs.exerciseSlug])`, with a comment recording why the default target is wrong here so the shorter form is not restored later.
- **Files modified:** `lib/features/reps/data/rep_tracking_repository.dart`
- **Commit:** `1412832`

### Additions Beyond the Written Plan

**2. [Rule 2 - Missing critical coverage] `rep_local_only_test.dart` gained a third test and a vacuity guard**

The plan specified the trigger query and the two sync-list assertions. Added:
- A `expect(rows, isNotEmpty)` sanity check on the trigger query — without it, a future refactor that stopped installing sync triggers entirely would make the central REP-04 assertion pass for the wrong reason.
- A `PRAGMA table_info(rep_set_observations)` test asserting no raw-sample-shaped column name and no `BLOB` column. This is the T-10-02 mitigation, which the plan's threat model assigns to Task 1 but which no listed test covered.

**3. [Rule 2] `prefFor(String slug)` added to the repository**

`isEnabledFor` deliberately collapses consent and preference into one bool, so there was no way for a test — or 10-04's consent UI — to read the stored preference itself. Added a small read accessor rather than letting callers reach past the repository into the table.

**4. Slug existence verified against the catalogue asset**

Before committing Task 2, confirmed all seven slugs resolve to exactly one row each in `assets/data/exercises.json`. A typo in the registry would have produced a silently dead feature that every test in this plan would still pass.

## Verification Results

| Check | Result |
|---|---|
| `flutter test test/migration_test.dart test/schema_v26_test.dart test/rep_local_only_test.dart test/rep_tracking_eligibility_test.dart test/rep_tracking_repository_test.dart` | 28/28 pass |
| `flutter analyze lib/features/reps/` | No issues found |
| `grep -n "rep_tracking_settings\|rep_tracking_exercise_prefs\|rep_set_observations" lib/data/local/migrations/sync_backfill.dart lib/data/sync/sync_table_specs.dart` | no matches (exit 1) |
| `git diff --stat lib/data/local/migrations/sync_backfill.dart lib/data/sync/sync_table_specs.dart` | empty — neither file changed |
| `grep -rn "enum RepMovement" lib/` | exactly one line, in `rep_movement.dart` |
| `flutter test` (full suite) | 538 passed, 4 skipped, 0 failed |

## Interface Contract for Downstream Plans

- **10-02** imports `RepMovement` from `lib/features/reps/domain/rep_movement.dart` for `RepDetectorConfig.forMovement`. It must not redeclare the enum and must not import `rep_tracking_eligibility.dart` (the slug list is a consent concern, not a detection one).
- **10-03b** imports the same enum for `RepSuggestion`.
- **10-04** reads consent through `repTrackingEnabledForProvider` / `repTrackingSettingsProvider` and writes it through `grantConsent` / `revokeConsent` / `setExerciseEnabled`. It must not query the three tables directly.
- **10-05** trains on `observationsFor({slug, source, placement, sensorType})` — an exact tuple, ordered by `recordedAt` ascending. A null `placement` means the wrist case, not a wildcard.
- `featuresJson`'s internal schema is owned by 10-02; this plan treats it as an opaque string.

## Known Stubs

None. Every surface this plan declares is implemented and tested. The feature is not yet reachable from the UI, which is 10-04's scope and is stated as out of scope in this plan's objective — not a stub.

## Threat Flags

None. The plan's four `mitigate` dispositions (T-10-01 through T-10-04) are each implemented and covered by a named test, and no new security-relevant surface was introduced beyond what the threat model enumerates. `pubspec.yaml` is untouched, so T-10-SC's `accept` disposition still holds.

## Notes for Future Phases

- The `RepTrackingSettings` singleton is enforced by convention in `grantConsent`, not by a schema constraint (the table has an autoincrement `id`, matching the plan's spec). Any future code that inserts into this table directly must update the existing row instead. `settings()` reads with `limit(1)`, so a stray second row would be silently ignored rather than throwing.
- `consentVersion` exists but nothing yet compares it against a current-version constant. When data handling changes, 10-04's consent flow is where the re-consent check belongs.
- `phonePlacement` must be non-null before the phone source is usable (REP-02). That invariant is documented on the column but not yet enforced — enforcement belongs to 10-03/10-04, where the source is actually selected.
