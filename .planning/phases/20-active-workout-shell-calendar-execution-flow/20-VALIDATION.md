---
phase: 20
slug: active-workout-shell-calendar-execution-flow
status: draft
nyquist_compliant: false
wave_0_complete: false
created: 2026-09-16
---

# Phase 20 — Validation Strategy

> Per-phase validation contract for feedback sampling during execution.

---

## Test Infrastructure

| Property | Value |
|----------|-------|
| **Framework** | `flutter_test` (bundled), `package:test` for pure-Dart unit tests |
| **Config file** | none — standard `flutter test` / `dart test` discovery of `test/**_test.dart` |
| **Quick run command** | `flutter test test/widgets/active_workout_keyboard_test.dart test/widgets/day_detail_sheet_test.dart` |
| **Full suite command** | `flutter test > /tmp/test_output.txt 2>&1; tr '\r' '\n' < /tmp/test_output.txt \| tail -50` (per CLAUDE.md — never pipe directly to `tail`) |
| **Estimated runtime** | ~2 min (baseline: 1308 pass / 4 skipped — expect this count to shift once new tests land) |

---

## Sampling Rate

- **After every task commit:** Run targeted `flutter test test/widgets/<changed>_test.dart`
- **After every plan wave:** Run full suite (`flutter test`, redirected per CLAUDE.md's `\r`-loses-exit-code gotcha)
- **Before `/gsd:verify-work`:** Full suite must be green, `flutter analyze` at 0 errors
- **Max feedback latency:** ~120 seconds (full suite runtime)

---

## Per-Task Verification Map

| Task ID | Plan | Wave | Requirement | Threat Ref | Secure Behavior | Test Type | Automated Command | File Exists | Status |
|---------|------|------|-------------|------------|-----------------|-----------|-------------------|-------------|--------|
| 20-0W-01 | 0W | 0 | FLOW-02 | — | N/A | widget | `flutter test test/widgets/planned_workout_preview_view_test.dart` | ❌ Wave 0 — new file | ⬜ pending |
| 20-0W-02 | 0W | 0 | FLOW-03 | — | N/A | infra | GoRouter test harness helper (new) | ❌ Wave 0 — new infra | ⬜ pending |
| 20-0W-03 | 0W | 0 | FLOW-03 | — | N/A | widget | `flutter test test/widgets/month_calendar_test.dart` | ❌ Wave 0 — no existing test | ⬜ pending |
| 20-01-xx | 01 | 1 | FLOW-01 | — | Nav bar + action bar hide/ignore/exclude-semantics stay in sync via `KeyboardObstructionScope` | widget | `flutter test test/widgets/active_workout_keyboard_test.dart` | ✅ extend in place | ⬜ pending |
| 20-02-xx | 02 | 1-2 | FLOW-02 | T-20-01 | `PlannedWorkoutPreviewView` renders plan without writing to DB; malformed/stale `scheduleId` renders empty/error state, does not throw | widget | `flutter test test/widgets/planned_workout_preview_view_test.dart` | ❌ Wave 0 creates | ⬜ pending |
| 20-03-xx | 03 | 1-2 | FLOW-03 | — | Tapping a specific session opens `DayDetailSheet` scrolled/highlighted to that row, for both `MonthCalendar` and `WeekBoard` call sites | widget | `flutter test test/widgets/month_calendar_test.dart` | ❌ Wave 0 creates | ⬜ pending |
| 20-04-xx | 04 | 2 | FLOW-03 | T-20-02 | done/in-progress → `WorkoutHistoryView(sessionId: completedSessionId)`; planned/moved → `PlannedWorkoutPreviewView`; malformed route id → `_badParam` error screen | widget | `flutter test test/widgets/day_detail_sheet_test.dart` | ✅ rewrite for new routing + GoRouter harness | ⬜ pending |

*Status: ⬜ pending · ✅ green · ❌ red · ⚠️ flaky*

*Exact task IDs are assigned by the planner; this table is the requirement→test contract the planner's tasks must satisfy, not a literal task list.*

---

## Wave 0 Requirements

- [ ] `test/widgets/planned_workout_preview_view_test.dart` — stub covering FLOW-02, including the "no session created on render" assertion (mirror `day_detail_sheet_test.dart`'s existing `fakeService.startCalls == 0` pattern)
- [ ] A minimal `GoRouter` test harness (helper in `test/support/` or inline per-test) — needed by both the FLOW-02 view test and the rewritten FLOW-03 status-routing tests in `day_detail_sheet_test.dart`. No test in this repo currently exercises `go_router`'s `context.push`/`MaterialApp.router` — this is new infrastructure.
- [ ] `test/widgets/month_calendar_test.dart` — new file; `month_calendar.dart` has no dedicated widget test today, and FLOW-03's `_SelectedDayList.onOpenSession(row.id)` wiring (both `MonthCalendar` and `WeekBoard` call sites) needs direct coverage, not just downstream `DayDetailSheet` behavior
- [ ] No framework install needed — `flutter_test` already configured

---

## Manual-Only Verifications

*None — all phase behaviors (FLOW-01, FLOW-02, FLOW-03) have automated widget-test coverage per the map above.*

---

## Validation Sign-Off

- [ ] All tasks have `<automated>` verify or Wave 0 dependencies
- [ ] Sampling continuity: no 3 consecutive tasks without automated verify
- [ ] Wave 0 covers all MISSING references (`planned_workout_preview_view_test.dart`, GoRouter harness, `month_calendar_test.dart`)
- [ ] No watch-mode flags
- [ ] Feedback latency < 120s
- [ ] `nyquist_compliant: true` set in frontmatter

**Approval:** pending
