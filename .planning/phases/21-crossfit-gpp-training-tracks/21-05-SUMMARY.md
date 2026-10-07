---
phase: 21-crossfit-gpp-training-tracks
plan: 05
subsystem: training-programs
tags: [flutter, dart, domain-service, tdd, crossfit, gpp]

# Dependency graph
requires:
  - phase: 21-crossfit-gpp-training-tracks
    provides: "CrossfitSlotNeed/SessionSegment descriptor (Plan 21-01)"
provides:
  - "GppProgramPlanner.segmentNeedsFor() -> List<CrossfitSlotNeed> for the GPP conditioning day"
  - "Regression test proving GppProgramPlanner output never resolves to a heavy (main/supplemental) SlotRole"
affects: ["21-06 (wires GppProgramPlanner into smart_program_planner.dart)"]

# Tech tracking
tech-stack:
  added: []
  patterns:
    - "abstract final class ... static List<CrossfitSlotNeed> segmentNeedsFor(...) pure-domain planner pattern (mirrors CrossfitProgramPlanner from Plan 21-04)"

key-files:
  created:
    - lib/features/programs/domain/gpp_program_planner.dart
    - test/features/programs/gpp_program_planner_test.dart
  modified: []

key-decisions:
  - "GPP day shape resolved as standalone 3rd training day, matching the already-shipped SplitType.fullBodyAbGpp skeleton, not a shorter Full Body A/B addition"
  - "GPP/Dynamic-Effort guard resolved as: existing role.isHeavy-gated structural exclude in smart_program_planner.dart is primary and already correct; GppProgramPlanner keeps it closed by construction by never emitting a heavy role; SlotRoleEligibility.derive's isTimed/cardio-only conditioning gate is the secondary, already-sufficient content restriction"
  - "4-exercise gpp pool ships as-is this phase (not widened to the 17-exercise crossfit pool), documented as a known content-curation limitation"
  - "Full end-to-end 'populate() never emits dynamicEffort for a GPP day' regression deferred explicitly to Plan 21-06, where the smart_program_planner.dart wiring exists to exercise it"

patterns-established:
  - "Segment-tagged CrossfitSlotNeed planners stay pure domain (no catalog/DB dependency), returning descriptors consumed by a later wiring plan"

requirements-completed: [CF-03]

# Metrics
duration: 12min
completed: 2026-09-26
---

# Phase 21 Plan 05: GppProgramPlanner Summary

**Pure-domain `GppProgramPlanner.segmentNeedsFor()` formalizing the GPP conditioning day into a single `SlotRole.conditioning`/`SessionSegment.metcon` need, with a regression test locking the never-heavy-role invariant that keeps the existing Dynamic-Effort guard structurally closed.**

## Performance

- **Duration:** 12 min
- **Started:** 2026-09-26T00:00:00Z (approx, session-relative)
- **Completed:** 2026-09-26
- **Tasks:** 1 (TDD RED/GREEN)
- **Files modified:** 2 (1 created source, 1 created test)

## Accomplishments
- Implemented `GppProgramPlanner.segmentNeedsFor()` in `lib/features/programs/domain/gpp_program_planner.dart`, returning exactly one `CrossfitSlotNeed(role: SlotRole.conditioning, segment: SessionSegment.metcon)`.
- Documented both resolved CONTEXT.md discretion items directly in the class doc comment: GPP day shape (standalone 3rd day matching `SplitType.fullBodyAbGpp`) and the GPP/Dynamic-Effort guard mechanism (existing `role.isHeavy` exclude is primary; `SlotRoleEligibility`'s isTimed/cardio-only gate is secondary).
- Added `test/features/programs/gpp_program_planner_test.dart` with 4 tests: single-need shape, never-heavy-role assertion, no-extraneous-segments assertion, and a standalone `SlotRoleEligibility` derivation test proving conditioning eligibility for a synthetic cardio/timed exercise while the planner itself never emits main/supplemental.
- Followed TDD RED/GREEN: test committed first against the non-existent class (compile-failure RED), then the implementation committed to turn it GREEN.

## Task Commits

Each task was committed atomically (TDD RED then GREEN):

1. **Task 1 (RED): failing test for GppProgramPlanner.segmentNeedsFor** - `5402e0d` (test)
2. **Task 1 (GREEN): implement GppProgramPlanner.segmentNeedsFor** - `395bd0e` (feat)

**Plan metadata:** commit pending (this SUMMARY + STATE/ROADMAP update)

## Files Created/Modified
- `lib/features/programs/domain/gpp_program_planner.dart` - Pure domain service; `segmentNeedsFor()` returns the single conditioning/metcon need for a GPP day; doc comments record both resolved discretion items and the known 4-exercise pool limitation.
- `test/features/programs/gpp_program_planner_test.dart` - 4 tests covering output shape, never-heavy-role invariant, segment narrowness, and `SlotRoleEligibility` interaction; notes the full end-to-end DE regression is deferred to Plan 21-06.

## Decisions Made
- GPP day shape: standalone 3rd day (matches shipped `SplitType.fullBodyAbGpp` skeleton), not appended to Full Body A/B.
- DE guard: rely on existing `role.isHeavy` exclude as primary mechanism; this planner's contribution is structural (never emit a heavy role), not a new filter.
- Kept the 4-exercise gpp pool as-is, flagged as a known limitation rather than silently widened or ignored.
- Deferred the full `populate()`-level DE regression test to Plan 21-06 (wiring doesn't exist yet in this plan's scope).

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 1 - Bug] Reworded doc comment to avoid literal `SlotRole.main` token**
- **Found during:** Task 1 (acceptance criteria check)
- **Issue:** Initial doc comment in `gpp_program_planner.dart` used the literal string `SlotRole.main`/`.supplemental` while explaining the DE-guard mechanism, which would have failed the plan's automated `<source>` acceptance check ("gpp_program_planner.dart contains no `SlotRole.main` or `SlotRole.supplemental` token anywhere").
- **Fix:** Reworded the doc comment to describe "the two heaviest roles" instead of naming them literally, preserving the same explanation without the forbidden tokens.
- **Files modified:** `lib/features/programs/domain/gpp_program_planner.dart`
- **Verification:** `grep -n "SlotRole.main\|SlotRole.supplemental" lib/features/programs/domain/gpp_program_planner.dart` returns no matches; tests still pass; `flutter analyze` still 0 errors.
- **Committed in:** `395bd0e` (part of Task 1 GREEN commit)

---

**Total deviations:** 1 auto-fixed (1 bug/acceptance-criteria fix)
**Impact on plan:** Cosmetic doc-comment wording change only; no behavior change. No scope creep.

## Issues Encountered
None.

## User Setup Required
None - no external service configuration required.

## Next Phase Readiness
- `GppProgramPlanner.segmentNeedsFor()` is ready for Plan 21-06 to wire into `smart_program_planner.dart`'s `_needsFor` dispatch, replacing the current inline `[_SlotNeed(null, null, SlotRole.conditioning)]` gpp branch.
- The full end-to-end "`populate()` never emits `dynamicEffort` for a GPP day" regression test is explicitly deferred to Plan 21-06, where the wiring exists to exercise it — not silently dropped.
- No blockers.

---
*Phase: 21-crossfit-gpp-training-tracks*
*Completed: 2026-09-26*

## Self-Check: PASSED

- FOUND: lib/features/programs/domain/gpp_program_planner.dart
- FOUND: test/features/programs/gpp_program_planner_test.dart
- FOUND commit: 5402e0d
- FOUND commit: 395bd0e
