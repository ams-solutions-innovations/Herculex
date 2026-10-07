---
phase: 28-adaptive-tdee-activity-calibration
plan: 11
subsystem: nutrition-verification
tags: [tdee, supabase, verification, traceability]
requires:
  - phase: 28-05
    provides: tdee_estimates Supabase migration file
  - phase: 28-08
    provides: adaptive baseline wired into editor, planner and dream physique
  - phase: 28-09
    provides: badge and detail sheet
  - phase: 28-10
    provides: activity reset policy and Profile flow
provides:
  - Phase-level verification of Phase 28 (suite, analyzer, structure, greps)
  - TDEE-01..05 and D-01..D-15 traceability
  - Record of the user-reported Supabase push and two known limitations
affects: [29]
key-files:
  created: []
  modified: []
key-decisions:
  - "Supabase push independently verified 2026-09-28 via supabase CLI + 4 read-only queries; the earlier user 'Pushed' report was unverified and turned out to be wrong (migration was still pending)"
  - "The 9 skipped tests are pre-existing live-Supabase tests, not introduced by Phase 28"
requirements-completed: [TDEE-01, TDEE-02, TDEE-03, TDEE-04, TDEE-05]
duration: ~30min
completed: 2026-09-28
---

# Phase 28 Plan 11: Supabase push gate and phase-level verification Summary

The full suite is green (1627 passed / 9 skipped / 0 failed), the analyzer has 0 errors, no new structure violation was introduced, and every TDEE requirement and D decision traces to code or a documented deferral. The Supabase push, originally only user-reported, was independently verified and (since it turned out not to have actually happened) applied on 2026-09-28.

## Task 1: Supabase migration push (user-run gate)

**Status: independently verified live on 2026-09-28.**

- The original "Pushed" reply to the blocking checkpoint carried no evidence and the Supabase MCP was not authorized in that session, so it went unverified (see prior revision of this summary).
- On 2026-09-28, with the Supabase CLI linked to this repo (`supabase/config.toml` and `supabase/.temp/project-ref` both confirm `ldzgyzigvbwofbswitrv`, not `jioesomepkauponjrena`), `supabase migration list` showed `0015` through `20260916000000` already applied remotely — CLAUDE.md's "0015/0016 outstanding" note is stale — but **`20260928000000_tdee_estimates_v45.sql` was still pending**, meaning the earlier "Pushed" report was incorrect.
- `supabase db push --dry-run` confirmed only that one migration was pending. With the user's explicit go-ahead, ran `supabase db push`, which applied it.
- Verified with the four read-only queries from the how-to-verify list, run via `supabase db query <sql> --linked`:
  - `information_schema.columns` → exactly the 12 expected columns (confidence, date_iso, deleted_at, estimated_at, id, inputs_json, kcal, method, observed_qualified, updated_at, user_id, window_days).
  - `pg_policies` → all four `tdee_estimates_{select,insert,update,delete}_own` policies.
  - `pg_trigger` → both `t_set_updated_at_tdee_estimates` and `t_record_tombstone_tdee_estimates`.
  - `pg_indexes` → `tdee_estimates_user_updated_idx` present (plus the implicit `tdee_estimates_pkey`).
- Not run: the optional real-device smoke test (a live recalibration row draining through `pending_sync_ops` without PGRST204) — that's UAT item 6, still pending, since it needs a real device with Health data over ~14 days.
- `.planning/phases/28-adaptive-tdee-activity-calibration/28-HUMAN-UAT.md` item 1 updated to `pass` with this evidence.

## Task 2: Phase-level verification (real command output)

| Check | Result |
| ----- | ------ |
| `flutter test` (full) | exit 0, `+1627 ~9: All tests passed!` |
| Targeted phase run (13 files/dirs from the plan) | exit 0, `+277: All tests passed!` |
| `flutter analyze` | 0 errors, 11 warnings, 33 info (44 issues) |
| `dart run tool/check_structure.dart` | 58 violations, all pre-existing (same count as 28-10) |
| `dart format --output=none --set-exit-if-changed lib test tool` | exit 1: 62 files would change, see below |
| `nutrition_targets_view.dart` length | 2618 lines (limit 2635) |
| New domain files | `tdee_estimator.dart` 498, `activity_classifier.dart` 176, `tdee_trend.dart` 101; all under 600 |
| No `DateTime.now` in the nine listed files | grep returns nothing |
| No `package:flutter` / `package:drift` in the five pure-domain files | grep returns nothing |
| `MacroTargets.fromProfile` call sites in `lib` | only `nutrition_providers.dart:78` (the definition file does not match the literal pattern) |
| `schemaVersion => 45`, `drift_schema_v45.json`, `schema_v45.dart`, migration SQL | all present |

