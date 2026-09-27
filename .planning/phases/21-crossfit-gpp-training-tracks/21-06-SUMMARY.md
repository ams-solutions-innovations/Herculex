---
phase: 21-crossfit-gpp-training-tracks
plan: 06
subsystem: programs
tags: [drift, program-generation, crossfit, gpp, slot-role, session-segment]

requires:
  - phase: 21-crossfit-gpp-training-tracks (21-01)
    provides: SessionSegment enum, CrossfitSlotNeed descriptor, sessionSegment/supersetGroup schema (v44)
  - phase: 21-crossfit-gpp-training-tracks (21-02)
    provides: CrossfitScalingPolicy (time caps, movement ceiling, recoveryReserveWarning)
  - phase: 21-crossfit-gpp-training-tracks (21-04)
    provides: CrossfitProgramPlanner.segmentNeedsFor
  - phase: 21-crossfit-gpp-training-tracks (21-05)
    provides: GppProgramPlanner.segmentNeedsFor
provides:
  - smart_program_planner.dart's _needsFor dispatches CrossFit/GPP days to the real domain planners instead of bare stub literals
  - Week-scoped slotCache/slotKey so CrossFit metcon format genuinely rotates per week
  - Categorical technique-override for every segment-tagged slot (closes RESEARCH.md Pitfall 2 / T-21-01)
  - sessionSegment/supersetGroup persisted end-to-end through populate()
  - Capped-segment duration estimation and trim-loop exclusion for metcon slots
  - recoveryReserveWarning surfaced through the existing ProgramSlotExplanations rationale channel
affects: [22-primary-lift-strength-specialization, program-editor, active-workout-shell]

tech-stack:
  added: []
  patterns:
    - "Domain-service dispatch at the _needsFor boundary: private _SlotNeed extended with a 1:1 mirror of the public CrossfitSlotNeed shape, mapped via a single _fromCrossfitNeed helper"
    - "Week-scoped cache/slotKey suffix (-w{weekIndex}) for any day whose needs are re-derived per week, gated by the same usesWeeklySegments predicate at both the cache-key and slotKey call sites"

key-files:
  created: []
  modified:
    - lib/features/programs/data/smart_program_planner.dart
    - test/features/programs/smart_program_planner_test.dart
    - test/crossfit_gpp_program_test.dart

key-decisions:
  - "Metcon slots bypass _timePlanFor entirely and construct their _TimePlan directly (setType from the rotated format, capSeconds/minutes in prescriptionCodecJson's meta), since a metcon's duration and prescription shape have nothing in common with the sets/reps model every other slot uses."
  - "supersetGroup is computed once per day in the pass-2 insert loop from a String->int counter keyed by metconGroupKey, not carried on _TimePlan — the grouping is a day-level insert-time concern, not a per-slot planning concern."
  - "recoveryReserveWarning's advisory string is appended to the first CrossFit/GPP day's first slot's existing ProgramSlotExplanations.rationale for that week, reusing Phase 17's rationale channel instead of adding new schema or a new UI surface."

requirements-completed: [CF-01, CF-02, CF-03]

duration: ~90min
completed: 2026-09-27
---

# Phase 21 Plan 06: CrossFit/GPP Planner Dispatch Summary

**Wires `CrossfitProgramPlanner` and `GppProgramPlanner` into `smart_program_planner.dart`'s `_needsFor` dispatch, replacing the bare 2-slot CrossFit stub and the inline GPP literal with real, segment-tagged, week-rotating, categorically-DE-safe generator output.**

## Performance

- **Duration:** ~90 min
- **Completed:** 2026-09-27
- **Tasks:** 2
- **Files modified:** 3 (1 production, 2 test)

## Accomplishments

- `_needsFor`'s `gpp` and `crossfit` branches now call `GppProgramPlanner.segmentNeedsFor()` / `CrossfitProgramPlanner.segmentNeedsFor(experience, variationSeed: weekIndex)` instead of returning bare `_SlotNeed` literals.
- `_SlotNeed`, `_ResolvedSmartSlot`, and `_TimePlan` extended with `segment`/`metconGroupKey`/`metconFormat`/`metconCapSeconds`/`metconMinutes` (source-compatible — every existing call site untouched).
- Every segment-tagged slot (CrossFit or GPP) is categorically forced to `SlotTrainingMethod.technique`, unconditionally, before any role/periodization/day-label override logic runs — closing RESEARCH.md's Pitfall 2 (T-21-01) regardless of which future codepath might otherwise reopen Dynamic-Effort eligibility.
- CrossFit/GPP days' `slotCache` key and `ProgramExerciseSlots.slotKey` are week-scoped (`-w{weekIndex}` suffix), so `CrossfitProgramPlanner`'s `variationSeed`-driven metcon format genuinely rotates AMRAP → EMOM → For Time across weeks instead of reusing week 1's cached blueprint forever.
- `sessionSegment` is written to both `ProgramExerciseSlots` and `ProgramDayExercises`; `supersetGroup` is written to `ProgramDayExercises` (one shared int per distinct `metconGroupKey`, assigned once per day).
- `_estimateSlotDuration` branches to `WorkoutDurationEstimator.estimateCappedSegment` for metcon slots (deriving `capSeconds` from `metconMinutes * 60` for the EMOM case), and the time-budget trim loop explicitly excludes `SessionSegment.metcon` from its trimmable/shrinkable filters.
- `CrossfitScalingPolicy.recoveryReserveWarning` runs once per week; any warning is appended to the first CrossFit/GPP day's first slot's existing `ProgramSlotExplanations.rationale` for that week.
- 4 new end-to-end regression tests close the Wave 0 gaps: CF-03's DE guard (both `maxEffort` and `linear` periodization), CF-01's segment ordering + shared `supersetGroup`, CF-01's 3-week AMRAP/EMOM/For-Time rotation, and the Full Body 2×+GPP integration shape.

