---
phase: 29-weekly-report-herculex-ai-narrative
plan: 18
subsystem: weekly-report
tags: [flutter, riverpod, go_router, report-view, routing, lifecycle, tdd]

requires:
  - phase: 29-weekly-report-herculex-ai-narrative
    provides: "IsoWeek and route constants (29-01), section/AI cards (29-13), controller and providers (29-15), TdeeShiftCard (29-16), history view and entry points (29-17)"
provides:
  - "WeeklyReportView({required IsoWeek week}): frozen render of a stored week, generate-on-open, every narrative and empty state"
  - "AppRoutes.weeklyReports / AppRoutes.weeklyReport registered in router.dart with validated path params (buildWeeklyReportRoute)"
  - "weeklyReportResumeProvider: re-reads the due week on app resume"
affects: []

tech-stack:
  added: []
  patterns:
    - "Route builder with untrusted params extracted as a @visibleForTesting top-level function so the production builder is exercised under a minimal GoRouter"
    - "Open once from a post-frame callback in initState; live data through a StreamProvider, never .first"

key-files:
  created:
    - lib/features/weekly_report/presentation/views/weekly_report_view.dart
    - lib/features/weekly_report/application/weekly_report_resume.dart
    - test/features/weekly_report/weekly_report_view_test.dart
    - test/features/weekly_report/weekly_report_resume_test.dart
  modified:
    - lib/app/router/router.dart
    - lib/app/app.dart
    - test/features/weekly_report/weekly_report_routes_test.dart

key-decisions:
  - "buildWeeklyReportRoute is a top-level @visibleForTesting function in router.dart (route params validated by _intParam then IsoWeek.tryCreate; impossible weeks reach _badParam)"
  - "The view keeps the controller's open result in local state only to pick the empty-state face (NoData / Failed / Disabled) when no row exists; a stored row always wins"
  - "Opt-in off with no row shows 'Turn on weekly report' (pushes AppRoutes.notifications) without waiting for the open result"
  - "The app-resume hook lives in its own small file (weekly_report_resume.dart) and is wired with one watch line in app.dart, instead of editing weekly_report_providers.dart"

patterns-established:
  - "Views use HxScreenShell title 'Week {n}' plus a label-sized Mon-Sun range line"

requirements-completed: [RPT-01, RPT-02, RPT-03, RPT-04, RPT-05]

duration: 45min
completed: 2026-10-03
---

# Phase 29 Plan 18: Weekly report screen, routes and resume hook Summary

**The weekly report screen (frozen measured cards, TDEE card only when material, one distinct Herculex AI card), generate-on-open through the controller, both routes registered with validated ISO-week params, and an app-resume hook so the dashboard card catches the Sunday trigger.**

## What was built

- `WeeklyReportView` (`presentation/views/`, 252 lines): `HxScreenShell` titled "Week {n}" with a Mon-Sun range label. `initState` schedules `controller.open(week)` once after the first frame; the live row comes from `weeklyReportProvider(week)`. With a row: payload decoded strictly (`fromJsonString` in try/catch, failure shows "Couldn't load this report. Go back and open it again." with an `hx.danger` icon), "Snapshot from {date}" for weeks other than the current one, then Nutrition, Training, Recovery, Physique, `TdeeShiftCard` only when `tdee != null && tdee.material`, a 32 gap and `AiNarrativeCard` built from `narrativeStatusFor` (nothing when the model is null). Retry calls `retryNarrative(week)` on tap only. Without a row: opt-in off shows "Turn on weekly report"; `NoData` shows "No data this week"; `Failed` shows the error copy; otherwise a loading label.
- Routes: `AppRoutes.weeklyReports` -> `WeeklyReportsHistoryView`; `AppRoutes.weeklyReport` -> `buildWeeklyReportRoute` (`_intParam`, `IsoWeek.tryCreate`, `_badParam`). The Sunday notification deep link and the history/entry/ready-card pushes now land on real screens.
- `weeklyReportResumeProvider` (new `weekly_report_resume.dart`): a `WidgetsBindingObserver` that invalidates `weeklyReportDueWeekProvider` on `AppLifecycleState.resumed`. Wired in `app.dart` with one import and one `ref.watch`. Closes the limitation noted in 29-15 and 29-17.