Notes on each:

- **Analyzer:** the count is 44 items against the 42 quoted in earlier plans. I checked every item in phase-adjacent files with `git blame`: `macro_chart.dart:166`, `dream_physique_priorities_sheet.dart:1`, `profile_view.dart:30`, `_body.part.dart:133` and `nutrition_restore_entry_test.dart:29` all date from 2026-09-01 or 2026-09-14, before Phase 28. None is in a file line this phase wrote. I did not chase the exact 2-item difference from the earlier figure (the earlier figure was a reported number, not a saved artifact I could diff). All 44 are warnings or info, so exit code 1 is expected.
- **check_structure:** 58 violations, none in a new file. `nutrition_providers.dart` is over 600 lines but was already over (926 before Phase 28, 934 now, +8). `nutrition_targets_view.dart` was already over and is +1 versus its 2617 starting size.
- **Formatting:** 62 files would be reformatted, essentially all in code Phase 28 never touched. Exactly one file in that list was touched by this phase, `lib/features/profile/presentation/profile_view/_body.part.dart` (plan 10). The formatter's diff there was confined to `_ProfileLevelCard` (the gamification level card, lines ~1125 and ~1164), which Phase 28 did not write. Per the instruction not to commit unrelated formatting churn, I restored that file byte-for-byte and left the tree with only the three pre-existing uncommitted paths. Nothing was reformatted or committed.
- **Skipped count (9 versus the CLAUDE.md baseline of 4):** not caused by this phase. Phase 28 added no `skip:` or `@Skip` (diff of `test/` from the commit before plan 01 shows none). The skips are the opt-in live-Supabase tests in `test/sync/live_round_trip_test.dart` (4 tests) and `test/sync/live_buddy_test.dart` (5 tests), gated behind environment variables and last modified 2026-09-02. 4 + 5 = 9. The figure "4 skipped" in CLAUDE.md is stale. Plan 03's summary already recorded 9 skipped, so this was known before the phase's later plans.
- **Failures:** none. No pre-existing failure was encountered, so nothing was deferred.

## Traceability: requirements to tests

| Req | What | Automated coverage |
| --- | ---- | ------------------ |
| TDEE-01 | Observed expenditure from food diary and bodyweight | `test/tdee_estimator_test.dart`, `test/tdee_inputs_repository_test.dart`, `test/features/nutrition/tdee_providers_test.dart`, `test/features/nutrition/nutrition_targets_view_test.dart` |
| TDEE-02 | Activity classifier fallback from HealthSamples and training | `test/activity_classifier_test.dart`, `test/macro_targets_test.dart`, `test/tdee_inputs_repository_test.dart`, `test/activity_reset_policy_test.dart`, `test/features/profile/activity_reset_flow_test.dart` |
| TDEE-03 | App self-selects window and recalibration cadence | `test/tdee_estimator_test.dart` (window candidates 35/28/21/14, `shouldRecalibrate`, hysteresis), `test/features/nutrition/tdee_recalibration_test.dart` |
| TDEE-04 | Method, confidence, window and inputs always visible; never overrides a manual target | `test/tdee_estimate_test.dart`, `test/target_resolver_test.dart`, `test/features/nutrition/tdee_estimate_badge_test.dart`, `test/features/nutrition/tdee_estimate_sheet_test.dart`, `test/features/nutrition/tdee_providers_test.dart`, `test/activity_reset_policy_test.dart` |
| TDEE-05 | History persisted and synced, material shift never silent | `test/tdee_estimates_repository_test.dart`, `test/tdee_sync_registration_test.dart`, `test/migration_test.dart`, `test/tdee_supabase_migration_test.dart`, `test/tdee_estimator_test.dart` (`isMaterialShift`), `test/features/nutrition/tdee_recalibration_test.dart` |

## Traceability: decisions to code

