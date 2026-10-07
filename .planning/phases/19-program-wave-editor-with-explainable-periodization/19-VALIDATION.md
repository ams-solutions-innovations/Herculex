---
phase: 19
slug: program-wave-editor-with-explainable-periodization
status: draft
nyquist_compliant: false
wave_0_complete: false
created: 2026-09-16
---

# Phase 19 — Validation Strategy

> Per-phase validation contract for feedback sampling during execution.

---

## Test Infrastructure

| Property | Value |
|----------|-------|
| **Framework** | `flutter_test` (bundled with Flutter SDK) |
| **Config file** | none — standard `flutter test` discovery over `test/` |
| **Quick run command** | `flutter test test/program_exercise_replacement_scope_test.dart test/program_method_guide_test.dart test/widgets/exercise_replacement_sheet_test.dart` |
| **Full suite command** | `flutter test > /tmp/flutter_test_out.log 2>&1; echo exit=$?` (redirect to a file per CLAUDE.md — do not pipe to `tail`, it loses the exit code; use `tr '\r' '\n'` before grepping) |
| **Estimated runtime** | ~120 seconds |

---

## Sampling Rate

- **After every task commit:** Run `flutter test test/program_exercise_replacement_scope_test.dart test/program_method_guide_test.dart test/widgets/exercise_replacement_sheet_test.dart` (plus any new Wave-0 files as they're created)
- **After every plan wave:** Run full suite (`flutter test`, redirected to a file)
- **Before `/gsd:verify-work`:** Full suite must be green (1308+ pass / 4 skipped baseline — expect growth), plus `flutter analyze` at 0 errors and `dart run tool/check_structure.dart` clean
- **Max feedback latency:** 120 seconds

---

## Per-Task Verification Map

| Task ID | Plan | Wave | Requirement | Threat Ref | Secure Behavior | Test Type | Automated Command | File Exists | Status |
|---------|------|------|-------------|------------|-----------------|-----------|-------------------|-------------|--------|
| 19-01-01 | TBD | 0 | EDIT-01 | — | N/A | widget | `flutter test test/block_detail_view_test.dart` | ❌ W0 | ⬜ pending |
| 19-01-02 | TBD | 0 | EDIT-01 | — | N/A | unit | `flutter test test/wave_label_test.dart` | ❌ W0 | ⬜ pending |
| 19-01-03 | TBD | 1 | EDIT-02 | — | N/A | unit | `flutter test test/program_exercise_replacement_scope_test.dart` | ✅ | ⬜ pending |
| 19-01-04 | TBD | 1 | EDIT-02 | — | N/A | widget | `flutter test test/widgets/exercise_replacement_sheet_test.dart` | ✅ | ⬜ pending |
| 19-01-05 | TBD | 0 | EDIT-03 | — | N/A | unit | `flutter test test/program_exercise_replacement_scope_test.dart` (extend) | ❌ W0 | ⬜ pending |
| 19-01-06 | TBD | 1 | EDIT-04 | — | N/A | unit | `flutter test test/program_method_guide_test.dart` | ✅ (needs new row-count assertion) | ⬜ pending |

*Status: ⬜ pending · ✅ green · ❌ red · ⚠️ flaky*

*No security_enforcement threats apply to this phase (see RESEARCH.md Security Domain — local-first, no new auth/input-validation/session/crypto surface); Threat Ref column is N/A throughout.*

---

## Wave 0 Requirements

- [ ] `test/block_detail_view_test.dart` — new widget test file; covers EDIT-01's Week dropdown/wave-strip rendering and EDIT-02's per-exercise replace trigger wiring
- [ ] `test/wave_label_test.dart` (or co-located with the new domain file) — unit tests for the new anchor-slot wave-label pure function (D-05), including single-wave and block-boundary edge cases
- [ ] Extend `test/program_exercise_replacement_scope_test.dart` (or add a new file) — assert a post-commit `replaceProgramExerciseSlot` + `rematerializeProgram` sequence leaves `in_progress`/`done` `ScheduledWorkouts` rows byte-identical (EDIT-03's explicit safety requirement)
- [ ] Extend `test/program_method_guide_test.dart` — lock in the 8-row (or deliberate exception) count per model per D-06
- [ ] No framework install needed — `flutter_test` is already fully configured

---

## Manual-Only Verifications

*All phase behaviors have automated verification.*

---

## Validation Sign-Off

- [ ] All tasks have `<automated>` verify or Wave 0 dependencies
- [ ] Sampling continuity: no 3 consecutive tasks without automated verify
- [ ] Wave 0 covers all MISSING references
- [ ] No watch-mode flags
- [ ] Feedback latency < 120s
- [ ] `nyquist_compliant: true` set in frontmatter

**Approval:** pending
