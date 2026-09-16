---
phase: 21
slug: crossfit-gpp-training-tracks
status: draft
nyquist_compliant: false
wave_0_complete: false
created: 2026-09-16
---

# Phase 21 — Validation Strategy

> Per-phase validation contract for feedback sampling during execution.

---

## Test Infrastructure

| Property | Value |
|----------|-------|
| **Framework** | `flutter_test` (existing, per CLAUDE.md commands) |
| **Config file** | none — standard `flutter test` discovery |
| **Quick run command** | `flutter test test/features/programs/... test/features/workouts/... 2>&1 \| tr '\r' '\n'` (redirect to file, per CLAUDE.md — piping to `tail` loses exit code) |
| **Full suite command** | `flutter test > /tmp/test-out.txt 2>&1; tr '\r' '\n' < /tmp/test-out.txt \| tail -50` |
| **Estimated runtime** | ~2 minutes (CLAUDE.md baseline: 1308 pass / 4 skipped, expect growth) |

---

## Sampling Rate

- **After every task commit:** Run targeted `flutter test` on touched test files.
- **After every plan wave:** Run the full `flutter test` suite.
- **Before `/gsd:verify-work`:** Full suite must be green, plus `flutter analyze` at 0 errors (per CLAUDE.md).
- **Max feedback latency:** 120 seconds.

---

## Per-Task Verification Map

| Task ID | Plan | Wave | Requirement | Threat Ref | Secure Behavior | Test Type | Automated Command | File Exists | Status |
|---------|------|------|-------------|------------|-----------------|-----------|-------------------|-------------|--------|
| 21-XX-XX | TBD | TBD | CF-01 | — | Segment tag threads through `ProgramExerciseSlots`→`ProgramDayExercises`→`WorkoutExercises`, ordered correctly | unit | `flutter test test/features/workouts/planned_session_resolver_test.dart` | Verify in planning — resolver-level test likely exists for `slotRole`, needs a segment-parallel case | ⬜ pending |
| 21-XX-XX | TBD | TBD | CF-01 | — | AMRAP/EMOM/For Time formats preserve time caps through materialization | unit | new test in `test/features/workouts/` | ❌ W0 | ⬜ pending |
| 21-XX-XX | TBD | TBD | CF-02 | — | Novice/intermediate/advanced generate different, prerequisite-gated skill/scaling selections | unit | `flutter test test/exercise_scaling_resolver_test.dart` (extend existing file) | ✅ exists, extend | ⬜ pending |
| 21-XX-XX | TBD | TBD | CF-03 | T-21-01 | GPP day never produces `SlotTrainingMethod.dynamicEffort` regardless of periodization model | unit/regression | new test targeting `SmartProgramPlanner` GPP day generation | ❌ W0 | ⬜ pending |
| 21-XX-XX | TBD | TBD | CF-03 | — | Full Body 2×+GPP delivers 2 strength days + GPP content without 8×3 | integration | `flutter test test/features/programs/smart_program_planner_test.dart` (verify/extend) | Verify in planning | ⬜ pending |

*Status: ⬜ pending · ✅ green · ❌ red · ⚠️ flaky*

---

## Wave 0 Requirements

- [ ] Regression test asserting no GPP-labeled day produces `SlotTrainingMethod.dynamicEffort` — covers CF-03's core guarantee explicitly (currently true by construction but untested for this specific case).
- [ ] Test for segment-tag threading through the three-table materialization path (`ProgramExerciseSlots`→`ProgramDayExercises`→`WorkoutExercises`) — covers CF-01.
- [ ] Test for AMRAP/EMOM/For Time time-cap preservation end-to-end (program day → planned snapshot → materialized `WorkoutExercises`/`SetEntries`) — covers CF-01's "time caps preserved" success criterion.
- [ ] Metadata curation: add `prerequisiteSlugs` to `kipping-muscle-up`, `strict-muscle-up`, and all 6 Olympic-tagged exercises (data task, not test, but blocks CF-02's gating from being meaningfully testable against Faza 6's own named examples).

---

## Manual-Only Verifications

*None identified — all phase behaviors have automated verification per the test map above.*

---

## Validation Sign-Off

- [ ] All tasks have `<automated>` verify or Wave 0 dependencies
- [ ] Sampling continuity: no 3 consecutive tasks without automated verify
- [ ] Wave 0 covers all MISSING references
- [ ] No watch-mode flags
- [ ] Feedback latency < 120s
- [ ] `nyquist_compliant: true` set in frontmatter

**Approval:** pending