## Task Commits

1. **Task 1: Extend structs, dispatch planners, write sessionSegment/supersetGroup, capped-duration branch** - `aad7102` (feat)
2. **Task 2: End-to-end regression tests** - `5c243fa` (test)
3. **Deviation fix: update pre-existing `crossfit_gpp_program_test.dart`** - `cc28105` (fix, Rule 1)

## Files Created/Modified

- `lib/features/programs/data/smart_program_planner.dart` — `_needsFor` dispatch, week-scoped cache/slotKey, categorical technique override, `_SlotNeed`/`_ResolvedSmartSlot`/`_TimePlan` extensions, metcon `_TimePlan` bypass, capped-duration branch, trim-loop exclusion, `sessionSegment`/`supersetGroup` inserts, `recoveryReserveWarning` wiring.
- `test/features/programs/smart_program_planner_test.dart` — new `CrossFit/GPP segment wiring (CF-01/CF-02/CF-03)` group (4 tests); `insertExercise` helper extended with `allowedTrainingStylesJson`/`loggingMetric`/`category` params.
- `test/crossfit_gpp_program_test.dart` — updated the pre-existing "novice CrossFit plan" test to assert the new segment-blueprint contract instead of the old bare-stub `SlotRole.conditioning`-only shape.

## Decisions Made

- Metcon slots bypass `_timePlanFor` entirely rather than threading a metcon branch through it — the sets/reps model `_timePlanFor` implements has no meaningful analog for AMRAP/EMOM/For Time.
- `supersetGroup` is computed at pass-2 insert time from a day-scoped `metconGroupKey -> int` counter, not stored on `_TimePlan` — it's a day-level insert concern, not a per-slot planning concern (matches the plan's own read_first instruction placement).
- The recovery-reserve warning reuses Phase 17's existing `ProgramSlotExplanations.rationale` channel via a targeted per-week `UPDATE`, rather than adding new schema or a new UI-facing field.

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 1 - Bug] Updated `test/crossfit_gpp_program_test.dart`'s now-outdated CrossFit assertion**
- **Found during:** Task 2 (full-suite regression run after wiring the new dispatch)
- **Issue:** A pre-existing test ("novice CrossFit plan remains conditioning-first and curated") asserted the *old* bare 2-slot stub's shape — every row `slotRole == SlotRole.conditioning`. This plan's entire purpose is replacing that stub with `CrossfitProgramPlanner`'s real warmup/skill/strength/metcon/cooldown blueprint (roles: accessory/supplemental, never conditioning), so the old assertion now fails by design, not by regression.
- **Fix:** Rewrote the assertion to check the new contract: every row is `accessory`/`supplemental` (never `main`/`conditioning`), `trainingMethod` is never `dynamic_effort`, and produced `sessionSegment` values are a valid subset of `{warmup, skill, strength, metcon, cooldown}` with `metcon` guaranteed present (warmup/skill/strength/cooldown are structural placeholders per D-03/D-04 and may legitimately stay empty against the real, thinly-curated catalog).
- **Files modified:** `test/crossfit_gpp_program_test.dart`
- **Verification:** `flutter test test/crossfit_gpp_program_test.dart` — 3/3 pass.
- **Committed in:** `cc28105`

---

**Total deviations:** 1 auto-fixed (1 bug/outdated-assertion fix)
**Impact on plan:** Necessary to keep the full suite accurately reflecting the new, intended behavior this plan ships. No scope creep — no other pre-existing file was touched.

## Issues Encountered

- The first draft of Task 2's Test 1 (GPP/DE-guard) used `ExperienceLevel.advanced` with `PeriodizationModel.maxEffort`, which threw `Bad state: Add at least three suitable variations...` from the *unrelated* Full Body A/B main-lift Max Effort rotation check (the synthetic fixture catalog only has one squat variation, and `maxEffortEligibility` defaults to null/ineligible). Switched the test to `ExperienceLevel.novice`, which sidesteps Max Effort selection entirely for the Full Body A/B days while still exercising the GPP day's DE guard under both periodization models — the guard is unconditional on `need.segment != null`, so it holds regardless of experience level.
- The full-suite run surfaced 7 pre-existing `test/schema_v25_test.dart`/`schema_v27_test.dart`/`schema_v28_test.dart`/`schema_v29_test.dart` failures (stale hardcoded `newVersion: 39` targets vs. the actual `schemaVersion 44`). These predate this plan (logged in `.planning/phases/21-crossfit-gpp-training-tracks/deferred-items.md` during 21-01) and are out of scope per the SCOPE BOUNDARY rule — not fixed here.

## User Setup Required

None - no external service configuration required.

## Next Phase Readiness

- CF-01/CF-02/CF-03 are now proven end-to-end through `populate()`, not just at the planner-unit level — Phase 21's remaining plan(s), if any, and Phase 22 (Primary Lift Strength Specialization) can build on a stable, tested `_needsFor` dispatch surface.
- Known content-curation limitation carried forward unchanged from 21-05: the 4-exercise `gpp`-tagged pool and the still-thin `crossfit`-tagged pool (34 metadata entries, fewer eligible at novice) mean warmup/skill/strength/cooldown segments can legitimately materialize empty for some experience/catalog combinations. This is a pre-existing, documented limitation, not a regression from this plan.
- `test/schema_v25_test.dart`/`schema_v27_test.dart`/`schema_v28_test.dart`/`schema_v29_test.dart` remain failing (pre-existing, stale v39 targets) — still deferred, still tracked in `deferred-items.md`.

---
*Phase: 21-crossfit-gpp-training-tracks*
*Completed: 2026-09-27*
