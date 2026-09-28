---
phase: 28
slug: adaptive-tdee-activity-calibration
status: draft
nyquist_compliant: true
wave_0_complete: false
created: 2026-09-28
revised: 2026-09-28
---

# Phase 28 — Validation Strategy

> Per-phase validation contract for feedback sampling during execution.
> Task IDs below are `{plan}-{task}` and were finalized after plan revision (plans 01-11). `wave_0_complete` stays false
> until execution: every test file is created test-first inside its owning task, so there are no missing references.

---

## Test Infrastructure

| Property | Value |
|----------|-------|
| **Framework** | `flutter_test` (bundled with Flutter SDK) + `package:test` conventions, per existing suite |
| **Config file** | none — no `dart_test.yaml` in repo; standard `flutter test` discovery |
| **Quick run command** | `flutter test test/tdee_estimator_test.dart` (new file) |
| **Full suite command** | `flutter test` (CLAUDE.md: ~2min, 1308 pass / 4 skipped baseline — redirect to a file, don't pipe through `tail`) |
| **Estimated runtime** | ~120 seconds (full suite) |

---

## Sampling Rate

- **After every task commit:** Run the task's own `<automated>` command (single test file(s) listed in the map below)
- **After every plan wave:** Run `flutter test` (full suite)
- **Before `/gsd:verify-work`:** Full suite must be green, plus `flutter analyze` at 0 errors (exits 1 on warnings too — check the error count, not just exit code) and `dart run tool/check_structure.dart` with no new violation (600-line rule)
- **Max feedback latency:** 120 seconds

---

## Per-Task Verification Map

| Task ID | Plan | Wave | Requirement | Threat Ref | Secure Behavior | Test Type | Automated Command | File Exists | Status |
|---------|------|------|-------------|------------|-----------------|-----------|-------------------|-------------|--------|
| 28-01-01 | 01 | 1 | TDEE-04 | T-28-02 | Badge label copy per state (locked D-05/D-08 strings), classifier+high clamped to Medium; enum `fromName` falls back safely | unit | `flutter test test/tdee_estimate_test.dart` | ❌ W0 (created in task) | ⬜ pending |
| 28-01-02 | 01 | 1 | TDEE-02 | T-28-01 | Classifier produces a plausible clamped multiplier from a synthetic `HealthSamples` fixture; unavailable below 3 step days (falls through to cold start); never high confidence; active kcal / sleep / resting HR never change the multiplier | unit | `flutter test test/activity_classifier_test.dart` | ❌ W0 (created in task) | ⬜ pending |
| 28-02-01 | 02 | 1 | TDEE-02 | T-28-05, T-28-07 | `MacroTargets.fromProfile` behaviour unchanged after the split; `fromMaintenance` applies the goal delta exactly once | unit | `flutter test test/macro_targets_test.dart` | ❌ W0 (created in task) | ⬜ pending |
| 28-02-02 | 02 | 1 | TDEE-04 | T-28-06 | `TargetResolver` still returns the manual `TargetRule` over any baseline value (regression-proves the "never overrides manual" guarantee) | unit | `flutter test test/target_resolver_test.dart` | ❌ W0 (created in task) | ⬜ pending |
| 28-03-01 | 03 | 1 | TDEE-05 | T-28-08 | `TdeeEstimates` table, v45 upgrade branch, four sync registrations compile | static | `dart analyze lib/data` | n/a | ⬜ pending |
| 28-03-02 | 03 | 1 | TDEE-05 | T-28-08 | drift v45 migration replay (createTable) | integration | `flutter test test/migration_test.dart` | Retarget existing file | ⬜ pending |
| 28-03-03 | 03 | 1 | TDEE-05 | T-28-09, T-28-10 | Sync registration guard; older schema fixtures retargeted | unit | `flutter test test/tdee_sync_registration_test.dart test/schema_v25_test.dart test/schema_v27_test.dart test/schema_v28_test.dart test/schema_v29_test.dart` | ❌ W0 (created in task) | ⬜ pending |
| 28-04-01 | 04 | 2 | TDEE-01, TDEE-03 | T-28-12, T-28-13 | Observed-expenditure formula + D-02 adherence gates produce correct kcal for synthetic fixtures; EWMA gap-fill matches expected trend; window self-selection (35 for 28 dense days, 28 for 24 dense days, 14, null) | unit | `flutter test test/tdee_estimator_test.dart` | ❌ W0 (created in task) | ⬜ pending |
| 28-04-02 | 04 | 2 | TDEE-03, TDEE-05 | T-28-14, T-28-16 | Hysteresis / hold / fallback in `recalibrate`; cadence gate fires only on trigger conditions; `isMaterialShift` matches D-09 at boundary values | unit | `flutter test test/tdee_estimator_test.dart` | ❌ W0 (same file) | ⬜ pending |
| 28-05-01 | 05 | 2 | TDEE-05 | T-28-17, T-28-20 | Supabase migration text guard: owner-only RLS, triggers, index, column parity with drift | unit | `flutter test test/tdee_supabase_migration_test.dart` | ❌ W0 (created in task) | ⬜ pending |
| 28-06-01 | 06 | 3 | TDEE-05 | T-28-22, T-28-23 | `TdeeEstimatesRepository` persists / reads history newest-first, validates enum text | unit | `flutter test test/tdee_estimates_repository_test.dart` | ❌ W0 (created in task) | ⬜ pending |
| 28-06-02 | 06 | 3 | TDEE-01, TDEE-02 | T-28-24 | `TdeeInputsRepository` derives food/weight/steps/workout observations from drift | unit | `flutter test test/tdee_inputs_repository_test.dart` | ❌ W0 (created in task) | ⬜ pending |
| 28-07-01 | 07 | 4 | TDEE-01, TDEE-02, TDEE-04 | T-28-27, T-28-29 | `baselineTargetsProvider` sources maintenance from the estimate, degrades to the exact legacy seed on null/loading/error; a saved rule (2222) beats an estimate (3000) | unit | `flutter test test/features/nutrition/tdee_providers_test.dart` | ❌ W0 (created in task) | ⬜ pending |
| 28-07-02 | 07 | 4 | TDEE-03, TDEE-05 | T-28-28, T-28-30 | Recalibrator runs at open, on ActivityLevel change (forced) and on app resume (non-forced, once per calendar day); never writes `nutrition_targets`; swallows errors; in-flight guard | unit | `flutter test test/features/nutrition/tdee_recalibration_test.dart test/features/nutrition/tdee_providers_test.dart` | ❌ W0 (created in task) | ⬜ pending |
| 28-08-01 | 08 | 5 | TDEE-01, TDEE-04 | T-28-32, T-28-33 | Editor "Maintenance calories" pre-fills from the adaptive estimate (providers pre-warmed in the test), planner uses pure maintenance | widget | `flutter test test/features/nutrition/nutrition_targets_view_test.dart` | Extend existing file | ⬜ pending |
| 28-09-01 | 09 | 6 | TDEE-04 | T-28-35, T-28-36 | Detail sheet shows method, window, confidence, per-method inputs; classifier "used" inputs separate from "Also recorded (not used in the estimate)"; no accept/dismiss | widget | `flutter test test/features/nutrition/tdee_estimate_sheet_test.dart` | ❌ W0 (created in task) | ⬜ pending |
| 28-09-02 | 09 | 6 | TDEE-04 | T-28-38 | Badge shows correct method/confidence copy for each state (measured/aging/classified/calibrating), never blank/error, hidden when no estimate is possible | widget | `flutter test test/features/nutrition/tdee_estimate_badge_test.dart test/features/nutrition/tdee_estimate_sheet_test.dart test/features/nutrition/nutrition_targets_view_test.dart` | ❌ W0 (created in task) | ⬜ pending |
| 28-10-01 | 10 | 5 | TDEE-02, TDEE-04 | T-28-40 | Reset policy: calibrated/measured state, `actionFor` branching, exact D-13/D-14/D-15 copy | unit | `flutter test test/activity_reset_policy_test.dart` | ❌ W0 (created in task) | ⬜ pending |
| 28-10-02 | 10 | 5 | TDEE-02, TDEE-04 | T-28-39, T-28-40 | Profile reset flow: calibrated + different tile shows dialog, Keep leaves selection unchanged, Reset saves and shows the right snackbar (mandatory widget test) | widget | `flutter test test/features/profile/activity_reset_flow_test.dart test/activity_reset_policy_test.dart && flutter analyze lib/features/onboarding lib/features/profile lib/features/nutrition` | ❌ W0 (created in task) | ⬜ pending |
| 28-11-01 | 11 | 7 | TDEE-05 | T-28-43..46 | Supabase migration applied to `ldzgyzigvbwofbswitrv` by the user (checkpoint; no automated command possible) | manual | `human-check` (see plan 11) | n/a | ⬜ pending |
| 28-11-02 | 11 | 7 | TDEE-01..05 | — | Phase-level: full suite, analyzer, structure check, traceability | integration | see plan 11 Task 2 `<automated>` | n/a | ⬜ pending |

*Status: ⬜ pending · ✅ green · ❌ red · ⚠️ flaky*

---

## Wave 0 Requirements

Every test file below is created test-first inside the task that owns it (the tasks are `tdd`), so no task references a test file that does not yet exist.

- [ ] `test/tdee_estimate_test.dart`, `test/activity_classifier_test.dart` — plan 01 (TDEE-02, TDEE-04 copy)
- [ ] `test/macro_targets_test.dart`, `test/target_resolver_test.dart` — plan 02 (TDEE-04 precondition; pre-existing gap for `target_resolver_test.dart`, load-bearing for TDEE-04)
- [ ] `test/migration_test.dart` retarget to v45 with a new replay case, `test/tdee_sync_registration_test.dart`, `test/schema_v25/27/28/29_test.dart` retarget — plan 03
- [ ] `test/tdee_estimator_test.dart` — plan 04 (TDEE-01, TDEE-03, TDEE-05)
- [ ] `test/tdee_supabase_migration_test.dart` — plan 05
- [ ] `test/tdee_estimates_repository_test.dart`, `test/tdee_inputs_repository_test.dart` — plan 06
- [ ] `test/features/nutrition/tdee_providers_test.dart`, `test/features/nutrition/tdee_recalibration_test.dart` — plan 07
- [ ] `test/features/nutrition/nutrition_targets_view_test.dart` (extend), `test/features/nutrition/tdee_estimate_sheet_test.dart`, `test/features/nutrition/tdee_estimate_badge_test.dart` — plans 08-09 (the badge widget test lives under `test/features/nutrition/`, not `test/nutrition_targets_view_test.dart`)
- [ ] `test/activity_reset_policy_test.dart`, `test/features/profile/activity_reset_flow_test.dart` — plan 10
- [ ] Framework install: none — `flutter_test` already present, no new test dependency needed

---

## Manual-Only Verifications

| Behavior | Requirement | Why Manual | Test Instructions |
|----------|-------------|------------|-------------------|
| Apply `supabase/migrations/20260928000000_tdee_estimates_v45.sql` (after outstanding `0015_workout_circuits_and_session_columns.sql` and `0016_exercise_progression_double.sql`) to project `ldzgyzigvbwofbswitrv` | TDEE-05 (sync half) | Needs the user's `SUPABASE_ACCESS_TOKEN` and mutates production; executors never apply migrations (CLAUDE.md) | Plan 11 Task 1 (blocking checkpoint) |

All other phase behaviors have automated verification per the map above.

---

## Validation Sign-Off

- [x] All tasks have `<automated>` verify or Wave 0 dependencies (28-11-01 is a `checkpoint:human-action` with a `human-check`)
- [x] Sampling continuity: no 3 consecutive tasks without automated verify
- [x] Wave 0 covers all MISSING references (each test is created test-first in its owning task)
- [x] No watch-mode flags
- [x] Feedback latency < 120s (per-task commands run single files; the full suite runs per wave)
- [x] `nyquist_compliant: true` set in frontmatter

**Approval:** planner-revised 2026-09-28; pending plan-checker re-verification
