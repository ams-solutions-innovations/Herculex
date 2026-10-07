---
phase: 23-persistent-dream-physique-multi-phase-nutrition
plan: 13
subsystem: ui
tags: [flutter, riverpod, physique, sheets, dialogs, roadmap-editor, accessibility]

requires:
  - phase: 23-06
    provides: PhysiqueRoadmapRepository.replaceRoadmap
  - phase: 23-10
    provides: PhysiqueText, PhaseTypePill, RestrictionNoticeList, VerdictChip, VerdictBlock
  - phase: 23-11
    provides: physique providers (goal, phases, check-ins, photos, eligibility)
provides:
  - RoadmapEditorSheet (reorder, resize 2-52, add, remove with Undo, reset, accept/save)
  - physiqueRoadmapSuggestionProvider(goalId)
  - CheckInHistorySheet (list, detail, confirmed delete), PastGoalsSheet
  - PhotoThumbnail, SheetSnackBarScope
  - Reset, discard, delete-check-in, start-new-goal, no-face-found dialogs
  - GoalDisplayCopy shared legacy-goal copy helper
affects: [23-16 progress view composition, add check-in flow, start-new-goal save path]

tech-stack:
  added: []
  patterns:
    - "Sheets own a ScaffoldMessenger (SheetSnackBarScope) so snackbar actions are reachable above the modal barrier"
    - "Reorder exposed as Move up / Move down custom semantics actions as well as drag"

key-files:
  created:
    - lib/features/physique/domain/goal_display_copy.dart
    - lib/features/physique/application/physique_roadmap_suggestion_provider.dart
    - lib/features/physique/presentation/sheets/roadmap_editor_sheet.dart
    - lib/features/physique/presentation/sheets/check_in_history_sheet.dart
    - lib/features/physique/presentation/sheets/past_goals_sheet.dart
    - lib/features/physique/presentation/dialogs/reset_roadmap_dialog.dart
    - lib/features/physique/presentation/dialogs/discard_changes_dialog.dart
    - lib/features/physique/presentation/dialogs/delete_check_in_dialog.dart
    - lib/features/physique/presentation/dialogs/start_new_goal_dialog.dart
    - lib/features/physique/presentation/dialogs/no_face_found_dialog.dart
    - lib/features/physique/presentation/widgets/photo_thumbnail.dart
    - lib/features/physique/presentation/widgets/sheet_snackbar_scope.dart
    - test/features/physique/goal_display_copy_test.dart
    - test/features/physique/presentation/roadmap_editor_sheet_test.dart
    - test/features/physique/presentation/physique_sheets_dialogs_test.dart
  modified: []

key-decisions:
  - "Roadmap saves go only through replaceRoadmap; no nutrition import anywhere under presentation/"
  - "With no usable start weight the editor skips retarget, saves drafts as-is and disables Add phase"
  - "Draft rows are keyed by ObjectKey of the draft instance, so reorder keeps identity"

patterns-established:
  - "SheetSnackBarScope: ScaffoldMessenger + transparent Scaffold + tap-outside forwarding to maybePop"

requirements-completed: []

duration: 75min
completed: 2026-10-02
---

# Phase 23 Plan 13: Roadmap editor, history, past goals and dialogs Summary

**Roadmap editor sheet (reorder/resize/add/remove/reset/accept without ever writing calories), check-in history with confirmed delete that leaves the 7-day cap intact, read-only past goals through a shared legacy-goal copy helper, a graceful photo thumbnail and five confirmation dialogs.**

## Accomplishments
- RoadmapEditorSheet edits the non-done phases through `RoadmapDraftEditor` only; restricted phases are disabled in the picker with the reason notice; dirty dismiss asks "Discard changes?"; CTA reads Accept roadmap or Save roadmap.
- Legacy goals (no start weight, no target) cannot crash or corrupt the roadmap: retarget is skipped, Add phase disabled with explanatory label, "Reset to suggestion" hidden.
- CheckInHistorySheet: newest first, detail with VerdictBlock, delete only for an active goal; the file is removed and `physiqueLastCheckInAtProvider` is unchanged (tested against a real in-memory database).
- PastGoalsSheet and GoalDisplayCopy: photos-only goals show "Imported progress photos" and no Target line.
- PhotoThumbnail resolves through `PhysiquePhotoStore`; missing, empty and traversal paths show "Photo unavailable".

## Task Commits
1. Task 1: suggestion provider, roadmap editor, reset/discard dialogs, GoalDisplayCopy - `5102468`
2. Task 2: thumbnail, history, past goals, delete/new-goal/no-face dialogs, SheetSnackBarScope - `4bdd11c`

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 1 - Bug] Snackbar "Undo" unreachable behind the modal barrier**
- **Found during:** Task 1 (Undo test)
- **Issue:** A SnackBar shown on the page scaffold sits under the modal route barrier; Undo could not be tapped.
- **Fix:** New `SheetSnackBarScope` gives the sheet its own ScaffoldMessenger and a transparent Scaffold; because that scaffold covers the barrier, the area above the sheet forwards taps to `Navigator.maybePop` so tap-outside and the dirty-dismiss dialog still work. Used by the roadmap editor and history sheet.
- **Files:** widgets/sheet_snackbar_scope.dart (not in the plan's file list)
- **Commits:** 5102468, 4bdd11c

### Planner-added copy (flagged)
- "Add your weight in Profile to add phases." (as specified in the plan).
- "We couldn't save your roadmap. Try again." SnackBar when `replaceRoadmap` throws (added; plan had no save-failure copy).
- History detail back affordance reads "All check-ins"; list title "Check-ins", detail title "Check-in".

### Notes
- `ReorderableListView.onReorder` is deprecated in this Flutter; `onReorderItem` is used and its adjusted index is converted back to the editor's raw ReorderableListView convention.
- The framework adds its own Move up/down semantics on reorderable items; the explicit actions are kept so the contract is visible in the file.
- `physiqueRoadmapSuggestionProvider` uses the profile weight only (per plan); the sheet itself falls back to `goal.startWeightKg` for retargeting.
- Drift stream tests under `testWidgets`: the delete test uses `runAsync` and `addTearDown(db.close)`; closing inside the test body hangs.

## Verification
- `flutter test test/features/physique`: 365 passed
- `flutter analyze lib/features/physique test/features/physique`: no issues; `dart format` clean
- Greps: no nutrition repository/target/AppColors/Color(0x/Colors./boxShadow/legacy sheet references in `presentation/`; `danger` only in the delete and discard dialogs
- `dart run tool/check_structure.dart` names no `features/physique` file; largest new file 489 lines

## Known Stubs
None. Dialogs `StartNewGoalDialog` and `NoFaceFoundDialog` are not yet wired into the save and check-in flows; later plans (check-in sheet, progress view, save-path edit) own those call sites.

## Self-Check: PASSED
