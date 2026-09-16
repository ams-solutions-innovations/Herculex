---
phase: 20-active-workout-shell-calendar-execution-flow
plan: 01
subsystem: testing
tags: [go_router, flutter_test, widget-testing, navigation]

# Dependency graph
requires: []
provides:
  - "test/support/go_router_test_harness.dart — GoRouterTestHarness + StubRouteScreen reusable widget-test infra"
  - "Self-tested proof that context.push against a parameterised path resolves to a stub screen with the correct path param, under MaterialApp.router"
affects: [20-03-plan, 20-04-plan]

# Tech tracking
tech-stack:
  added: []
  patterns:
    - "GoRouter widget-test harness: build a real GoRouter from a home builder plus a stubRoutes map, expose MaterialApp.router, assert pushed routes via find.text on a StubRouteScreen label:value string"

key-files:
  created:
    - test/support/go_router_test_harness.dart
    - test/support/go_router_test_harness_test.dart
  modified: []

key-decisions:
  - "Kept the harness file free of the literal string 'AppRoutes.' anywhere, including doc comments, so the zero-occurrence acceptance check holds trivially — not just in code but in prose too."

patterns-established:
  - "GoRouterTestHarness: any future plan needing to test context.push navigation pumps GoRouterTestHarness(home: ..., stubRoutes: {...}).app and asserts via find.text('Label:value') instead of hand-rolling a GoRouter per test."

requirements-completed: [FLOW-02, FLOW-03]

# Metrics
duration: 12min
completed: 2026-09-16
---

# Phase 20 Plan 01: GoRouter Widget-Test Harness Summary

**Reusable `GoRouterTestHarness` + `StubRouteScreen` widget-test infra proving `context.push` against a parameterised path resolves to a stub screen rendering the correct path param — zero dependency on any production `AppRoutes` constant.**

## Performance

- **Duration:** 12 min
- **Started:** 2026-09-16T14:13:00Z
- **Completed:** 2026-09-16T14:25:37Z
- **Tasks:** 2 completed
- **Files modified:** 2 (both new)

## Accomplishments
- Built `GoRouterTestHarness`, wrapping a real `GoRouter` built from a caller-supplied `home` builder plus a `stubRoutes` map (path pattern → builder), exposing `.app` as a ready-to-pump `MaterialApp.router`.
- Built `StubRouteScreen`, a minimal `Scaffold`+`Text` destination whose rendered text encodes `label` or `label:value`, giving tests a single `find.text` assertion target after a push.
- Proved the harness end-to-end with a self-test: tapping a button that calls `GoRouter.of(context).push('/target/42')` resolves to `find.text('Target:42')` finding exactly one widget, and the harness also renders its `home` builder standalone with no `stubRoutes` pushed.
- Closes phase 20 RESEARCH.md Pitfall 2 — no prior test in this repo pumped a widget under `MaterialApp.router` or exercised `context.push`; `DayDetailSheet` tests only ever used a bare `MaterialApp(home: Scaffold(...))`.

## Task Commits

Each task was committed atomically:

1. **Task 1: Create the GoRouter test harness** - `69ca08e` (feat)
2. **Task 2: Self-test the harness** - `c3ea23d` (test)

**Plan metadata:** (this commit)

## Files Created/Modified
- `test/support/go_router_test_harness.dart` - `GoRouterTestHarness` (GoRouter + `MaterialApp.router` builder) and `StubRouteScreen` (assertable stub destination)
- `test/support/go_router_test_harness_test.dart` - Self-test: push+path-param extraction, and standalone `home` rendering with no routes pushed

## Decisions Made
- Wrote the harness before its self-test (rather than a strict RED-first TDD cycle) because Task 1's own acceptance criteria required the file to independently compile and pass `flutter analyze` with zero `AppRoutes.` references — the self-test in Task 2 is the proof-of-mechanism gate, not the mechanism itself. Both tasks kept `tdd="true"`'s spirit: no task was marked done without a passing automated check.
- Avoided the literal string `AppRoutes.` in the harness file's doc comments as well as its code, since the plan's acceptance criteria checks for zero occurrences via source inspection, not just compiled dependency.

## Deviations from Plan

None - plan executed exactly as written.

## Issues Encountered

None.

## User Setup Required

None - no external service configuration required.

## Next Phase Readiness
- Plan 20-03 (FLOW-02) and Plan 20-04 (FLOW-03) can now import `test/support/go_router_test_harness.dart` directly to widget-test `context.push` calls from `DayDetailSheet._viewWorkout` and `PlannedWorkoutPreviewView` without needing real destination screens or `AppRoutes` constants to exist first.
- No blockers.

---
*Phase: 20-active-workout-shell-calendar-execution-flow*
*Completed: 2026-09-16*
