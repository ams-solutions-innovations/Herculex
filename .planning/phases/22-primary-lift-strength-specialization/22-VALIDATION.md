---
phase: 22
slug: primary-lift-strength-specialization
status: draft
nyquist_compliant: false
wave_0_complete: true
created: 2026-09-30
---

# Phase 22 — Validation Strategy

> Per-phase validation contract for feedback sampling during execution.

---

## Test Infrastructure

| Property | Value |
|----------|-------|
| **Framework** | `flutter_test` (bundled with Flutter 3.44 SDK) |
| **Config file** | none — standard `flutter test` discovery over `test/` |
| **Quick run command** | `flutter test test/primary_lift_specialization_test.dart test/program_guardrails_test.dart test/features/programs/volume_bands_test.dart` |
| **Full suite command** | `flutter test > test_output.txt 2>&1` (redirect per CLAUDE.md — do not pipe to `tail`; `tr '\r' '\n'` before grepping progress output) |
| **Estimated runtime** | ~120 seconds (full suite, per CLAUDE.md's ~2min baseline) |

---

## Sampling Rate

- **After every task commit:** Run the quick-run command above (specialization/guardrail/volume-bands unit tests), plus `flutter analyze` on touched files.
- **After every plan wave:** `flutter test test/smart_program_planner_test.dart test/block_builder_view_test.dart test/program_guardrails_test.dart test/features/programs/volume_bands_test.dart test/program_muscle_volume_test.dart` plus full-repo `flutter analyze` (0 errors).
- **Before `/gsd:verify-work`:** Full suite must be green — target 1721+ passed (Phase 27's last recorded STATE.md baseline) plus this phase's new tests, 0 failures.
- **Max feedback latency:** 120 seconds.

---

## Per-Task Verification Map

| Task ID | Plan | Wave | Requirement | Threat Ref | Secure Behavior | Test Type | Automated Command | File Exists | Status |
|---------|------|------|-------------|------------|-----------------|-----------|-------------------|-------------|--------|
| 22-01 Task 1 | 22-01 | 1 | D-12 branching (SPEC-01) + dead-code removal | — | Bench/OHP/pull-up's `_needsForPrimaryLift` returns a distinct assistance `_SlotNeed` per sticking point, not one generic `horizontal_pull` slot; `SquatSpecialization`/`SquatStickingPoint` fully removed, no dangling references | unit + static | `flutter test test/smart_program_planner_test.dart` + `flutter analyze` (0 errors) + `grep -r "SquatSpecialization\|SquatStickingPoint" lib/ test/` (0 matches) | ✅ (existing 1378-line file; exercise indirectly via `SmartProgramPlanner.populate()` since `_needsForPrimaryLift`/`_SlotNeed` are private); `test/squat_specialization_test.dart` deleted | ⬜ pending |
| 22-01 Task 2 | 22-01 | 1 | Guardrail functions (SPEC-02 D-04/D-06 + SPEC-03 D-11, partial) | — | `ProgramGuardrails.validateVolumeFloor`/`validateKgIncrease` return `warning`-severity issues matching UI-SPEC copy, mirroring `validateConfiguration()`'s shape | unit | `flutter test test/program_guardrails_test.dart` | ✅ file exists, new test group added (kg-ceiling unit test, Wave 0 gap) | ⬜ pending |
| 22-02 Task 1 | 22-02 | 1 | Split-flexibility (SPEC-01 D-01–D-03) + exposures-text fix (Pitfall 3) | — | Toggling specialization on with an existing Upper/Lower or PPL split (including `upperLowerFullBody`, excluding `fullBodyAbGpp`) keeps that split; incompatible split (e.g. bro split) resets to Full Body/3-day/Linear; exposures/week text computed from `_plan`, not hardcoded `3` | widget | `flutter test test/block_builder_view_test.dart` | ✅ existing file covers specialization toggle interactions | ⬜ pending |
| 22-03 Task 1 | 22-03 | 2 | Timeline warning (SPEC-03 D-08–D-10) | — | Picking a shorter-than-recommended weeks value while specialization is active shows an inline "Not enough time" warning and auto-adjusts `_weeks` to the recommended value | widget | `flutter test test/block_builder_view_test.dart` | ✅ file exists, new test cases added | ⬜ pending |
| 22-03 Task 2 | 22-03 | 2 | Kg-ceiling warning, sheet half (SPEC-03 D-11) | — | The Weeks-picker sheet shows a "That's a big jump" banner whenever the active specialization's kg increase exceeds its experience-tier ceiling, independent of the weeks-shortfall check | widget | `flutter test test/block_builder_view_test.dart` | ✅ file exists, new test cases added | ⬜ pending |
| 22-04 Task 1 | 22-04 | 3 | Volume-floor live preview (SPEC-02 D-04, D-06 live half, D-07) | — | `VolumeBands.verdicts()` called with a specialization-skewed `computeFromTemplates` breakdown flags at least one `VolumeVerdict.low` group when non-target muscles are starved, rendered as "Light" in `SpecializationVolumeFloorCard` inside the Schedule step's `_summaryCard` | unit + widget | `flutter test test/features/programs/volume_bands_test.dart test/program_muscle_volume_test.dart test/specialization_volume_floor_card_test.dart` | ✅ Wave 0 gap closed — new `computeFromTemplates` + `VolumeBands.verdicts` integration test added to `test/program_muscle_volume_test.dart` | ⬜ pending |
| 22-04 Task 2 | 22-04 | 3 | Create-time check (SPEC-02 D-06 Create-time half, D-07; SPEC-03 D-11 Create-time half) | — | `_create()` surfaces, but never blocks on, a combined volume-floor + kg-increase warning whenever specialization is active and either issue is flagged; declining cancels cleanly, confirming proceeds exactly as before | widget | `flutter test test/block_builder_view_test.dart` | ✅ file exists, new test group added (`'D-06/D-11 Create-time specialization warnings (22-04)'`) | ⬜ pending |

*Status: ⬜ pending · ✅ green · ❌ red · ⚠️ flaky*
*Task IDs reflect the final 4-plan set (22-01 through 22-04) as of the plan-checker revision, 2026-10-02.*

---

## Wave 0 Requirements

- [x] A new unit test covering D-11's kg-ceiling function — lands in `22-01 Task 2`'s
      `program_guardrails_test.dart` group (`ProgramGuardrails.validateKgIncrease`), not a separate
      new file.
- [x] A new integration-style test combining `ProgramVolumeCalculator.computeFromTemplates` +
      `VolumeBands.verdicts()` for a specialization-skewed configuration — lands in `22-04 Task 1`'s
      new case in `test/program_muscle_volume_test.dart` (`'computeFromTemplates feeding into
      VolumeBands.verdicts flags a below-floor muscle group'`).
- [x] `test/squat_specialization_test.dart` (27 lines) deleted, not extended — handled by
      `22-01 Task 1`.

---

## Manual-Only Verifications

*None — all phase behaviors have automated verification per the map above.*

---

## Validation Sign-Off

- [ ] All tasks have `<automated>` verify or Wave 0 dependencies
- [ ] Sampling continuity: no 3 consecutive tasks without automated verify
- [ ] Wave 0 covers all MISSING references (kg-ceiling unit test, volume-floor integration test)
- [ ] No watch-mode flags
- [ ] Feedback latency < 120s
- [ ] `nyquist_compliant: true` set in frontmatter

**Approval:** pending
