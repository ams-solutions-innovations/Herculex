---
phase: 19
plan: 02
subsystem: programs-presentation
tags: [refactor, extraction, exercise-replacement, wave-editor]
dependency-graph:
  requires: []
  provides:
    - "ExerciseReplacementSheet (public widget at lib/features/programs/presentation/sheets/exercise_replacement_sheet.dart)"
    - "ExerciseReplacementSelection (result type, same file)"
  affects:
    - "lib/features/programs/presentation/views/program_review_view.dart"
    - "Plan 19-04's post-commit editor (future import site)"
tech-stack:
  added: []
  patterns:
    - "presentation/sheets/ directory convention for shared bottom-sheet widgets (matches existing template_picker_sheet.dart precedent)"
key-files:
  created:
    - lib/features/programs/presentation/sheets/exercise_replacement_sheet.dart
  modified:
    - lib/features/programs/presentation/views/program_review_view.dart
    - test/widgets/exercise_replacement_sheet_test.dart
    - test/program_review_view_test.dart
decisions:
  - "Kept AppColors.* usage verbatim in the extracted file rather than switching to context.hx, per executor discretion noted in the plan (no existing convention in a brand-new file to preserve either way; verbatim minimizes review surface)."
metrics:
  duration: "~25 minutes"
  completed: "2026-09-16"
---

# Phase 19 Plan 02: Extract ExerciseReplacementSheet Summary

Moved `ExerciseReplacementSheet` (plus its `_ExerciseReplacementSheetState`, `ExerciseReplacementSelection` result type, and `_ScopeChoice` helper) out of `program_review_view.dart` into a new standalone file at `lib/features/programs/presentation/sheets/exercise_replacement_sheet.dart`, verbatim, so the pre-commit review screen and Plan 19-04's future post-commit editor share one scope-picker implementation.

## What Was Built

**Task 1 — Extract into new file.** Created `lib/features/programs/presentation/sheets/exercise_replacement_sheet.dart` containing the four moved declarations, byte-identical in body (same `ChoiceChip` scope labels, same `HxSheet` title/subtitle, same search/ranking logic, same doc comment). The new file's import block was built from scratch to include only what the moved code needs: `flutter/material.dart`, `flutter_riverpod/flutter_riverpod.dart`, `herculex/data/local/database.dart` (`ExerciseCatalogData`), `herculex/design_system/components/components.dart` (`HxSheet`), `herculex/design_system/components/premium_text_field.dart`, `herculex/design_system/theme/colors.dart`, `herculex/features/programs/data/programs_repository.dart` (`ProgramExerciseReplacementScope`), `herculex/features/workouts/application/workouts_providers.dart` (`recentExerciseIdsProvider`), `herculex/features/workouts/domain/exercise_substitution.dart` (`ExerciseSubstitution.getRankedSubstitutes`). `flutter analyze` on the new file alone: 0 issues.

**Task 2 — Repoint call site and tests.** Deleted the four declarations from `program_review_view.dart` and added the new sheet import. Removed two imports that became unused as a direct result (`design_system/components/premium_text_field.dart` and `features/programs/data/programs_repository.dart`), while re-confirming `design_system/components/components.dart` (needed for `HxScreenShell`, still used by the remaining view code) and `features/workouts/presentation/widgets/exercise_artwork.dart` stayed. The `showModalBottomSheet<ExerciseReplacementSelection>(...)` call site in `_chooseReplacement` was left untouched — it already referenced `ExerciseReplacementSheet`/`ExerciseReplacementSelection` by name and needed no code change beyond the new import resolving those names.

Updated `test/widgets/exercise_replacement_sheet_test.dart` to import `ExerciseReplacementSheet` from the new sheet path instead of via `program_review_view.dart`. Updated `test/program_review_view_test.dart` to add the new sheet import alongside its existing `program_review_view.dart` import (the latter is still needed for `ProgramReviewView` itself).

`program_review_view.dart` shrank from 974 to 705 lines.

## Verification

- `flutter analyze lib/features/programs/presentation/sheets/exercise_replacement_sheet.dart`: 0 issues.
- `flutter analyze lib/features/programs/presentation/views/program_review_view.dart`: 0 issues (one `unused_import` warning surfaced mid-task for `programs_repository.dart` and was removed before commit).
- `grep -c "class ExerciseReplacementSheet" lib/features/programs/presentation/views/program_review_view.dart`: 0.
- `flutter test test/widgets/exercise_replacement_sheet_test.dart test/program_review_view_test.dart`: 10/10 passing.
- Full-repo `flutter analyze`: 40 pre-existing issues remain, none in the two files this plan touched (confirmed via targeted grep of the analyzer output) — all are unrelated, out-of-scope warnings/infos in other files (`smart_substitution_sheet.dart`, `circuit_builder_view.dart`, `template_builder_view.dart`, `exercise_analytics_cards.dart`, and a handful of test files with unused imports/locals). Not fixed per scope-boundary rule.

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 3 - Blocking] Removed `programs_repository.dart` import from `program_review_view.dart` after it became unused**
- **Found during:** Task 2, post-edit `flutter analyze`
- **Issue:** After deleting the four moved declarations, `program_review_view.dart` no longer referenced `ProgramExerciseReplacementScope` directly (it's still used inside `_chooseReplacement` only via the `selection.scope` field access, which doesn't require the type import), leaving the import dangling and triggering an `unused_import` warning — which counts as a `flutter analyze` error condition per this project's zero-warnings gate (CLAUDE.md: "exits 1 on warnings as well as errors").
- **Fix:** Removed the import; re-verified with `flutter analyze` that the remainder of the file resolves cleanly and all types it does use (`AppColors`, `HxScreenShell`, `PremiumButton`, `ExerciseArtwork`, `EmptySlotNotice`) still come from their existing imports.
- **Files modified:** `lib/features/programs/presentation/views/program_review_view.dart`
- **Commit:** d5231a0

None of the other deviation rules applied — this was a straightforward verbatim file move with one follow-on import cleanup.

## Known Stubs

None. No hardcoded empty/placeholder data was introduced.

## Threat Flags

None — this plan introduced no new network endpoints, auth paths, file access patterns, or schema changes. Matches the plan's own threat-model disposition (`accept`, verbatim extraction of already-reviewed UI).

## Self-Check: PASSED

- `lib/features/programs/presentation/sheets/exercise_replacement_sheet.dart` — FOUND
- `lib/features/programs/presentation/views/program_review_view.dart` — FOUND (modified)
- `test/widgets/exercise_replacement_sheet_test.dart` — FOUND (modified)
- `test/program_review_view_test.dart` — FOUND (modified)
- Commit `f138af2` (Task 1) — FOUND in `git log`
- Commit `d5231a0` (Task 2) — FOUND in `git log`
