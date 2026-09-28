---
phase: 28
slug: adaptive-tdee-activity-calibration
status: draft
nyquist_compliant: false
wave_0_complete: false
created: 2026-09-28
---

# Phase 28 — Validation Strategy

> Per-phase validation contract for feedback sampling during execution.

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

- **After every task commit:** Run `flutter test test/tdee_estimator_test.dart test/activity_classifier_test.dart test/target_resolver_test.dart` (whichever files the task touched)
- **After every plan wave:** Run `flutter test` (full suite)
- **Before `/gsd:verify-work`:** Full suite must be green, plus `flutter analyze` at 0 errors (exits 1 on warnings too — check the error count, not just exit code)
- **Max feedback latency:** 120 seconds

---

## Per-Task Verification Map

| Task ID | Plan | Wave | Requirement | Threat Ref | Secure Behavior | Test Type | Automated Command | File Exists | Status |
|---------|------|------|-------------|------------|-----------------|-----------|-------------------|-------------|--------|
| 28-TBD | TBD | 0 | TDEE-01 | — | Observed-expenditure formula + D-02 adherence gate produce correct kcal given synthetic intake/weight series | unit | `flutter test test/tdee_estimator_test.dart` | ❌ W0 | ⬜ pending |
| 28-TBD | TBD | 0 | TDEE-01 | — | EWMA gap-fill smoothing matches expected trend for a sparse-log fixture | unit | `flutter test test/tdee_estimator_test.dart` | ❌ W0 | ⬜ pending |
| 28-TBD | TBD | 0 | TDEE-02 | — | Classifier produces a plausible multiplier from a synthetic `HealthSamples` fixture; falls back correctly when adherence fails | unit | `flutter test test/activity_classifier_test.dart` | ❌ W0 | ⬜ pending |
| 28-TBD | TBD | 0 | TDEE-03 | — | Window self-selection picks correct window for varying data density; cadence gate fires only on trigger conditions | unit | `flutter test test/tdee_estimator_test.dart` | ❌ W0 | ⬜ pending |
| 28-TBD | TBD | 0 | TDEE-04 | — | `TargetResolver` still returns the manual `TargetRule` over any `baselineTargetsProvider` value (regression-proves the "never overrides manual" guarantee) | unit | `flutter test test/target_resolver_test.dart` | ❌ W0 | ⬜ pending |
| 28-TBD | TBD | 0 | TDEE-04 | — | Badge shows correct method/confidence copy for each state (observed/classifier/coldStart/stale) | widget | `flutter test test/nutrition_targets_view_test.dart` | Check during planning | ⬜ pending |
| 28-TBD | TBD | 0 | TDEE-05 | — | `isMaterialShift` threshold matches D-09's "bigger of ±100/±5%" rule at boundary values | unit | `flutter test test/tdee_estimator_test.dart` | ❌ W0 | ⬜ pending |
| 28-TBD | TBD | 0 | — | — | drift v45 migration replay (createTable) | integration | `flutter test test/migration_test.dart` | Retarget existing file | ⬜ pending |

*Status: ⬜ pending · ✅ green · ❌ red · ⚠️ flaky*
*Task IDs, Plan IDs, and Wave assignment are finalized by the planner in step 8 — this table is a requirement→test-command map inherited from RESEARCH.md, not a task list.*

---

## Wave 0 Requirements

- [ ] `test/tdee_estimator_test.dart` — stubs for TDEE-01, TDEE-03, TDEE-05
- [ ] `test/activity_classifier_test.dart` — stubs for TDEE-02
- [ ] `test/target_resolver_test.dart` — covers TDEE-04's precondition (pre-existing file gap, not introduced by this phase, but load-bearing for TDEE-04 and currently untested)
- [ ] `test/migration_test.dart` — retarget to v45 with a new replay case (existing file, minor addition per the established v44 pattern)
- [ ] Framework install: none — `flutter_test` already present, no new test dependency needed

---

## Manual-Only Verifications

*None — all phase behaviors have automated verification per the map above. Widget-test coverage for `nutrition_targets_view.dart`'s badge states should be confirmed/extended during planning rather than done manually.*

---

## Validation Sign-Off

- [ ] All tasks have `<automated>` verify or Wave 0 dependencies
- [ ] Sampling continuity: no 3 consecutive tasks without automated verify
- [ ] Wave 0 covers all MISSING references
- [ ] No watch-mode flags
- [ ] Feedback latency < 120s
- [ ] `nyquist_compliant: true` set in frontmatter

**Approval:** pending