| Decision | Where it lives |
| -------- | -------------- |
| D-01 two independent gates (food days, weigh-ins) | `TdeeEstimator.estimateObserved`; `TdeeTuning.minWeighIns` (4), `foodAdherenceBar` |
| D-02 ~70% of window days logged | `TdeeTuning.foodAdherenceBar = 0.70`, `_ceilShare` (0.7 x 10 gates at 7) in `tdee_estimator.dart` |
| D-03 sustained crossing, no flapping | `TdeeTuning.hysteresisCycles = 2`; `recalibrate` promotes only on a qualifying run 7+ days after the last row |
| D-04 hold last observed estimate as aging, then fall back | `TdeeTuning.graceDays = 7`, `observedHoldMaxAgeDays = 14`; held rows surface as "aging" in the badge |
| D-05 inline badge opening a detail sheet | `presentation/widgets/tdee_estimate_badge.dart`, `presentation/sheets/tdee_estimate_sheet.dart`, mounted under "Maintenance calories" in `nutrition_targets_view.dart` (plan 09) |
| D-06 classifier inputs listed individually | `TdeeEstimateSheet` "used" inputs (avg steps, workouts per week); active kcal, sleep and resting HR only under "Also recorded (not used in the estimate)" |
| D-07 saved target beside the live estimate | `savedTargetForTodayProvider` in `tdee_display_providers.dart`, rendered in the sheet (saved target compared against pure maintenance, no goal delta) |
| D-08 cold start, "Calibrating", never blank | `TdeeBadgeState`; `MacroTargets.seedMaintenanceKcal`; `baselineTargetsProvider` falls back to `MacroTargets.fromProfile` on null, loading or error |
| D-09 material shift is max(100 kcal, 5%) | `TdeeEstimator.isMaterialShift` (strict greater-than, unrounded) |
| D-10 accept/dismiss prompt | **Deferred to Phase 29** by design. Not implemented in Phase 28. |
| D-11 persist history only, no shift event | `TdeeEstimates` table (drift v45, synced), `TdeeEstimatesRepository`; deliberately no accept/dismiss UI and no material-shift event or record |
| D-12 onboarding question kept, reframed | `onboarding_view.dart` ("How active are you right now?" with starting-point subtitle), plan 10 |
| D-13 picker stays in Profile as a manual reset | `ActivityLevelSection` in `profile/presentation/widgets/activity_level_section.dart`, `ActivityResetPolicy` |
| D-14 reset reseeds only, keeps history | Reset is the ordinary profile save; `TdeeRecalibrator` forced run appends a row and never deletes; a stored coldStart row's kcal is ignored in favour of the live seed |
| D-15 reset does not force back to Calibrating for measured users | `ActivityResetPolicy.isMeasured` and the measured-aware snackbar; observed rows returned as stored by `baselineTargetsProvider` |

Also intentionally absent per D-11: any accept/dismiss control and any material-shift event.

## Known limitations

These are recorded, not fixed in this phase.

1. **The classifier needs step data.** A user without Health/steps data (fewer than 3 step days in the 14-day window) gets `ActivityClassification.unavailable`, so they stay on the `ActivityLevel` seed (coldStart) until observed mode qualifies from food and weight logs, and indefinitely if they never log both.
2. **The Nutrition goals-sheet activity picker is not relabelled.** `goals_view.dart` `_ActivityLevelSheet` has no reset confirm dialog and no caption. Plan 10 scoped the copy to Profile and onboarding per the approved UI-SPEC. It writes the same seed field and the controller reseeds correctly on any surface, so behaviour is consistent; only the copy and confirm are missing. Offered as a follow-up.

## Deviations from Plan

None new in this plan (verification only, no source changes).

Carried forward from earlier plans: plan 28-09 modified `lib/design_system/components/hx_stat_tile.dart` (label and value wrapped in `Flexible`), although its plan said not to. It was a Rule 3 fix because the unmodified tile overflowed at 360dp with 2x text; existing users of the tile (`macro_grid.dart`, `training_level_view.dart`) are covered by the green full suite.

## Known Stubs

None.

## Threat Flags

None new. T-28-43 (wrong project), T-28-45 (migration order) and T-28-46 (RLS gap) are now confirmed mitigated by the 2026-09-28 verification queries, not just the user's checklist. T-28-44 (executor applying production migrations) was explicitly waived for this one push: the user was asked and gave explicit go-ahead for the executor to run `supabase db push` in this session, rather than running it themselves, since the CLI was already linked here and the earlier unverified report needed correcting.

## Outstanding

- UAT item 6 (real-device ~14-day calibration progression) is still pending — needs a physical device with Health data.
- `.planning/ROADMAP.md`: Phase 28 progress updated with `roadmap update-plan-progress`.
