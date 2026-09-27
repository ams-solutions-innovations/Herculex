---
phase: 21-crossfit-gpp-training-tracks
verified: 2026-09-27T13:56:13Z
status: passed
score: 7/7 must-haves verified
overrides_applied: 0
re_verification:
  previous_status: gaps_found
  previous_score: 5/7
  gaps_closed:
    - "A metcon's movement count and advanced-movement stacking are bounded by a per-level ceiling, never silently uncapped (D-06 combo/complexity axis)"
    - "Program review UI shows the real AMRAP/EMOM/For-Time metcon prescription, not a meaningless placeholder"
  gaps_remaining: []
  regressions: []
deferred: []
---

# Phase 21: CrossFit & GPP Training Tracks Verification Report

**Phase Goal:** Support structured CrossFit and GPP training programs with multi-segment session blueprints and scaled gymnastics/metcons.
**Verified:** 2026-09-27
**Status:** passed
**Re-verification:** Yes — after gap closure (plans 21-08, 21-09 executed on top of the original 7)

## Goal Achievement

### Observable Truths

| # | Truth | Status | Evidence |
|---|-------|--------|----------|
| 1 | A CrossFit day produces an ordered warmup→skill→strength→metcon→cooldown segment blueprint, skill and strength kept distinct | ✓ VERIFIED | Unchanged since initial verification. `CrossfitProgramPlanner.segmentNeedsFor` (crossfit_program_planner.dart:29-85) returns exactly that order. |
| 2 | AMRAP, EMOM, and For Time metcon formats are all genuinely reachable (not hardcoded to one), with time caps that vary by experience level | ✓ VERIFIED | Unchanged since initial verification. `_metconFormats` rotates via `variationSeed % 3`; `CrossfitScalingPolicy.timeCapFor` applies per-level multipliers. |
| 3 | A metcon's time cap is treated as a fixed upper bound in the session time-budget estimator, not per-rep-estimated or trimmed | ✓ VERIFIED | Unchanged since initial verification. `WorkoutDurationEstimator.estimateCappedSegment` called from smart_program_planner.dart:1579; trim loop excludes `segment == SessionSegment.metcon`. |
| 4 | A metcon's movement count and advanced-movement stacking are bounded by a per-level ceiling, never silently uncapped | ✓ VERIFIED (gap closed by 21-08) | `CrossfitScalingPolicy.complexityCheck` now has a real production call site at `smart_program_planner.dart:881`, inside `_createStableSlots`. A candidate-pool substitution filter (lines 749-756) reassigns `candidates` to exclude a second advanced/just-unlocked exercise for the same `metconGroupKey` whenever a safe alternative exists in that slot's own pool — verified as a real filter, not a no-op (`candidates = safeCandidates` only when `safeCandidates.isNotEmpty`). When no safe substitute exists, `complexityCheck`'s `exceedsCeiling` rationale plus an explicit "no safe substitute" note is appended to `why` (lines 887-892), which flows unchanged into `ProgramDayExercises.prescriptionWhy` (line 433-435: `prescriptionWhy: Value('${slot.why}...')`). Two new regression tests in `test/features/programs/smart_program_planner_test.dart` (lines 900-992 and 994+) independently confirm both branches: "a novice CrossFit metcon never stacks 2+ advanced/just-unlocked movements when a safe substitute exists" and "when no safe substitute exists, the D-06 exception is recorded in prescriptionWhy, not silently accepted." Both tests pass. |
| 5 | Segment tags and metcon caps survive Program → active workout materialization (not just generation) | ✓ VERIFIED | Unchanged since initial verification. `planned_session_resolver.dart` threads `sessionSegment`/`supersetGroup`/`prescriptionCodecJson`; both CF-01 tests pass. |
| 6 | A GPP day is a standalone 3rd training day that structurally cannot produce Dynamic Effort / heavy strength slots | ✓ VERIFIED | Unchanged since initial verification. `GppProgramPlanner.segmentNeedsFor` only emits `SlotRole.conditioning`; end-to-end regression test passes. |
| 7 | Generated program review UI accurately reflects the real metcon prescription | ✓ VERIFIED (gap closed by 21-09) | `program_review_view.dart`'s `_ExerciseRow` (line 632-646) now computes `isMetcon` from `item.row.sessionSegment == SessionSegment.metcon.id` and decodes `SlotPrescriptionCodec.decode(item.row.prescriptionCodecJson)?.segments.firstOrNull`. When `isMetcon && metconSegment != null`, the subtitle renders `_metconSummary(metconSegment)` (e.g. "AMRAP 7:30", "EMOM 12 min", "For Time, cap 9:00") instead of the raw `targetSets`/`targetRepsMin/Max` placeholder. Non-metcon rows and any metcon row whose decode fails fall back unchanged to the pre-existing `'$targetSets sets · $reps'` text — verified by reading the exact ternary at line 644-646. A new widget test in `test/program_review_view_test.dart` (line 252+) seeds a metcon row with a real encoded AMRAP prescription (`capSeconds: 450`) and asserts `find.textContaining('AMRAP')` finds a widget while `find.textContaining('1 sets')` finds none. Test passes. |

