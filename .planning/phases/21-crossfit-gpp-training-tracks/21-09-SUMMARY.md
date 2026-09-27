---
phase: 21-crossfit-gpp-training-tracks
plan: 09
subsystem: ui
tags: [flutter, drift, crossfit, program-review, slot-prescription-codec]

# Dependency graph
requires:
  - phase: 21-crossfit-gpp-training-tracks
    provides: "SlotPrescriptionCodec/SlotPrescription/WorkSegment (plan 21-01 onward) and the metcon prescriptionCodecJson written by smart_program_planner.dart (plan 21-06)"
provides:
  - "program_review_view.dart's _ExerciseRow decodes prescriptionCodecJson for metcon rows and renders the real AMRAP/EMOM/For-Time summary instead of the placeholder"
affects: [phase-21-verification, program-review-ui]

# Tech tracking
tech-stack:
  added: []
  patterns:
    - "Decode-with-fallback: SlotPrescriptionCodec.decode never throws; UI treats a null/failed decode as 'render the pre-existing placeholder', never a crash or blank state"

key-files:
  created: []
  modified:
    - lib/features/programs/presentation/views/program_review_view.dart
    - test/program_review_view_test.dart

key-decisions:
  - "Used package:collection's firstOrNull for the decoded segment list rather than a manual isEmpty check, since collection was already a project dependency and the codebase's own session_segment.dart already relies on it for the analogous firstWhereOrNull pattern"
  - "Wrote the new metcon test with an inline programDayExercises insert rather than threading a new optional parameter through seedProgram(), since the metcon row's shape (sessionSegment, prescriptionCodecJson) diverges enough from seedProgram()'s existing filled/empty-slot shape that reusing it would have added conditional branches to a helper whose current two call sites don't need them"

patterns-established:
  - "Segment-typed subtitle rendering: _ExerciseRow gates its subtitle computation on item.row.sessionSegment == SessionSegment.metcon.id, keeping non-metcon rendering byte-for-byte identical to before this plan"

requirements-completed: [CF-01]

# Metrics
duration: 25min
completed: 2026-09-27
---

# Phase 21 Plan 09: Real Metcon Prescription in Program Review Summary

**Program review's `_ExerciseRow` now decodes `prescriptionCodecJson` via `SlotPrescriptionCodec` for CrossFit metcon rows and renders "AMRAP 7:30" / "EMOM 12 min" / "For Time, cap 9:00" instead of the meaningless "1 sets · 1 reps" placeholder.**

## Performance

- **Duration:** 25 min
- **Started:** 2026-09-27T12:46:00Z
- **Completed:** 2026-09-27T13:11:00Z
- **Tasks:** 2 completed
- **Files modified:** 2

## Accomplishments
- `_ExerciseRow` decodes `prescriptionCodecJson` for `sessionSegment == 'metcon'` rows and renders a real one-line AMRAP/EMOM/For-Time summary with cap/minutes formatting (`_metconSummary`/`_formatCap` helpers)
- Non-metcon rows and metcon rows whose decode fails are rendered byte-for-byte identically to before this plan (fallback to the existing `'$targetSets sets · $reps'` text)
- New widget test seeds a metcon `programDayExercises` row with a real encoded AMRAP prescription and proves both that "AMRAP" renders and that the placeholder text "1 sets" is absent

## Task Commits

Each task was committed atomically:

1. **Task 1: Decode and render the real metcon prescription in _ExerciseRow** - `5036b89` (feat)
2. **Task 2: Widget test proving the real metcon summary replaces the placeholder** - `861c386` (test)

**Plan metadata:** (this commit, following SUMMARY.md creation)

## Files Created/Modified
- `lib/features/programs/presentation/views/program_review_view.dart` - `_ExerciseRow` now computes `isMetcon`/`metconSegment` from `SlotPrescriptionCodec.decode`, and the subtitle `Text` renders `_metconSummary(metconSegment)` for decodable metcon rows; new top-level `_metconSummary`/`_formatCap` helpers
- `test/program_review_view_test.dart` - new test in the `'ProgramReviewView empty-slot notices'` group seeding a metcon row with an encoded AMRAP prescription (`capSeconds: 450`) and asserting "AMRAP" renders while "1 sets" does not

## Decisions Made
- Used `firstOrNull` from the already-present `collection` package for `segments.firstOrNull` rather than a manual empty check
- Wrote the metcon test's seed data inline instead of extending `seedProgram()`, since the metcon shape doesn't share enough structure with the existing empty/filled-slot fixture to justify a new optional parameter

## Deviations from Plan

None - plan executed exactly as written.

## Issues Encountered
None.

## User Setup Required
None - no external service configuration required.

## Next Phase Readiness
Phase 21's second and final gap-closure item (CF-01, the program-review metcon display gap from VERIFICATION.md) is now closed. Both 21-08 (complexityCheck wiring) and 21-09 (this plan) are complete — Phase 21 is 9/9 plans done and ready for re-verification.

---
*Phase: 21-crossfit-gpp-training-tracks*
*Completed: 2026-09-27*

## Self-Check: PASSED

All modified files and both task commits (`5036b89`, `861c386`) verified present.
