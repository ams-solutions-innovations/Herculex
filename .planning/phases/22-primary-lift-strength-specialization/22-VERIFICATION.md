---
phase: 22-primary-lift-strength-specialization
verified: 2026-10-02T10:32:31Z
status: passed
score: 11/11 must-haves verified
overrides_applied: 0
---

# Phase 22: Primary Lift Strength Specialization Verification Report

**Phase Goal:** Enable specialized strength programs centered around a single target lift (e.g.
Squat) with sticking point transfer exercises and baseline volume maintenance.
**Verified:** 2026-10-02T10:32:31Z
**Status:** passed
**Re-verification:** No — initial verification

## Goal Achievement

### Observable Truths

Merged from ROADMAP.md Success Criteria and all 4 plans' `must_haves.truths` frontmatter.

| # | Truth | Status | Evidence |
|---|-------|--------|----------|
| 1 | Bench press, OHP, and pull-up specializations each select a distinct assistance-exercise slot per sticking point, matching squat/deadlift's branching (D-12, SPEC-01) | VERIFIED | `lib/features/programs/data/smart_program_planner.dart:1550-1574` — `_needsForPrimaryLift`'s `assistance` switch has per-lift `switch (specialization.stickingPoint)` branches for `benchPress` (chest→horizontal_push/chest), `overheadPress` (bottom→vertical_push/shoulder), `pullUp` (deadHang→vertical_pull/null), each with a distinct `_` default. `test/smart_program_planner_test.dart` has dedicated OHP (line 588) and pull-up (line 641) cases; `flutter test test/smart_program_planner_test.dart` passes. |
| 2 | A squat specialization on a PPL split only anchors the Legs day — Push/Pull days unaffected (D-02) | VERIFIED | `test/smart_program_planner_test.dart:668` `'squat specialization on a PPL split only anchors the Legs day'` test exists and passes. |
| 3 | SquatSpecialization/SquatStickingPoint no longer exist anywhere in lib/ or test/ | VERIFIED | `lib/features/programs/domain/squat_specialization.dart` confirmed deleted (file not found); `grep -rn "SquatSpecialization\|SquatStickingPoint" lib/ test/` returns 0 matches. |
| 4 | ProgramGuardrails can classify a below-floor muscle group and an unrealistic kg increase as warning-severity (never blocking) issues | VERIFIED | `lib/features/programs/domain/program_guardrails.dart:224-277` — `validateKgIncrease` and `validateVolumeFloor` both exist, both return only `GuardrailSeverity.warning` issues. `test/program_guardrails_test.dart` passes (11 new tests per 22-01-SUMMARY.md). |
| 5 | Toggling specialization on with a compatible split (Upper/Lower, PPL, Full Body) keeps that split instead of forcing a reset (D-01-D-03) | VERIFIED | `step_parameters_specialization.part.dart:4` `_specializationCompatibleSplits` set; line 236 `if (!_specializationCompatibleSplits.contains(_split))` gates the reset. `test/block_builder_view_test.dart` passes including this case. |
| 6 | Toggling specialization with an incompatible split (e.g. Bro Split) still resets to Full Body/3-day/Linear (D-03) | VERIFIED | Same gated conditional (inverse branch); covered by a passing widget test per 22-02-SUMMARY.md. |
| 7 | Every lift's sticking-point selection shows its own assistanceFocus copy in the specialization modal (D-12 UI half) | VERIFIED | `step_parameters_specialization.part.dart:172` renders `PrimaryLiftSpecialization(...).assistanceFocus` as a `Text` widget after the sticking-point dropdown. Widget tests assert exact copy for bench/OHP cases. |
| 8 | The specialization summary card's exposures-per-week text reflects the actual split, never hardcoded 3 (Pitfall 3) | VERIFIED | `step_parameters.part.dart:279` interpolates `_specializationExposuresPerWeek` (computed via `PrimaryLift.appliesToDayLabel` against `_plan.trainingDays`), not a literal. |
| 9 | Weeks picker auto-adjusts a too-short specialization pick to recommendedWeeks() with an inline warning (D-08-D-10) | VERIFIED | `dialogs.part.dart:262-270` — `if (_useLiftSpecialization && selected < _liftRecommendedWeeks)` sets `_weeks = recommended` and shows a `SnackBar` with heading `'Not enough time to progress safely'`. Tests pass. |
| 10 | Weeks picker shows a "That's a big jump" warning when the kg gap exceeds the experience-tier ceiling, independent of weeks tapped (D-11) | VERIFIED | `dialogs.part.dart:212` calls `ProgramGuardrails.validateKgIncrease`; line 231 renders `heading: "That's a big jump"` banner. Tests pass. |
| 11 | Schedule step's volume breakdown highlights below-floor muscle groups as "Light" when specialization is active with a linked template (D-04, D-06 live half, D-07); Create-time shows a non-blocking confirmation naming volume-floor/kg-increase issues, "Create anyway" proceeds, "Review" cancels cleanly (D-05, D-06 Create-time half, D-11 Create-time half); inactive specialization or no issues proceeds unchanged (regression) | VERIFIED | `step_schedule_summary.part.dart:168-169` conditionally renders `SpecializationVolumeFloorCard` instead of `ProgramMuscleVolumeCard` when `_useLiftSpecialization`. `specialization_volume_floor_card.dart` (113 lines) tints `VolumeVerdict.low` rows. `actions.part.dart:55` `_confirmSpecializationWarnings`, lines 126-147 call `validateVolumeFloor`/`validateKgIncrease` and gate on `_useLiftSpecialization`. All 4 new `block_builder_view_test.dart` cases (D-06/D-11 group) plus all 6 pre-existing D-07 characterization tests pass. |

