---
phase: 23-persistent-dream-physique-multi-phase-nutrition
plan: 14
subsystem: ui
tags: [flutter, riverpod, physique, check-in, consent, image-picker, camera-resume]

requires:
  - phase: 23-08
    provides: PhysiquePhotoSanitizer, StagedPhoto, PhysiquePrivacyPreferences
  - phase: 23-10
    provides: PhysiqueText, VerdictBlock
  - phase: 23-11
    provides: PhysiqueCheckInFlow, physique providers
  - phase: 23-13
    provides: NoFaceFoundDialog, SheetSnackBarScope
provides:
  - CheckInSheet.show(context, goal, resumed?) with pose, privacy, consent, analyse, result and baseline modes
  - AiScanContextType.physiqueCheckin plus main_scaffold resume case
  - ResumedCapture, physiqueResumedCaptureProvider, physiqueCheckInContextProvider, LegacyMigrationNotice
  - One-time legacy migration SnackBar in main_scaffold
affects: [23-16 progress view (entry button, reads physiqueResumedCaptureProvider), 23-17 consent legal-review note]

tech-stack:
  added: []
  patterns:
    - "Set PendingAiScanContext before pick, clear in finally; null file is cancel"
    - "Sheet sequences UI only; stage/analyse/persist stay in PhysiqueCheckInFlow"
    - "Outer ScaffoldMessenger captured at show() so confirmations outlive the sheet"

key-files:
  created:
    - lib/features/physique/application/physique_capture_providers.dart
    - lib/features/physique/presentation/sheets/check_in_sheet.dart
    - lib/features/physique/presentation/sheets/check_in_sheet/_steps.part.dart
    - test/features/physique/physique_capture_providers_test.dart
    - test/features/physique/presentation/check_in_sheet_test.dart
  modified:
    - lib/services/ai/pending_ai_scan_service.dart
    - lib/features/shell/main_scaffold.dart

key-decisions:
  - "Consent body lives in one constant (CheckInSheet._consentBody), marked DRAFT pending legal review"
  - "Baseline mode is derived from the photos stream (no role == baseline row), not passed in"
  - "Staged file is discarded in dispose() on any exit that did not persist it (T-23-72)"
  - "invalidInput AI failures show the flow's own message; quota and other failures use UI-SPEC copy"

patterns-established:
  - "Tests for flows using Isolate.run poll with tester.runAsync + pump instead of pumpAndSettle"

requirements-completed: []

duration: ~75min
completed: 2026-10-02
---

# Phase 23 Plan 14: Check-in Sheet Summary

**Check-in sheet that sanitises before anything else, gates AI upload on versioned consent, never claims unperformed blur, persists before showing the verdict, and resumes after Android kills the camera activity.**

## Performance

- **Tasks:** 2/2
- **Files:** 5 created, 2 modified

## Accomplishments

- `AiScanContextType.physiqueCheckin` added (appended, JSON of old contexts unchanged) with the matching `main_scaffold` switch case in the same commit, so the exhaustive switch still compiles. The case stores a `ResumedCapture` and pushes `AppPaths.dreamPhysiqueProgress(goalId:)`.
- `main_scaffold` shows the legacy-migration outcome once per session as a floating SnackBar (diff +28 lines).
- `CheckInSheet`: pose pills, Take photo / Choose from library, blur toggle (defaults to last used), always-on privacy line, consent step only until the version is accepted, "Save photo without analysis", error views (AI unavailable, quota, unreadable, storage), result via `VerdictBlock`, baseline mode (2 steps, no cap, no AI), cap-race SnackBar with the next date, `PopScope` blocking dismissal mid-analysis with "Hang on, almost done".
- 26 new tests (10 provider tests, 16 sheet tests incl. 320 dp / 2.0 text scale and a dark smoke test). All 391 tests under `test/features/physique` pass.

## Task Commits

1. **Task 1: physiqueCheckin context, capture providers, migration notice, main_scaffold wiring** - `778fe43`
2. **Task 2: CheckInSheet** - `965bb15`

## Deviations from Plan

None - plan executed as written. Notes:

- The plan's behaviour bullet "Retake or any error path calls discardStaged" is implemented as retake/cap-race/dispose discards; staging-failure paths hold no staged file.
- The pending-context assertion in tests reads the raw preference value because `PendingAiScanContext.isExpired` uses the real `DateTime.now()` while the test clock is fixed.

## Issues Encountered

- Windows keeps the decoded fixture JPEG open after `Image.file`, so test temp-dir cleanup tolerates `FileSystemException`.
- `flutter analyze lib test` reports 0 errors. `dart run tool/check_structure.dart` lists 57 pre-existing violations; none name `features/physique` or `main_scaffold.dart`.

## Known Stubs

None. Entry into the sheet (button, cap state, reading `physiqueResumedCaptureProvider` on the progress view) is Plan 16.

## Threat Flags

None. All T-23-67..72 mitigations are implemented (consent gate, honest blur, sanitise-first, validated resume context, controls disabled while busy, staged-file cleanup). T-23-73 (draft consent copy) remains accepted; Plan 17 records the legal-review item.

## Self-Check: PASSED

All created files exist; commits 778fe43 and 965bb15 present.
