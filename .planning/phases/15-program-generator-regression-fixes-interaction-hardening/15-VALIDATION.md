---
phase: 15
slug: program-generator-regression-fixes-interaction-hardening
status: draft
nyquist_compliant: true
wave_0_complete: false
created: 2026-09-13
---

# Phase 15 — Validation Strategy

> Per-phase validation contract for feedback sampling during execution.

---

## Test Infrastructure

| Property | Value |
|----------|-------|
| **Framework** | Flutter Test / Dart test |
| **Config file** | `pubspec.yaml` |
| **Quick run command** | `flutter test test/smart_program_planner_test.dart` |
| **Full suite command** | `flutter test test/smart_program_planner_test.dart test/planned_session_resolver_test.dart test/scheduled_workout_service_test.dart` |
| **Estimated runtime** | ~15 seconds |

---

## Sampling Rate

- **After every task commit:** Run `flutter test test/smart_program_planner_test.dart` (or task-specific test file)
- **After every plan wave:** Run `flutter test test/smart_program_planner_test.dart test/planned_session_resolver_test.dart test/scheduled_workout_service_test.dart`
- **Before `/gsd-verify-work`:** Full suite must be green
- **Max feedback latency:** 20 seconds

---

## Per-Task Verification Map

| Task ID | Plan | Wave | Requirement | Threat Ref | Secure Behavior | Test Type | Automated Command | File Exists | Status |
|---------|------|------|-------------|------------|-----------------|-----------|-------------------|-------------|--------|
| 15-01-01 | 01 | 1 | FIX-01 | — | Novice linear full-body plans never generate Dynamic Effort sets | unit | `flutter test test/smart_program_planner_test.dart` | ✅ | ⬜ pending |
| 15-01-02 | 01 | 1 | FIX-01 | — | PlannedSessionResolver resolves straight sets matching targetSets for novice linear | unit | `flutter test test/planned_session_resolver_test.dart` | ✅ | ⬜ pending |
| 15-02-01 | 02 | 1 | FIX-02 | — | Replacement modal renders opaque surfaceContainer across light & dark themes | widget | `flutter test test/widgets/exercise_replacement_sheet_test.dart` | ❌ W0 | ⬜ pending |
| 15-02-02 | 02 | 1 | FIX-03 | — | Active workout input focus hides and disables hit-testing on nav bar, Finish and Add buttons | widget | `flutter test test/widgets/active_workout_keyboard_test.dart` | ❌ W0 | ⬜ pending |
| 15-03-01 | 03 | 2 | FIX-04 | — | Calendar day detail launches specific scheduleId and distinguishes Start from Resume | unit | `flutter test test/scheduled_workout_service_test.dart` | ❌ W0 | ⬜ pending |
| 15-03-02 | 03 | 2 | FIX-04 | — | Calendar day detail Start/Resume switches active tab to Workouts tab | widget | `flutter test test/widgets/day_detail_sheet_test.dart` | ❌ W0 | ⬜ pending |

*Status: ⬜ pending · ✅ green · ❌ red · ⚠️ flaky*

---

## Wave 0 Requirements

- [ ] `test/widgets/exercise_replacement_sheet_test.dart` — widget tests asserting opaque `surfaceContainer` across themes
- [ ] `test/widgets/active_workout_keyboard_test.dart` — widget tests asserting immediate hiding & hit-test disabling of navbar, Finish, and Add buttons on input focus
- [ ] `test/scheduled_workout_service_test.dart` — unit tests for multi-schedule day disambiguation and resume idempotency
- [ ] `test/widgets/day_detail_sheet_test.dart` — widget tests for DayDetailSheet tab switching on Start/Resume

---

## Manual-Only Verifications

| Behavior | Requirement | Why Manual | Test Instructions |
|----------|-------------|------------|-------------------|
| Virtual keyboard visual transition fluidity | FIX-03 | Platform soft keyboard animation appearance | Launch app on physical device or emulator, tap weight input, observe bottom navigation and action buttons slide away without overlap. |

---

## Validation Sign-Off

- [x] All tasks have `<automated>` verify or Wave 0 dependencies
- [x] Sampling continuity: no 3 consecutive tasks without automated verify
- [x] Wave 0 covers all MISSING references
- [x] No watch-mode flags
- [x] Feedback latency < 20s
- [x] `nyquist_compliant: true` set in frontmatter

**Approval:** pending 2026-09-13
