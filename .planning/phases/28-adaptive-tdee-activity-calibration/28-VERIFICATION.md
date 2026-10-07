---
phase: 28-adaptive-tdee-activity-calibration
verified: 2026-09-28T00:00:00Z
status: human_needed
score: 7/8 must-haves verified (1 partial, deferred to Phase 29)
overrides_applied: 0
re_verification: false
deferred:
  - truth: "A material shift surfaces in the weekly report (accept/dismiss prompt)"
    addressed_in: "Phase 29"
    evidence: "Phase 29 goal: 'weekly report ... TDEE drift'; RPT-01: 'One persisted report row per ISO week ... and TDEE drift'. CONTEXT D-10/D-11 document that Phase 28 persists history only and Phase 29 diffs it with the D-09 rule."
human_verification:
  - test: "Confirm the tdee_estimates migration is live on Supabase project ldzgyzigvbwofbswitrv, after 0015 and 0016"
    expected: "12 columns (id, user_id, date_iso, estimated_at, method, confidence, window_days, kcal, observed_qualified, inputs_json, updated_at, deleted_at); four tdee_estimates_{select,insert,update,delete}_own policies; triggers t_set_updated_at_tdee_estimates and t_record_tombstone_tdee_estimates; index tdee_estimates_user_updated_idx; a recalibration row syncs and pending_sync_ops drains without PGRST204"
    why_human: "User reported 'Pushed' with no evidence (no project ref, no migration list, no query output). Supabase MCP is not authorized in this session, so it cannot be checked from here."
  - test: "Nutrition > Targets > editor: look at the badge under 'Maintenance calories' in each state (Calibrating, Classified, Measured, Measured aging), at 360dp width and 2x text scale, in light and dark themes"
    expected: "Pill reads per the UI-SPEC copy, does not overflow, hit area is about 44px, accent colours are legible, badge is visible without scrolling past the field"
    why_human: "Layout, contrast and touch feel cannot be judged from code."
  - test: "Tap the badge to open the detail sheet, with and without a saved manual target"
    expected: "Method, window ('Based on the last N days'), confidence and 'WHAT WE USED' inputs are listed individually. With a saved target the two tiles sit side by side (or stack below 400dp) with the 'set manually' caption. Active calories, sleep and resting HR appear only under 'Also recorded (not used in the estimate)'."
    why_human: "Visual composition and readability."
  - test: "HxStatTile visual regression on the dashboard macro grid and the training level screen"
    expected: "Tiles look the same as before. The Flexible wrap and the new 8px gap between label and icon bubble change nothing at normal widths."
    why_human: "Static analysis shows the change is layout-safe (see Behavioural notes), but there are no golden tests, so a visual diff is the only real proof."
  - test: "Profile > activity level: pick a different level (a) while Calibrating and (b) after calibration, including as a Measured user"
    expected: "(a) saves at once, seed caption, snackbar. (b) confirm dialog 'Reset activity level?' with 'Keep Current Level' / 'Reset Activity Level'. Measured user sees 'Saved. Your estimate stays measured from your logs.' and the badge stays Measured."
    why_human: "Dialog flow and copy tone; widget tests cover logic only."
  - test: "On a real device with Health data, use the app over about 14 days with food and weight logging, then open the badge"
    expected: "Estimate moves from Calibrating to Classified (with steps) and to Measured after about two qualifying weekly runs, without the user choosing any duration"
    why_human: "End-to-end behaviour over real elapsed time and real Health Connect / HealthKit data."
---

# Phase 28: Adaptive TDEE & Activity Calibration Verification Report

**Phase Goal:** Replace the hand-picked activity multiplier with a measured expenditure estimate that the app calibrates and re-calibrates on its own cadence.
**Verified:** 2026-09-28
**Status:** human_needed
**Re-verification:** No, initial verification

I did not rely on SUMMARY claims. I read the domain, data, application and presentation code, grepped every consumer of the baseline, ran the 16 phase test files myself, and ran `flutter analyze`.

## Goal Achievement

### Observable Truths

The ROADMAP `success_criteria` array is empty for this phase. The contract is the single "Success" paragraph, split here into its clauses. Plan-level truths are merged in where they add detail.