**Score:** 7/7 truths verified

### Required Artifacts

| Artifact | Expected | Status | Details |
|----------|----------|--------|---------|
| `lib/features/programs/data/smart_program_planner.dart` | `CrossfitScalingPolicy.complexityCheck` called at metcon slot resolution, with real substitution | ✓ VERIFIED | Call site at line 881; substitution filter at lines 749-756; tracking maps `metconGroupMovementCount`/`metconGroupAdvancedCount` at lines 516-517; helper `_isCrossfitAdvancedOrJustUnlocked` at line 1250. |
| `test/features/programs/smart_program_planner_test.dart` | Two new regression tests proving both branches of the stacking guard | ✓ VERIFIED | Both tests present in the `'CrossFit/GPP segment wiring (CF-01/CF-02/CF-03)'` group; both pass (confirmed via targeted `flutter test` run). |
| `lib/features/programs/presentation/views/program_review_view.dart` | `_ExerciseRow` decodes `prescriptionCodecJson` via `SlotPrescriptionCodec` for metcon rows | ✓ VERIFIED | Decode call at line 634; `_metconSummary`/`_formatCap` helpers at lines 689+; non-metcon/decode-failure fallback preserved unchanged. |
| `test/program_review_view_test.dart` | Widget test seeding a metcon row, asserting real summary renders and placeholder is absent | ✓ VERIFIED | Test at line 252 ("a metcon row renders the decoded AMRAP summary, not the placeholder"); asserts `AMRAP` present and `1 sets` absent; passes. |

