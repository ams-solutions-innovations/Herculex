---
phase: 22
slug: primary-lift-strength-specialization
status: draft
nyquist_compliant: false
wave_0_complete: false
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
| 22-01-XX | TBD | TBD | SPEC-01 (D-12 sticking-point branching) | — | Bench/OHP/pull-up's `_needsForPrimaryLift` returns a distinct assistance `_SlotNeed` per sticking point, not one generic `horizontal_pull` slot | unit | `flutter test test/smart_program_planner_test.dart` | ✅ (existing 1378-line file; exercise indirectly via `SmartProgramPlanner.populate()` since `_needsForPrimaryLift`/`_SlotNeed` are private) | ⬜ pending |
| 22-01-XX | TBD | TBD | SPEC-01 (D-01–D-03 split flexibility) | — | Toggling specialization on with an existing Upper/Lower or PPL split keeps that split; incompatible split (e.g. bro split) resets to Full Body/3-day/Linear | widget | `flutter test test/block_builder_view_test.dart` | ✅ existing file covers specialization toggle interactions | ⬜ pending |
| 22-01-XX | TBD | TBD | SPEC-02 (D-04–D-07 volume floor) | — | `VolumeBands.verdicts()` called with a specialization-skewed `computeFromTemplates` breakdown flags at least one `VolumeVerdict.low` group when non-target muscles are starved | unit | `flutter test test/features/programs/volume_bands_test.dart test/program_muscle_volume_test.dart` | ⚠️ W0 — new integration-style test needed combining both files (neither currently exercises them together) | ⬜ pending |
| 22-01-XX | TBD | TBD | SPEC-02 (D-06 Create-time volume-floor check) | — | `_create()` surfaces, but never blocks on, a low-volume warning | widget | `flutter test test/block_builder_view_test.dart` | ✅ file exists, new test cases needed | ⬜ pending |
| 22-01-XX | TBD | TBD | SPEC-03 (D-08–D-10 timeline warning) | — | Picking a shorter-than-recommended weeks value while specialization is active shows a warning and auto-adjusts `_weeks` | widget | `flutter test test/block_builder_view_test.dart` | ✅ file exists, new test cases needed | ⬜ pending |
| 22-01-XX | TBD | TBD | SPEC-03 (D-11 kg-ceiling warning) | — | A target/current kg gap exceeding the experience-tier ceiling shows a warning | unit + widget | new unit test for the ceiling function + widget test for the banner | ❌ W0 — no existing file covers this | ⬜ pending |
| 22-01-XX | TBD | TBD | Dead code cleanup | — | `SquatSpecialization`/`SquatStickingPoint` fully removed, no dangling references | static | `flutter analyze` (0 errors) + `grep -r "SquatSpecialization\|SquatStickingPoint" lib/ test/` (0 matches) | N/A — verification step, not a test file | ⬜ pending |

*Status: ⬜ pending · ✅ green · ❌ red · ⚠️ flaky*
*Task IDs are placeholders (`22-01-XX`) — the planner assigns real plan/wave/task IDs; this map's Requirement/Test/Command columns are locked, the ID columns are not.*

---

## Wave 0 Requirements

- [ ] A new unit test (either a new small `strength_progression_ceiling_test.dart` or an addition to `test/primary_lift_specialization_test.dart`) covering D-11's kg-ceiling function, once its exact home (new function vs. new file) is decided by planning.
- [ ] A new integration-style test combining `ProgramVolumeCalculator.computeFromTemplates` + `VolumeBands.verdicts()` for a specialization-skewed configuration — this is exactly the new D-04 call path and currently has zero coverage.
- [ ] `test/squat_specialization_test.dart` (27 lines) must be **deleted**, not extended — it tests only the dead `SquatSpecialization` class this phase removes.

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
