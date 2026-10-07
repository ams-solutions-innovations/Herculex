---
phase: 21-crossfit-gpp-training-tracks
plan: 04
subsystem: program-generator
tags: [crossfit, domain-service, dart, drift-independent, tdd]

# Dependency graph
requires:
  - phase: 21-crossfit-gpp-training-tracks (Plan 21-01)
    provides: SessionSegment enum and CrossfitSlotNeed descriptor (session_segment.dart)
  - phase: 21-crossfit-gpp-training-tracks (Plan 21-02)
    provides: CrossfitScalingPolicy.timeCapFor/.complexityCheck/.movementCeilingFor (crossfit_scaling_policy.dart)
provides:
  - CrossfitProgramPlanner.segmentNeedsFor(experience, variationSeed) -> List<CrossfitSlotNeed>
  - Deterministic warmup/skill/strength/metcon/cooldown segment ordering for a CrossFit training day
  - 3-format metcon rotation (AMRAP/EMOM/For Time) via variationSeed % 3
affects: [21-06 (wires segmentNeedsFor into smart_program_planner.dart's _needsFor dispatch)]

# Tech tracking
tech-stack:
  added: []
  patterns:
    - "Pure domain planner returning declarative descriptor lists (CrossfitSlotNeed), mirroring smart_program_planner.dart's private _SlotNeed shape, with no catalog/DB dependency"
    - "Format rotation via variationSeed % formats.length for deterministic weekly variation"

key-files:
  created:
    - lib/features/programs/domain/crossfit_program_planner.dart
    - test/features/programs/crossfit_program_planner_test.dart
  modified: []

key-decisions:
  - "Warmup and cooldown segments are structural placeholders with no pattern/muscle hint this phase (D-03/D-04) — no warmup content pool exists in the Phase 16 catalog, and curating one is out of this phase's architecture boundary"
  - "Strength segment uses SlotRole.supplemental (never .main); every other segment uses SlotRole.accessory, keeping the existing role.isHeavy-gated Dynamic-Effort guard closed to CrossFit content (T-21-03)"
  - "Metcon format rotates via variationSeed % 3 across [amrap, emom, forTime] so all three ROADMAP-named formats are genuinely reachable through normal week-over-week variation"

patterns-established:
  - "Segment-tagged slot-need descriptors (CrossfitSlotNeed) as the boundary type between pure segment-assembly planners and the existing candidate-selection pipeline (_createStableSlots)"

requirements-completed: [CF-01, CF-02]

# Metrics
duration: 25min
completed: 2026-09-26
---

# Phase 21 Plan 04: CrossfitProgramPlanner Summary

**CrossfitProgramPlanner.segmentNeedsFor assembles the D-01/D-02/D-03/D-04 warmup/skill/strength/metcon/cooldown segment blueprint for a CrossFit day, rotating deterministically across AMRAP/EMOM/For Time via variationSeed and never emitting SlotRole.main.**

## Performance

- **Duration:** 25 min
- **Started:** 2026-09-26T10:10:00Z
- **Completed:** 2026-09-26T10:35:39Z
- **Tasks:** 1
- **Files modified:** 2 (both created)

## Accomplishments
- Built `CrossfitProgramPlanner.segmentNeedsFor`, a pure domain service producing the correct ordered segment list (warmup, skill, strength, metcon x N, cooldown) for all three `ExperienceLevel`s, with skill and strength kept as two distinct segments per D-01/D-02.
- Metcon movement count and time cap are sourced exclusively from `CrossfitScalingPolicy.movementCeilingFor`/`.timeCapFor` — no hardcoded per-call duplication.
- Metcon format genuinely rotates across all three ROADMAP-named formats (AMRAP, EMOM, For Time) via `variationSeed % 3`, proven by tests at seeds 0/1/2/3 (3 wraps back to AMRAP).
- Verified via test that no returned need ever uses `SlotRole.main`, and exactly one `SlotRole.supplemental` assignment exists (the strength segment) — keeping the existing Dynamic-Effort guard intact (threat T-21-03).

## Task Commits

Each task was committed atomically (TDD RED/GREEN):

1. **Task 1: CrossfitProgramPlanner.segmentNeedsFor with 3-format rotation** - `ee7d0c6` (test, RED) → `22a8c27` (feat, GREEN)

**Plan metadata:** pending (this commit)

## Files Created/Modified
- `lib/features/programs/domain/crossfit_program_planner.dart` - `CrossfitProgramPlanner.segmentNeedsFor`, the pure segment-assembly domain service
- `test/features/programs/crossfit_program_planner_test.dart` - 7 behavior tests covering segment ordering, all 4 rotation seeds, role safety, shared metcon group fields, and the advanced-level 4-movement ceiling

## Decisions Made
- Warmup/cooldown carry no pattern/muscle hint this phase — explicit placeholder per D-03/D-04, documented in code comments, deferred content curation out of scope.
- Strength segment is the sole `SlotRole.supplemental` need; all others are `SlotRole.accessory`. No `SlotRole.main` is ever emitted.

## Deviations from Plan

None - plan executed exactly as written.

## Issues Encountered
None.

## User Setup Required

None - no external service configuration required.

## Next Phase Readiness
`segmentNeedsFor` is ready for Plan 21-06 to wire into `smart_program_planner.dart`'s `_needsFor` dispatch, replacing the current bare 2-slot CrossFit stub (lines 1227-1231). Candidate exercise resolution for each returned need still flows through the existing `_createStableSlots` eligibility/prerequisite pipeline, unmodified by this plan.

## TDD Gate Compliance

RED gate: `ee7d0c6` (test commit, confirmed compile-failure before implementation existed).
GREEN gate: `22a8c27` (feat commit, all 7 tests passing).
No REFACTOR commit was needed — implementation required no cleanup pass.

## Self-Check: PASSED

- FOUND: lib/features/programs/domain/crossfit_program_planner.dart
- FOUND: test/features/programs/crossfit_program_planner_test.dart
- FOUND: .planning/phases/21-crossfit-gpp-training-tracks/21-04-SUMMARY.md
- FOUND commit: ee7d0c6 (test, RED)
- FOUND commit: 22a8c27 (feat, GREEN)
- FOUND commit: 8931e83 (docs, plan metadata)

---
*Phase: 21-crossfit-gpp-training-tracks*
*Completed: 2026-09-26*