**Score:** 11/11 truths verified

### Required Artifacts

| Artifact | Expected | Status | Details |
|----------|----------|--------|---------|
| `lib/features/programs/data/smart_program_planner.dart` | `_needsForPrimaryLift` with 6 sticking-point branches covering all 5 PrimaryLift values; squatSpecialization threading removed | VERIFIED | Confirmed via Read; squat/deadlift/bench/OHP/pullUp all branch distinctly; no `squatSpecialization` references remain. |
| `lib/features/programs/domain/program_guardrails.dart` | `validateVolumeFloor`, `validateKgIncrease`, `kgIncreaseCeilings`, warning-severity only | VERIFIED | Confirmed via Read; matches 22-01-SUMMARY.md's documented signatures exactly. |
| `lib/features/programs/presentation/views/block_builder_view/step_parameters_specialization.part.dart` | `_specializationCompatibleSplits` set + conditional reset + assistanceFocus Text | VERIFIED | Confirmed via grep, 283 lines (well under 600-line cap). |
| `lib/features/programs/presentation/views/block_builder_view/step_parameters.part.dart` | computed `exposuresPerWeek`, no literal '3 exposures/week' | VERIFIED | Confirmed via grep. |
| `lib/features/programs/presentation/views/block_builder_view/dialogs.part.dart` | shortfall auto-adjust + kg-ceiling banner | VERIFIED | Confirmed via grep, 391 lines (under cap). |
| `lib/features/programs/presentation/widgets/specialization_volume_floor_card.dart` | `SpecializationVolumeFloorCard`, tints low-verdict rows | VERIFIED | Confirmed via Read, 113 lines, exported and imported in `block_builder_view.dart`. |
| `lib/features/programs/presentation/views/block_builder_view/actions.part.dart` | `_create()`'s non-blocking volume-floor/kg-increase confirmation gated on `_useLiftSpecialization` | VERIFIED | Confirmed via grep, 396 lines (under cap). |
| `lib/features/programs/domain/squat_specialization.dart` | should no longer exist | VERIFIED (deleted) | `ls` confirms file absent. |

### Key Link Verification

| From | To | Via | Status | Details |
|------|-----|-----|--------|---------|
| `smart_program_planner.dart (_needsForPrimaryLift)` | `primary_lift_specialization.dart (PrimaryLiftStickingPoint)` | `switch (specialization.stickingPoint)` per lift | WIRED | Confirmed present for benchPress/overheadPress/pullUp in addition to pre-existing squat/deadlift. |
| `program_guardrails.dart (validateKgIncrease)` | `primary_lift_specialization.dart (PrimaryLiftSpecialization)` | required `specialization` param | WIRED | Confirmed in signature. |
| `step_parameters_specialization.part.dart (Apply handler)` | `split_template.dart (SplitType)` | `_specializationCompatibleSplits.contains(_split)` | WIRED | Confirmed. |
| `step_parameters.part.dart (summary card)` | `primary_lift_specialization.dart (appliesToDayLabel)` | `_plan.trainingDays.where(...)` | WIRED | Confirmed via `_specializationExposuresPerWeek` getter. |
| `dialogs.part.dart (_showLengthPicker onSelected)` | `primary_lift_specialization.dart (recommendedWeeks via _liftRecommendedWeeks)` | `selected < _liftRecommendedWeeks` | WIRED | Confirmed. |
| `dialogs.part.dart (sheet body)` | `program_guardrails.dart (validateKgIncrease)` | direct static call | WIRED | Confirmed. |
| `step_schedule_summary.part.dart (_summaryCard)` | `specialization_volume_floor_card.dart (SpecializationVolumeFloorCard)` | conditional instantiation inside `FutureBuilder` | WIRED | Confirmed. |
| `actions.part.dart (_create)` | `program_guardrails.dart (validateVolumeFloor/validateKgIncrease)` | direct static calls | WIRED | Confirmed. |

### Data-Flow Trace (Level 4)

| Artifact | Data Variable | Source | Produces Real Data | Status |
|----------|---------------|--------|---------------------|--------|
| `SpecializationVolumeFloorCard` | `breakdown.averageWeeklyVolumes` | `ProgramVolumeCalculator.computeFromTemplates` (real DB query against `ExerciseCatalog`/`TemplateExercises`) | Yes | FLOWING — proven end-to-end by a new integration test in `test/program_muscle_volume_test.dart` seeding a real in-memory DB and asserting `VolumeBands.verdicts` yields `VolumeVerdict.low` for a low-volume Chest template. |
| `actions.part.dart` Create-time confirmation | `volumeIssues`/`kgIssues` | Fresh `ProgramVolumeCalculator.computeFromTemplates` call + `_primaryLiftSpecialization` | Yes | FLOWING — computed from live builder state (`_templatesBySlot`, `_plan`, `_weeks`, `_model`), not static/hardcoded. |

