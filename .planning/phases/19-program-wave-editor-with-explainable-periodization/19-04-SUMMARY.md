---
phase: 19
plan: 04
subsystem: programs-presentation
tags: [riverpod, drift, week-wave-editor, exercise-replacement, widget-test]
dependency-graph:
  requires:
    - phase: 19-01
      provides: "WaveLabel.compute / WaveLabel.selectAnchorSlot pure domain functions"
    - phase: 19-02
      provides: "ExerciseReplacementSheet / ExerciseReplacementSelection extracted widget"
  provides:
    - "BlockDetailView retrofitted into the real Week/Wave editor (single active week, Week dropdown, wave-strip label)"
    - "ProgramsRepository.getWaveLabelInfo + waveLabelProvider"
    - "Per-exercise 'Replace this exercise' trigger reusing ExerciseReplacementSheet"
  affects:
    - "lib/features/programs/presentation/views/block_detail_view.dart"
    - "lib/features/programs/data/programs_repository.dart"
    - "lib/features/programs/application/programs_providers.dart"
tech-stack:
  added: []
  patterns:
    - "part/part-of split under a subfolder named after the file (block_detail_view/_week_card.part.dart, _day_row.part.dart), matching the profile_view/*.part.dart precedent"
    - "Riverpod record-typed FutureProvider.family key (WaveLabelArgs) for a four-argument family provider"
    - "Cached-provider-value-with-future-fallback read pattern for a one-off async read inside a button handler (ref.read(...).value ?? await ref.read(otherProvider.future))"
key-files:
  created:
    - lib/features/programs/presentation/views/block_detail_view/_week_card.part.dart
    - lib/features/programs/presentation/views/block_detail_view/_day_row.part.dart
    - test/block_detail_view_test.dart
  modified:
    - lib/features/programs/presentation/views/block_detail_view.dart
    - lib/features/programs/data/programs_repository.dart
    - lib/features/programs/application/programs_providers.dart
decisions:
  - "Week dropdown and wave-strip label live directly in _BlockDetailViewState.build() (new _WeekDropdown/_WaveStrip widgets in the main file), not inside the _week_card.part.dart part file — only the per-week card body (volume slider + day list) moved into the part, matching the plan's literal action text describing where each piece belongs."
  - "waveLabelProvider's family key is a Dart record typedef (WaveLabelArgs) rather than a positional tuple, for readability at both the read and ref.invalidate call sites."
  - "_replace's candidate lookup prefers the already-resolved exerciseCatalogProvider cache and falls back to awaiting exerciseCatalogSnapshotProvider.future — the naive ref.read(...).value-only approach silently no-ops when nothing has subscribed to the catalog snapshot yet (a real race, not just a test artifact)."
requirements-completed: [EDIT-01, EDIT-02, EDIT-03, EDIT-04]
metrics:
  duration: "~3h (dominated by widget-test timing diagnostics against drift customSelect streams and showModalBottomSheet transitions)"
  completed: "2026-09-16"
---

# Phase 19 Plan 04: Program Wave Editor Retrofit Summary

Retrofitted `block_detail_view.dart` into the real Week/Wave editor: a single active week behind a "Week N of M" dropdown, a distinct "Exercise wave X of Y · Weeks A–B" caption beneath it, and a per-exercise "Replace this exercise" trigger that opens the shared `ExerciseReplacementSheet` and reaches only future materialized sessions.

## What Was Built

**D-01 — Single active week behind a dropdown.** `BlockDetailView` is now a `ConsumerStatefulWidget` holding `_selectedWeekIndex`. The old `for (final week in list) _WeekCard(...)` loop (rendering every week's card in a scrollable stack) is gone, replaced by one `_WeekCard` call for `list.firstWhere((w) => w.weekIndex == _selectedWeekIndex, orElse: () => list.first)`, preceded by a new `_WeekDropdown` widget whose items read `'Week ${i + 1} of $weekCount'`.

**D-05 — Wave-strip label.** `ProgramsRepository.getWaveLabelInfo({programId, programWeekId, weekIndex, totalWeeks})` resolves the week's anchor `main` slot via `WaveLabel.selectAnchorSlot` (Plan 19-01), builds a `weekIndex -> exerciseId` map from that slot's `RotationAssignments`, and calls `WaveLabel.compute` to derive the wave. `waveLabelProvider` (a `FutureProvider.family` keyed on the `WaveLabelArgs` record) exposes this to a new `_WaveStrip` widget, rendered as a `Text` fully separate from `_WeekDropdown`'s own `Text` — verified in the widget test by comparing the two rendered strings directly, not just their presence.

**D-04 — Per-exercise replacement.** `ProgramDayExerciseSummary` gained `id`/`exerciseId` fields (the only construction site updated). `_DayRow` (now in `_day_row.part.dart`, receiving `week`/`totalWeeks` in addition to its existing `program`/`day`) renders a "Replace this exercise" `IconButton` per exercise row. Its handler resolves `current` from the tapped summary's `exerciseId`, opens `ExerciseReplacementSheet` (Plan 19-02) with the full catalog as candidates, and on a non-null selection calls `replaceProgramExerciseSlot` then `rematerializeProgram` (default `futureOnly: true`), followed by `ref.invalidate(waveLabelProvider(...))` so a replacement landing on the anchor slot never leaves a stale wave-strip reading.

**D-03 — Day-level link unaffected.** The pre-existing "Link a template" icon/handler moved into `_day_row.part.dart` verbatim; both icons are simultaneously present on a day with a linked template and populated exercises.

**Structure.** `block_detail_view.dart` is 461 lines (was 710), split via `part`/`part of` into `block_detail_view/_week_card.part.dart` and `block_detail_view/_day_row.part.dart`, both under `dart run tool/check_structure.dart`'s exemption for `*.part.dart` files (same precedent as `profile_view/*.part.dart`).

## Task Commits

1. **Task 1: Split block_detail_view.dart; Week dropdown + wave-strip for a single active week** — `47a521e` (feat)
2. **Task 2: Per-exercise replacement trigger wired to the extracted sheet, plus rematerialize (D-04)** — `556d5c0` (feat)

Both tasks' implementation and their shared `test/block_detail_view_test.dart` were built as one coordinated pass per RESEARCH.md Pitfall 1 (the plan's own objective explicitly calls for this, not a mechanical split followed by a separate feature pass); the two commits above separate the diff along the plan's task boundaries as closely as the single shared file allowed.

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 1 - Bug] `_replace`'s catalog-candidate read could silently no-op on a cold read**
- **Found during:** Task 2, widget-test diagnosis
- **Issue:** The plan's action text specifies `ref.read(exerciseCatalogProvider(const ExerciseCatalogFilter())).value ?? const []` for candidates. When nothing in the widget tree has yet subscribed to `exerciseCatalogSnapshotProvider` (the underlying `StreamProvider` it derives from), that read returns `AsyncLoading` and `.value` is `null`, so `candidates` becomes `[]`, `current` resolves to `null`, and the handler returns without ever opening the sheet — a real race, reproduced concretely in the widget test and not merely a test-harness artifact (a user's very first tap in a fresh session could hit the same window).
- **Fix:** Fall back to `await ref.read(exerciseCatalogSnapshotProvider.future)` when the cached value is `null`, which properly awaits the stream's first emission regardless of subscription timing.
- **Files modified:** `lib/features/programs/presentation/views/block_detail_view/_day_row.part.dart`
- **Commit:** `556d5c0`

