---
phase: 17
slug: deterministic-program-planner-hard-guardrails
status: draft
nyquist_compliant: true
wave_0_complete: false
created: 2026-09-13
---

# Phase 17 — Validation Strategy

> Per-phase validation contract for feedback sampling during execution.

---

## Test Infrastructure

| Property | Value |
|----------|-------|
| **Framework** | `flutter_test` (bundled with Flutter 3.44) |
| **Config file** | none — standard `flutter test` discovery of `test/**/*_test.dart` |
| **Quick run command** | `flutter test test/exercise_programming_eligibility_test.dart test/exercise_scaling_resolver_test.dart test/smart_program_planner_test.dart` |
| **Full suite command** | `flutter test > /tmp/test_output.txt 2>&1` (redirect, don't pipe to `tail`; use `tr '\r' '\n'` before grepping, per CLAUDE.md) |
| **Estimated runtime** | ~2 min full suite (1308 pass / 4 skipped baseline, expected to rise) |

---

## Sampling Rate

- **After every task commit:** Run `flutter test test/exercise_programming_eligibility_test.dart test/exercise_scaling_resolver_test.dart test/smart_program_planner_test.dart`
- **After every plan wave:** Run full suite `flutter test`
- **Before `/gsd:verify-work`:** Full suite must be green, plus `flutter analyze` 0 errors and `dart run tool/check_structure.dart` clean
- **Max feedback latency:** 120 seconds

---

## Per-Task Verification Map

| Task ID | Plan | Wave | Requirement | Threat Ref | Secure Behavior | Test Type | Automated Command | File Exists | Status |
|---------|------|------|-------------|------------|-----------------|-----------|-------------------|-------------|--------|
| 17-01-01 | 01 | 0 | PLAN-04 | — | N/A | unit (stub) | `flutter test test/program_slot_explanations_test.dart` | ❌ W0 | ⬜ pending |
| 17-01-02 | 01 | 1 | PLAN-01 | — | N/A | integration | `flutter test test/smart_program_planner_test.dart` | ✅ (extend) | ⬜ pending |
| 17-01-03 | 01 | 1 | PLAN-02 | — | N/A | unit | `flutter test test/exercise_programming_eligibility_test.dart` | ✅ (extend) | ⬜ pending |
| 17-01-04 | 01 | 1 | PLAN-02 | — | N/A | integration | `flutter test test/smart_program_planner_test.dart` | ✅ (extend, no-throw-on-exhaustion case) | ⬜ pending |
| 17-01-05 | 01 | 1 | PLAN-03 | — | N/A | integration | `flutter test test/smart_program_planner_test.dart` | ✅ (extend, anchor-across-weeks case) | ⬜ pending |
| 17-01-06 | 01 | 1 | PLAN-03 | — | N/A | integration | `flutter test test/smart_program_planner_test.dart` | ✅ (extend, D-12 anchor-break-on-injury case) | ⬜ pending |
| 17-01-07 | 01 | 1 | PLAN-04 | — | N/A | unit + integration | `flutter test test/program_slot_explanations_test.dart test/smart_program_planner_test.dart` | ❌ W0 (created in 17-01-01) | ⬜ pending |
| 17-01-08 | 01 | 1 | PLAN-04 (D-04) | — | N/A | widget | `flutter test test/features/programs/presentation/` (exact file per plan's task breakdown) | ❌ W0, path TBD by planner | ⬜ pending |
| 17-01-09 | 01 | 1 | schema v42 | — | N/A | migration | `flutter test test/migration_test.dart` | ✅ (extend) | ⬜ pending |

*Status: ⬜ pending · ✅ green · ❌ red · ⚠️ flaky*
*(Task IDs above are placeholders — the planner assigns final IDs; the Req ID / Test Type / Command mapping is the binding contract.)*

---

## Wave 0 Requirements

- [ ] `test/program_slot_explanations_test.dart` — stubs for PLAN-04 (`ProgramSlotExplanationData` round-trip, `{slotId, weekIndex}` uniqueness)
- [ ] Migration fixtures for schema v42, generated via `dart run drift_dev schema generate drift_schemas/ test/generated_migrations/` (not hand-written) — covers new `ProgramSlotExplanations` table's `onUpgrade` path
- [ ] Widget test file for the empty-slot UI message (D-04) — exact path depends on where the planner surfaces it in the program day view; the planner's task breakdown must pin this path before Wave 1 begins

---

## Manual-Only Verifications

*None — all phase behaviors have automated verification per the Per-Task Verification Map above. The empty-slot UI message (D-04) has a widget test in Wave 0, so no manual-only fallback is needed.*

---

## Validation Sign-Off

- [ ] All tasks have `<automated>` verify or Wave 0 dependencies
- [ ] Sampling continuity: no 3 consecutive tasks without automated verify
- [ ] Wave 0 covers all MISSING references (`program_slot_explanations_test.dart`, schema v42 migration fixtures, empty-slot widget test)
- [ ] No watch-mode flags
- [ ] Feedback latency < 120s
- [ ] `nyquist_compliant: true` set in frontmatter

**Approval:** pending
