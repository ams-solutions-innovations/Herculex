---
phase: 23-persistent-dream-physique-multi-phase-nutrition
plan: 06
subsystem: physique-data
tags: [drift, repository, roadmap, goals, sync]
requires: ["23-01", "23-02"]
provides:
  - PhysiqueGoalRepository (start/archive/reconcile/watch, legacy photo append)
  - PhysiqueRoadmapRepository (replace/accept, advance, postpone)
  - FakeClock test helper, physiqueDayKey
affects: [23-07, 23-09, 23-11]
tech-stack:
  patterns: [drift transactions, stream reads, injected Clock]
key-files:
  created:
    - lib/features/physique/data/physique_date_keys.dart
    - lib/features/physique/data/physique_goal_repository.dart
    - lib/features/physique/data/physique_roadmap_repository.dart
    - test/support/fake_clock.dart
    - test/features/physique/physique_goal_repository_test.dart
    - test/features/physique/physique_roadmap_repository_test.dart
decisions:
  - Active-goal winner is chosen in Dart (non-legacy first, then startedAt, then id) rather than SQL CASE ordering
  - Replaced roadmap phases are hard-deleted (sync tombstone); done phases are kept
metrics:
  tasks: 2
  files: 6
completed: 2026-10-02
---

# Phase 23 Plan 06: Goal and Roadmap Repositories Summary

Transactional goal repository (archive-not-delete history, single-active reconciliation with legacy_import never outranking a live goal, idempotent legacy photo append) and a roadmap repository where accept, advance and postpone happen only through explicit calls and never touch nutrition targets.

## Tasks

1. FakeClock, `physiqueDayKey`, `PhysiqueGoalRepository` - commit d78143b
2. `PhysiqueRoadmapRepository` - commit fd95530

## Deviations from Plan

None in behavior. `replaceRoadmap` was made `async` so the empty-drafts ArgumentError surfaces as a future error. In the goal test, the rollback case is forced with a duplicate `goalSyncUuid`.

## Verification

`flutter test test/features/physique test/physique_sync_registration_test.dart` passes (143). `flutter analyze` on the new files is clean (5 pre-existing issues elsewhere, e.g. `test/widgets/day_detail_sheet_test.dart`). `check_structure` names no `features/physique` file.

## Known Stubs

None.

## Self-Check: PASSED
