---
phase: 23-persistent-dream-physique-multi-phase-nutrition
plan: 09
subsystem: data-migration
tags: [physique, migration, gdpr, wipe, drift]
requires: ["23-02", "23-03", "23-06"]
provides:
  - PhysiqueSummaryBridge (watchCurrent/watchHistory returning DreamPhysiqueAnalysisSummary from physique tables)
  - PhysiqueLegacyMigrator.run and LegacyMigrationResult
  - wipeAllLocalUserData clears physique tables and photo folder
affects: [23-11, 23-14, 23-15, 23-17]
tech-stack:
  added: []
  patterns: [state-based idempotence via legacyRef, delete-after-commit, nested drift transaction]
key-files:
  created:
    - lib/features/physique/data/physique_summary_bridge.dart
    - lib/features/physique/data/physique_legacy_migrator.dart
    - test/features/physique/physique_summary_bridge_test.dart
    - test/features/physique/physique_legacy_migrator_test.dart
    - test/features/physique/physique_wipe_test.dart
  modified:
    - lib/data/local/local_data_wipe.dart
    - test/auth/account_deletion_test.dart
decisions:
  - "Migrator wraps startGoal plus a assessmentId=null update in one outer db.transaction, because startGoal links baseline photos to the newest assessment while legacy photos must stay unlinked"
  - "Wipe folder name is a constant in local_data_wipe.dart (physiquePhotoFolderName), equality with PhysiquePhotoStore.rootFolderName is enforced by a test, so data/local imports no feature"
  - "tdee_estimates and herculex_ai_program_briefs added to the wipe list (existing completeness gap)"
metrics:
  tasks: 2
  completed: 2026-10-02
---

# Phase 23 Plan 09: Legacy migration, summary bridge and physique wipe

Idempotent app-level migrator that turns the SharedPreferences Dream Physique history and legacy `progress_photos` rows into a `legacy_import` goal (including a synthesized neutral goal for photos-only users), a database-backed summary bridge, and an account-deletion wipe that now removes physique rows and photo files.

## Commits
- c9f0b40: PhysiqueSummaryBridge and wipe extension, tests
- cc28bde: PhysiqueLegacyMigrator and tests

## Behavior
- History becomes oldest-first analysis assessments (summaryJson = entry toJson); newest entry defines style, months, target BF; startedAt is the oldest entry.
- Photos-only: null target and months, empty style, one maintain proposal, startedAt is the earliest parsable photo date.
- All photos go through the sanitiser (EXIF stripped); originals and rows deleted only after commit; missing or corrupt files are kept and reported once.
- A live goal is never displaced: with a live goal present the legacy goal is inserted archived.
- No done flag; later `progress_photos` rows are appended to the existing legacy goal, each once; crash recovery cleans rows whose legacyRef is already stored.
- Bridge is not wired into providers (Plan 15 switches them with the save path).

## Deviations from Plan
None in behavior. The migrator is not yet invoked anywhere (wiring is Plan 11/14).

## Known Stubs
None.

## Issues
`flutter analyze` reports one pre-existing warning (`TableMigration` experimental, database.dart:1119), out of scope.

## Self-Check: PASSED