## Task commits

| Task | Commit | Description |
| ---- | ------ | ----------- |
| 1 | 910b76c | WeeklyReportView and 21 view tests |
| 2 | 82436cd | Route registration, `buildWeeklyReportRoute`, extended routes test (11 tests) |
| extra | 2747f09 | Resume hook, wiring and 3 tests |

## Verification

- `flutter test test/features/weekly_report`: 406 passed (whole folder).
- `flutter analyze lib/app lib/features/weekly_report test/features/weekly_report`: 0 errors; 2 pre-existing `directives_ordering` infos in `lib/app/providers.dart` (not touched).
- `dart run tool/check_structure.dart`: nothing reported for weekly_report or router.dart.
- Greps on the view: no `appDatabaseProvider`, `package:drift`, `DateTime.now`, `AppColors.`, `Color(0x`, `.first`; 252 lines (< 600). `'/weekly-report` literals appear only in `routes.dart`.
- Routes test approach: registration is asserted on the real `routerProvider` configuration (with `profileProvider` overridden to an empty stream), and param handling by pumping a minimal `GoRouter` that uses the production builder `buildWeeklyReportRoute`, since the full app router redirects away to onboarding without a profile. Cases: `/weekly-reports`, `/weekly-report/2026/40` (week equals `IsoWeek(2026, 40)`), and bad params `2026/99`, `2026/0`, `abc/40`, `2026/xyz`, `2027/53` all show `AppErrorScreen` and never the view.

## Deviations from Plan

### Auto-fixed Issues

None needing rules 1-3.

### Judgement calls

1. **Resume hook added (not a plan task).** Requested by the 29-15/29-17 hand-off notes and the orchestrator. Own file plus one watch line in `app.dart` (830 lines, already over the 600 cap; grown by 3 lines). The hook only invalidates a read-only provider.
2. **TDD ordering.** The view was written before its test in one pass, so there is no separate failing-test commit for Task 1 or the resume hook; tests and implementation were committed together. All behaviours in the plan's behavior block are covered by passing tests.
3. **"Exactly one hx.primary-tinted card" check is scoped.** In every palette `domainTraining` has the same colour value as `primary` (design-system property, used by the plan 13 Training card), so a tree-wide primary-colour count finds the Training card too. The test instead asserts the AI card contains exactly one primary-tinted card and that the Nutrition, Recovery and TDEE cards contain none. The AI card is otherwise told apart by pill, glyph and position.
4. **Title/range.** `HxScreenShell` renders the title in its own pill, so "Week {n}" is the shell title (not a separate 28/600 Display text); the range is a 14/400 line below.
5. **Resume hook placement** in a new file rather than `weekly_report_providers.dart`, to keep that file untouched.

## Known Stubs

None.

## Threat Flags

None. T-29-73 (`_intParam` + `IsoWeek.tryCreate`, tested incl. week 99/0/53 in a 52-week year), T-29-74 (strict parse in try/catch, tested with `payloadVersion: 99`), T-29-75 (view reads only the stored payload; test overrides `savedTargetForTodayProvider` to a different value and asserts it never appears) and T-29-76 (single `open` from `initState`, retry only on tap, asserted by call-count) are mitigated as planned.

## Requirements

RPT-01 to RPT-05 are now complete across plans 01 to 18 (measured sections, distinct AI card, generate-on-open with notification deep link, frozen history, TDEE confirm card).

## Self-Check: PASSED

Files present: view, resume provider, three test files, router.dart and app.dart edits. Commits present: 910b76c, 82436cd, 2747f09.