| # | Truth | Status | Evidence |
|---|-------|--------|----------|
| 1 | Observed expenditure from logged intake and bodyweight trend becomes the baseline when adherence passes threshold (TDEE-01) | VERIFIED | `TdeeEstimator.estimateObserved` (`tdee_estimator.dart:152-259`): mean logged-day intake minus (EWMA-trend delta x 7700 / span). Two independent gates: food days >= ceil(0.70 x window), weigh-ins >= max(4, 2 x weeks) with data in both window halves (D-01/D-02). Recency, span and plausibility rails included. `recalibrate` returns it as `TdeeMethod.observed`. `baselineTargetsProvider` (`nutrition_providers.dart:73-81`) feeds `est.kcal` through `MacroTargets.fromMaintenance`. Trend is EWMA on an interpolated daily grid (`tdee_trend.dart`), not a two-point delta. Presence-based adherence in `TdeeInputsRepository._foodLoggedDays`. |
| 2 | Otherwise an activity classifier over `HealthSamples` and logged training supplies the multiplier (TDEE-02) | VERIFIED | `ActivityClassifier.classify` returns a continuous multiplier (1.15-1.90) from step anchors plus a training bonus, blended with the seed by data sparsity. `TdeeInputsRepository` reads `healthSamples` with `kind == 'steps'` and `workoutSessions` (completed, 28 days / 4). `recalibrate` computes `bmrKcal * multiplier`, so Mifflin-St Jeor runs with the derived multiplier. Steps are written per day by `HealthService` (`health_service.dart:530`). Limitation: fewer than 3 step days gives `unavailable` and a cold-start seed (recorded in 28-11 SUMMARY). |
| 3 | The app picks its own window and cadence; the user is never asked for a duration (TDEE-03) | VERIFIED | Widest passing window from `[35, 28, 21, 14]`. `shouldRecalibrate`: 7-day cadence, weight-trend shift >= 1 kg, step-mean shift >= 25%, forced on `ActivityLevel` change. Driven by `tdeeRecalibrationControllerProvider`, registered at `app.dart:698`, on profile arrival and on foreground resume. No UI element asks for a duration (grep). Caveat: no background scheduler exists, so a user who never opens the app is not recalibrated. This is documented in the controller. |
| 4 | Every estimate exposes method, confidence, window and inputs (TDEE-04) | VERIFIED (visual: human) | `TdeeEstimateResult` carries all four. Persisted as `method`, `confidence`, `window_days`, `inputs_json`. `TdeeEstimateBadge` is mounted under "Maintenance calories" (`nutrition_targets_view.dart:1599`). `TdeeEstimateSheet` lists method line, window ("Based on the last N days", observed span + 1, not the candidate window), and per-method inputs individually (D-06). Recorded-only signals are separated under "Also recorded (not used in the estimate)". Repository validates the closed vocabulary on read. |
| 5 | Never overrides a manually-set maintenance value (TDEE-04) | VERIFIED | The estimate only feeds `baselineTargetsProvider`. Saved rules resolve first in `TargetResolver` (`effectiveTargetsProvider`), covered by `test/target_resolver_test.dart`. Grep of all TDEE domain/data/application files shows no read or write of `nutrition_targets`. The only reference is `savedTargetForTodayProvider` (read-only, for the sheet comparison, D-07). |
| 6 | A material shift surfaces in the weekly report instead of silently rewriting confirmed targets (TDEE-05) | PARTIAL, DEFERRED | The "never silently rewrites" half is VERIFIED: nothing writes targets. The "surfaces in the weekly report" half is NOT delivered in Phase 28 by design (D-10/D-11): `TdeeEstimator.isMaterialShift` (max(100 kcal, 5%), strict) exists and is unit-tested, and history is persisted and synced. `isMaterialShift` has zero production callers (only its test), and no report or prompt exists. See Deferred Items and Gaps Summary. |
| 7 | `baselineTargetsProvider` is the single integration point and no path bypasses it | VERIFIED | `MacroTargets.fromProfile` is now called only at `nutrition_providers.dart:78` (cold-start fallback). The editor field (`nutrition_targets_view.dart:1387-1409`) uses `maintenanceKcalProvider` and `baselineTargetsProvider`. Phase planner and dream-physique go through the providers (`dream_physique_view.dart:409`). Goal delta is applied exactly once, inside `fromMaintenance`. No stray multiplier literals in `lib` outside `macro_targets.dart` and the classifier anchors. |
| 8 | Schema v45 and sync wiring complete (the five chores) | VERIFIED locally, remote UNCERTAIN | `schemaVersion => 45` (`database.dart:102`), `from < 45` branch (`:1183`), `TdeeEstimates` in `@DriftDatabase`, `syncTableSpecs` entry with `estimated_at` as dateTime (`sync_table_specs.dart:145`), `sync_backfill.dart:56`, `drift_schemas/drift_schema_v45.json`, `test/generated_migrations/schema_v45.dart`, `supabase/migrations/20260928000000_tdee_estimates_v45.sql`. SQL columns match the drift table snake_cased (sync_uuid to `id`, `synced_at` local-only), with RLS, triggers, realtime and index. Whether it is applied remotely is a human item. |

**Score:** 7/8 verified (truth 6 is partial and deferred; truth 8 needs a remote check).

### Deferred Items