### Notable test-infrastructure findings (not production bugs)

- `ProgramsRepository.watchDayExerciseSummaries` (a `customSelect('SELECT 1', readsFrom: {...}).watch().asyncMap(...)` stream, unmodified by this plan) does not reliably deliver its first emission to a widget test within a single `tester.pump()`/`pump(duration)` cycle — `tester.runAsync(() => Future.delayed(...))` around an additional `pump()` cycle was needed after the underlying `_DayRow` widgets first mount. This is a pre-existing characteristic of this stream shape (also present in `watchProgramTracking`), not something introduced by this plan; no prior widget test in the repo exercised a `customSelect`-based `StreamProvider` via `ref.watch` + `pump()` to have surfaced it before.
- The seeded test database already carries the full production exercise catalog (400+ rows) via migration, so a freshly-inserted test exercise can rank far down `ExerciseSubstitution.getRankedSubstitutes`' lazily-built `ListView` and never mount. The two interactive replacement tests search the sheet's text field for the candidate's exact name before tapping it, matching how a real user would locate a specific replacement rather than scrolling a long ranked list.

## Verification

- `flutter test test/block_detail_view_test.dart` — 7/7 passing (all `<behavior>` cases from both tasks).
- `flutter test test/block_detail_view_test.dart test/program_exercise_replacement_scope_test.dart test/program_tracking_test.dart test/program_review_view_test.dart` — 19/19 passing (no regression in the pre-existing replacement/tracking/review coverage this plan's changes touch transitively).
- `flutter test` (full suite) — 1337 passed, 9 skipped, 0 failed.
- `flutter analyze` — 41 pre-existing issues, none in any file this plan touched (confirmed via targeted grep of the analyzer output).
- `dart run tool/check_structure.dart` — 58 pre-existing violations (baseline drift, unrelated); `block_detail_view.dart` (461 lines) and its two new part files are not among them.
- `grep -n "for (final week in list)"` over `block_detail_view.dart` and its part files — no match (all-weeks loop confirmed removed).
- `grep -c "Icons.link_rounded" .../_day_row.part.dart` — 1 (day-level link icon preserved).
- `grep -n "replaceProgramExerciseSlot" -A3 .../_day_row.part.dart` — shows `rematerializeProgram` on the next statement (D-04 two-call ordering, no `futureOnly: false`).
- `grep -n "waveLabelProvider" .../_day_row.part.dart` — shows `ref.invalidate(waveLabelProvider(` after the `rematerializeProgram` call.

## Known Stubs

None. No hardcoded empty/placeholder data was introduced.

## Threat Flags

None — this plan introduced no new network endpoints, auth paths, file access patterns, or schema changes, matching its own threat-model disposition (`accept`; the only new write path reuses the already-transactional `replaceProgramExerciseSlot` unchanged).

## Self-Check: PASSED

- `lib/features/programs/presentation/views/block_detail_view.dart` — FOUND (modified)
- `lib/features/programs/presentation/views/block_detail_view/_week_card.part.dart` — FOUND
- `lib/features/programs/presentation/views/block_detail_view/_day_row.part.dart` — FOUND
- `lib/features/programs/data/programs_repository.dart` — FOUND (modified)
- `lib/features/programs/application/programs_providers.dart` — FOUND (modified)
- `test/block_detail_view_test.dart` — FOUND
- Commit `47a521e` — FOUND in `git log`
- Commit `556d5c0` — FOUND in `git log`