### Behavioral Spot-Checks

| Behavior | Command | Result | Status |
|----------|---------|--------|--------|
| Domain + guardrail unit tests | `flutter test test/smart_program_planner_test.dart test/program_guardrails_test.dart test/specialization_volume_floor_card_test.dart test/program_muscle_volume_test.dart` | exit 0, "All tests passed!" | PASS |
| Full block-builder widget test suite (incl. all phase-22 D-01–D-12 cases) | `flutter test test/block_builder_view_test.dart` | exit 0, 40/40 tests passed | PASS |
| Static analysis on all touched phase-22 files | `flutter analyze lib/features/programs/ test/smart_program_planner_test.dart test/program_guardrails_test.dart test/block_builder_view_test.dart test/specialization_volume_floor_card_test.dart test/program_muscle_volume_test.dart` | 4 pre-existing `info`-level issues, 0 errors, none in phase-22-touched files | PASS |
| `SquatSpecialization`/`SquatStickingPoint` fully removed | `grep -rn "SquatSpecialization\|SquatStickingPoint" lib/ test/` | 0 matches | PASS |
| Claimed commits exist in repo history | `git cat-file -t` on all 9 commit hashes cited across the 4 SUMMARY.md files | all 9 resolve to `commit` objects | PASS |

### Requirements Coverage

| Requirement | Source Plan | Description | Status | Evidence |
|-------------|------------|-------------|--------|----------|
| SPEC-01 | 22-01, 22-02 | Strength specialization targets user-selected lift with 1RM, target weight, sticking-point analysis | SATISFIED | `PrimaryLiftSpecialization` (pre-existing) + D-12 per-lift branching (22-01) + modal assistanceFocus copy surfaced per lift/sticking-point (22-02). |
| SPEC-02 | 22-02, 22-04 | Specialization planner preserves anchor lift frequency while maintaining non-target muscle groups above baseline maintenance volume | SATISFIED | Split-compatibility preservation + computed exposures (22-02); live volume-floor preview + Create-time confirmation via `ProgramGuardrails.validateVolumeFloor` wired end-to-end with a real DB integration test (22-04). |
| SPEC-03 | 22-03 | Unrealistic target timelines generate realistic warnings rather than aggressive programming | SATISFIED | Weeks-picker auto-adjust + "Not enough time" SnackBar, "That's a big jump" kg-ceiling banner (22-03), both non-blocking. |

**Note:** `.planning/REQUIREMENTS.md`'s checkbox state and Traceability table still show SPEC-01–03 as `[ ]`/"Pending" at verification time. This is a documentation-sync gap, not a code gap — all three requirements have concrete, tested, wired implementation evidence in the codebase as detailed above. Recommend updating REQUIREMENTS.md's checkboxes/Traceability row to reflect completion as part of phase close-out.

### Anti-Patterns Found

None. Scanned all 9 phase-22-modified/created lib files for `TBD|FIXME|XXX|TODO|HACK|PLACEHOLDER|not yet implemented|coming soon` — zero matches. All modified/created files are well under the 600-line cap (largest is `actions.part.dart` at 396 lines).

`dart run tool/check_structure.dart` reports 57 pre-existing over-600-line files, none of which are phase-22-created files; `smart_program_planner.dart` (1998 lines) was already over the cap before this phase and this phase only removed code from it (dead `SquatSpecialization` threading) — not a phase-22 regression.

### Human Verification Required

None. All behavioral claims (split-compatibility preservation/reset, assistanceFocus copy rendering, exposures-per-week text, weeks-picker auto-adjust + SnackBar, kg-ceiling banner, Schedule-step "Light" tinting, Create-time confirmation dialog with both button outcomes) are covered by passing automated widget tests that assert on rendered text/widget presence, not left to subjective visual judgment.

### Gaps Summary

No gaps found. All 11 observable truths derived from ROADMAP.md's Success Criteria and the 4 plans' `must_haves` frontmatter are verified against actual, tested, wired code — not just SUMMARY.md claims. All 4 plans' claimed file changes, commits, and test additions were independently confirmed by reading the source files and running the test suites fresh in this verification pass (not trusting the SUMMARY.md narration). `flutter test` and `flutter analyze` were both run directly rather than relying on the summaries' reported results.

One documentation-sync note (non-blocking): REQUIREMENTS.md's checkboxes for SPEC-01–03 were not flipped to `[x]` and the Traceability table still reads "Pending" — recommend a follow-up edit to REQUIREMENTS.md, but this does not affect phase goal achievement.

---

*Verified: 2026-10-02T10:32:31Z*
*Verifier: Claude (gsd-verifier)*