| # | Item | Addressed In | Evidence |
|---|------|--------------|----------|
| 1 | Material shift surfaced in the weekly report; accept/dismiss prompt (D-10) | Phase 29 | Phase 29 goal names "TDEE drift" in the weekly report. RPT-01: "...physique progress, and TDEE drift". CONTEXT D-10/D-11 and the design doc (line 267, "Materialen premik gre v tedensko poročilo") assign it there. |

Judgement on the deferral: it is legitimate and documented, not a silent gap. D-11 explicitly limits Phase 28 to persisting history, and Phase 29 exists in ROADMAP.md with TDEE drift in its goal. Two residual risks remain (see Warnings): the accept/dismiss wording lives only in CONTEXT, not in Phase 29's roadmap text, and the requirement is already ticked.

### Required Artifacts

| Artifact | Expected | Status | Details |
|----------|----------|--------|---------|
| `domain/tdee_estimator.dart` (498 lines) | Observed estimator, gates, hysteresis, cadence, material shift | VERIFIED | Substantive, wired via the recalibrator. Pure Dart, no `DateTime.now`. |
| `domain/tdee_trend.dart` | EWMA on an interpolated daily grid | VERIFIED | Used by the estimator. |
| `domain/activity_classifier.dart` | Continuous multiplier | VERIFIED | Used by the recalibrator. |
| `domain/tdee_estimate.dart` | Result type, badge state | VERIFIED | Shared by domain, data, UI. |
| `domain/macro_targets.dart` | bmr / multiplierFor / fromMaintenance split | VERIFIED | `fromProfile` kept as a composition. |
| `domain/activity_reset_policy.dart` | Reset copy and branching | VERIFIED | Used by `ActivityLevelSection`. |
| `data/tdee_estimates_repository.dart` | Persist and read history | VERIFIED | Validates ranges on write and vocabulary on read. |
| `data/tdee_inputs_repository.dart` | Real inputs from drift | VERIFIED | Queries `foodEntries`, `bodyMeasurements`, `healthSamples`, `workoutSessions`. |
| `application/tdee_providers.dart`, `tdee_display_providers.dart` | Estimate, maintenance, saved-target providers | VERIFIED | |
| `application/tdee_recalibration_controller.dart` | Recalibration triggers | VERIFIED | Registered in `app.dart:698`. |
| `presentation/widgets/tdee_estimate_badge.dart`, `sheets/tdee_estimate_sheet.dart` | Badge and detail sheet | VERIFIED | Mounted in the editor. Sheet is read-only. |
| `profile/presentation/widgets/activity_level_section.dart` | Profile reset flow | VERIFIED | Used at `_body.part.dart:441`. |
| Supabase migration SQL | Remote table | VERIFIED as a file | Applied state unknown. |

### Key Link Verification

| From | To | Via | Status | Details |
|------|----|-----|--------|---------|
| `TdeeRecalibrator` | `TdeeEstimator.recalibrate` | `run()` | WIRED | Real inputs in, result written via `_history.record`. |
| `app.dart` | recalibration controller | `ref.watch(tdeeRecalibrationControllerProvider)` | WIRED | Line 698. |
| `latestTdeeEstimateProvider` | `tdeeEstimateProvider` | stream to synthesized estimate | WIRED | Cold start never blank. |
| `tdeeEstimateProvider` | `baselineTargetsProvider` | `fromMaintenance(profile, est.kcal)` | WIRED | |
| Profile activity change | forced recalibration | `before.activityLevel != after.activityLevel` | WIRED | `run(force: true)`. |
| `nutrition_targets_view` | badge and sheet | `const TdeeEstimateBadge()` | WIRED | Line 1599. |
| `TdeeEstimator.isMaterialShift` | any production consumer | none | NOT_WIRED (intentional) | Deferred to Phase 29. |

### Data-Flow Trace (Level 4)

| Artifact | Data Variable | Source | Produces Real Data | Status |
|----------|---------------|--------|--------------------|--------|
| Badge / sheet | `tdeeEstimateProvider` | `tdee_estimates` drift stream, fed by the recalibrator | Yes, real recalibration output | FLOWING |
| Recalibrator | food, weight, steps, workouts | Drift queries in `TdeeInputsRepository` | Yes | FLOWING |
| Classifier | `stepsByDate` | `healthSamples` rows written by `HealthService` | Yes, when Health is connected | FLOWING (needs Health data) |
| Sheet comparison | `savedTargetForTodayProvider` | `nutritionTargetsProvider` resolved for today | Yes | FLOWING |

### Behavioural Spot-Checks

| Behaviour | Command | Result | Status |
|-----------|---------|--------|--------|
| Phase 28 test set (16 files, including `migration_test.dart`) | `flutter test <16 files>` | exit 0, `+252: All tests passed!` | PASS |
| Analyzer | `flutter analyze` | 42 issues, no errors, none in a TDEE file | PASS |
| Observed formula test | `tdee_estimator_test.dart:214` asserts `(2000 - delta*7700/13).round()` | passes | PASS |