All artifacts verified previously (session_segment.dart, tables.dart, database.dart, the Supabase migration, crossfit_scaling_policy.dart's other 3 methods, crossfit_program_planner.dart, gpp_program_planner.dart, workout_duration_estimator.dart, exercise_programming_metadata.json, planned_session_resolver.dart) remain unchanged and were re-confirmed present via regression check (no file deletions, no reverted commits found in `git log`).

### Key Link Verification

| From | To | Via | Status | Details |
|------|-----|-----|--------|---------|
| `smart_program_planner.dart` `_createStableSlots` | `crossfit_scaling_policy.dart` `CrossfitScalingPolicy.complexityCheck` | Direct static call, once per resolved metcon slot | ✓ WIRED (closed by 21-08) | Confirmed at smart_program_planner.dart:881; previously ✗ NOT_WIRED. |
| `program_review_view.dart` `_ExerciseRow` | `slot_prescription_codec.dart` `SlotPrescriptionCodec.decode` | Direct call inside `_ExerciseRow.build`, gated on `sessionSegment == 'metcon'` | ✓ WIRED (closed by 21-09) | Confirmed at program_review_view.dart:634; previously ✗ NOT_WIRED. |
| `smart_program_planner.dart` `_needsFor` | `crossfit_program_planner.dart` | `CrossfitProgramPlanner.segmentNeedsFor(...)` | ✓ WIRED | Unchanged, re-confirmed. |
| `smart_program_planner.dart` `_needsFor` | `gpp_program_planner.dart` | `value.trim() == 'gpp'` branch | ✓ WIRED | Unchanged, re-confirmed. |
| `planned_session_resolver.dart` | `tables.dart` | `plannedSessionSegment`/`supersetGroup` companion writes | ✓ WIRED | Unchanged, re-confirmed. |

### Data-Flow Trace (Level 4)

| Artifact | Data Variable | Source | Produces Real Data | Status |
|----------|---------------|--------|---------------------|--------|
| `_ExerciseRow` (program_review_view.dart) | `metconSegment` (decoded `WorkSegment`) | `ProgramDayExercises.prescriptionCodecJson`, encoded by `SlotPrescriptionCodec.encode` in `smart_program_planner.dart` with the real `slot.metconFormat`/`metconCapSeconds`/`metconMinutes` | Yes — decoded value flows to `_metconSummary` and renders as subtitle text | ✓ FLOWING (was ⚠️ STATIC before 21-09) |
| `ProgramDayExercises.prescriptionWhy` | `complexityExceptionNote` appended to `slot.why` | `CrossfitScalingPolicy.complexityCheck`'s `rationale`, computed from real per-group advanced-movement counts tracked during `_createStableSlots` | Yes — verified end-to-end by the forced-exception regression test reading `r.row.prescriptionWhy` from a real generated row | ✓ FLOWING (new sink, closed by 21-08) |

### Behavioral Spot-Checks

Not applicable — this phase is pure Dart domain/data logic plus a Flutter widget; no runnable CLI/HTTP entry points. Verification relies on the automated test suite (run in full below) plus direct code reading of the call sites and data flow.

### Probe Execution

No `scripts/*/tests/probe-*.sh` files exist in this project and no plan/summary declares probe-based verification. Step 7c: SKIPPED (no probes applicable).

### Test Suite Verification

Independently executed by the verifier (not taken from SUMMARY.md claims):

- **`flutter analyze`**: **0 errors** (42 info/warning-level issues, all pre-existing, none in files touched by 21-08/21-09).
- **`flutter test test/features/programs/smart_program_planner_test.dart test/program_review_view_test.dart`** (targeted): **18/18 passing**, including both new CF-02 stacking-guard regression tests and the new metcon-display widget test.
- **`flutter test` (full suite)**: **1380 passed, 9 skipped, 7 failed**. All 7 failures confirmed (via explicit `[E]` markers in the raw run, not just SUMMARY claims) to be exactly:
  - `test/schema_v25_test.dart` — 4 failures ("a v24 database migrates through v25...", "a pre-v25 row is backfilled...", "the outbox triggers fire after migrating from v24", "foods/recipes keep their v24 deletedAt column untouched")
  - `test/schema_v27_test.dart` — 1 failure ("v26 -> v27 creates fasting_schedules...")
  - `test/schema_v28_test.dart` — 1 failure ("v27 -> v28 adds start_time_minutes...")
  - `test/schema_v29_test.dart` — 1 failure ("v28 -> v29 adds the buddy mirror tables...")
  - This is exactly the same pre-existing failure set documented in the prior VERIFICATION.md and `deferred-items.md` (stale `v39`-hardcode debt against a live `schemaVersion` of 44, unrelated to Phase 21). **No new regressions** were introduced by 21-08 or 21-09. The passed count increased from 1367 to 1380 (+13), consistent with the 3 new tests added by this gap-closure work plus other unrelated test additions already in the tree.

### Requirements Coverage

| Requirement | Source Plan(s) | Description | Status | Evidence |
|-------------|-----------------|--------------|--------|----------|
| CF-01 | 21-01, 21-03, 21-04, 21-06, 21-07, 21-09 | Sessions structure into ordered blueprint segments with time caps that survive to the active workout, and the program review UI accurately reflects them | ✓ SATISFIED | Segment order, materialization, and now the review-UI display are all verified end-to-end. 21-09 closes the previously-open display gap. |
| CF-02 | 21-02, 21-03, 21-04, 21-08 | Experience levels scale movement complexity and metcon formats, including the D-06 hard stacking rule | ✓ SATISFIED | Time caps, movement count, and format rotation scale correctly; the advanced-movement-stacking hard rule is now enforced at generation time with real substitution and a non-silent exception path, per 21-08. |
| CF-03 | 21-01, 21-05, 21-06 | Full Body 2× + GPP split delivers dedicated conditioning without unintended Dynamic Effort sets | ✓ SATISFIED | Unchanged, re-confirmed passing. |

No orphaned requirements. All three IDs mapped to Phase 21 in REQUIREMENTS.md appear in at least one plan's `requirements` field (including the two gap-closure plans, which correctly declared `requirements: [CF-02]` and `requirements: [CF-01]` respectively).

### Anti-Patterns Found

None in the files modified by 21-08/21-09. No `TBD`/`FIXME`/`XXX` markers, no empty implementations, no hardcoded-empty stub patterns in `smart_program_planner.dart`'s new code, `program_review_view.dart`'s new code, or either test file. The two previously-flagged blocker/warning anti-patterns (dead-code `complexityCheck`, raw-placeholder `_ExerciseRow`) are both resolved — the underlying methods now have real call sites with substantive logic, not just references.

### Human Verification Required

None. Both previously-open items were deterministically verifiable in code (call-site existence, substitution logic, data-flow to `prescriptionWhy`/UI rendering) and have been confirmed programmatically, backed by passing automated tests. No visual/UX judgment call remains outstanding for this phase.

### Gaps Summary

None. Both gaps from the initial verification pass are closed:

1. **CrossfitScalingPolicy.complexityCheck dead code (gap #1)** — Closed by 21-08. The guard now has a real production call site in `_createStableSlots`, performs genuine candidate-pool substitution (not a passive check), and records a non-silent exception in `prescriptionWhy` when no safe substitute exists. Verified via direct source reading and two passing regression tests exercising both branches independently of scorer tie-break nondeterminism.

2. **Program review UI placeholder metcon display (gap #2)** — Closed by 21-09. `_ExerciseRow` now decodes `prescriptionCodecJson` for metcon rows and renders the real AMRAP/EMOM/For-Time summary, with a verified fallback to the old placeholder text for non-metcon rows or failed decodes. Verified via direct source reading and a passing widget test asserting both the presence of the real summary and the absence of the placeholder text.

Phase 21, all 9 plans (21-01 through 21-09), now fully meets the ROADMAP.md success criteria: "Sessions structured into warmup, skill/strength, metcon, and cooldown segments; AMRAP, EMOM, and For Time formats preserve time caps; Full Body 2× + GPP split delivers dedicated conditioning without 8×3 sets" — with the additional, now-closed safety guarantee (D-06 stacking guard) and the now-accurate review-UI display. `flutter analyze` is clean (0 errors) and the full test suite shows no new regressions beyond the pre-existing, out-of-scope schema migration test debt.

**Final verdict: Phase 21 PASSES in full. Ready to proceed.**

---

*Verified: 2026-09-27*
*Verifier: Claude (gsd-verifier)*