I did not re-run the full suite (about 2 minutes); the recorded 1627 pass / 9 skip / 0 fail is 28-11's figure, not mine. The 9 skips are opt-in live-Supabase tests, not new.

### Probe Execution

Step 7c: SKIPPED. No probe scripts are declared in the plans (`scripts/*/tests/probe-*.sh` is not part of this phase).

### Requirements Coverage

Every ID is claimed by at least one plan frontmatter, and the ID set is exactly TDEE-01 to TDEE-05. No orphaned IDs.

| Requirement | Source Plans | Status | Evidence |
|-------------|--------------|--------|----------|
| TDEE-01 | 04, 06, 07, 08, 09, 11 | SATISFIED | Truth 1 |
| TDEE-02 | 01, 02, 06, 07, 10, 11 | SATISFIED | Truth 2 |
| TDEE-03 | 04, 07, 11 | SATISFIED | Truth 3 |
| TDEE-04 | 01, 02, 07, 08, 09, 10, 11 | SATISFIED | Truths 4, 5 |
| TDEE-05 | 03, 04, 05, 06, 07, 11 | PARTIAL | "Never silently rewrites" satisfied. "Surfaced in the weekly report" deferred to Phase 29. Sync half depends on the human item. |

Bookkeeping inconsistency: REQUIREMENTS.md ticks all five TDEE boxes `[x]`, while its traceability table (line 140) still says `TDEE-01–05 | 28 | Pending`. One of the two is wrong.

### Anti-Patterns Found

| File | Line | Pattern | Severity | Impact |
|------|------|---------|----------|--------|
| all TDEE domain, data, application and presentation files | n/a | TODO / FIXME / TBD / XXX / HACK | none | Grep returned nothing. |
| same files | n/a | `DateTime.now()` | none | Clock-injected throughout. |
| `nutrition_targets_view.dart` | n/a | 2618 lines, over the 600 limit | Info | Pre-existing (2617 before). The new code lives in `widgets/` and `sheets/`. |
| `goals_view.dart` `_ActivityLevelSheet` | n/a | Second activity picker has no reset caption or confirm | Warning | Recorded in 28-11 as a known limitation. Behaviour is consistent (the same seed field is written) and only the copy and confirm are missing. |

No blocker anti-patterns and no unreferenced debt markers.

### Behavioural notes on the `hx_stat_tile.dart` change

Plan 28-09 said not to touch it. The diff (`git diff --ignore-all-space`) is two `Flexible` wraps (label, value) plus a fixed `SizedBox(width: HxSpace.x2)` between label and icon bubble. Static reading: for short text `Flexible` (loose fit) sizes to content, so `spaceBetween` positioning is unchanged, and the only difference is a minimum 8px gap and wrapping instead of overflow when text is too long. The other consumers (`macro_grid.dart`, `training_level_view.dart`) are covered by the green suite, and the repo has no golden tests. I judge it behaviour-preserving in intent but only a visual check can confirm it (listed under human verification).

### Human Verification Required

See the `human_verification` list in the frontmatter (six items). The first, the Supabase push, is reported by the user but unverified. I am not marking it passed or failed.

### Gaps Summary

There are no blocking gaps. Status is `human_needed` because of the unverifiable Supabase state and the visual and UX checks, not because a truth failed.

Warnings, none of which block the phase:

1. **TDEE-05 is ticked complete in REQUIREMENTS.md but only half delivered.** Surfacing in the weekly report is Phase 28's deferral to Phase 29. Suggest leaving TDEE-05 explicitly noted as "partial, completed by RPT-01 in Phase 29", or reconciling the checkbox and the "Pending" traceability row.
2. **D-10's accept/dismiss prompt is not in Phase 29's roadmap text.** Phase 29's goal says only "TDEE drift". Add the "Update my target to X / Keep current target" prompt and the `isMaterialShift` diff of `TdeeEstimatesRepository.recent()` to the Phase 29 plan or requirements so it does not fall between phases.
3. **`isMaterialShift` is currently dead in production.** Expected by D-11, but it means the material-shift rule is only test-proven until Phase 29 consumes it.
4. **No background recalibration.** Cadence is opportunistic at open and resume. This is documented and acceptable for the current project capabilities.
5. **Classifier depends on step data**, and the Nutrition goals-sheet activity picker is not relabelled. Both are already recorded in 28-11 as known limitations.
6. **Full suite and `dart format` were not re-run by me.** 28-11 records 62 files that the formatter would change, all outside this phase's code apart from one file it restored.

---

_Verified: 2026-09-28_
_Verifier: Claude (gsd-verifier)_
