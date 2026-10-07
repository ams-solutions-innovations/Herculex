---
phase: 29-weekly-report-herculex-ai-narrative
plan: 15
subsystem: weekly-report
tags: [riverpod, controller, narrative, quota-safety, opt-in, tdd]

requires:
  - phase: 29-weekly-report-herculex-ai-narrative
    provides: "WeeklyReportService and inputs repository (29-14), NarrativeStatus (29-13), notification opt-in settings (29-08), WeeklyReportRepository (29-06)"
provides:
  - "weekly_report_providers.dart: repository/inputs/service providers, weeklyReportProvider(week), weeklyReportHistoryProvider, enabled / due-week / dismissed-week / ready providers"
  - "WeeklyReportController (app-lifetime): open(week), retryNarrative(week), narrationInFlight(week)"
  - "narrativeUiStateProvider family, NarrativeUiState, NarrativeCardModel, narrativeStatusFor"
affects: [29-16, 29-17, 29-18]

tech-stack:
  added: []
  patterns:
    - "Open and narrative futures de-duplicated in per-week maps; in-flight flag set synchronously before the first await"
    - "Controller is the fail-soft layer over a service that does not catch"

key-files:
  created:
    - lib/features/weekly_report/application/weekly_report_providers.dart
    - lib/features/weekly_report/application/weekly_report_controller.dart
    - test/features/weekly_report/weekly_report_providers_test.dart
    - test/features/weekly_report/weekly_report_controller_test.dart
  modified: []

key-decisions:
  - "Controller takes plain callbacks (isEnabled, writeUiState, onDismissedWeek) so it is unit-testable without a container; the provider wires them to Riverpod"
  - "Quota day-gating: same Clock calendar day -> quotaExhausted with Retry off; from the next day the card reads as plain pending with Retry on, so a stale 'try again tomorrow' message is never shown"
  - "An unreadable stored narrative shows pending with Retry off, because the backend is never called again for a row that already holds narrative_json"
  - "NoData stores the dismissed marker for the week that was opened (normally the due week), key weekly_report_dismissed_week, value '<isoYear>-<isoWeek>'"
  - "open() on an opted-out device returns an existing row and still stamps it viewed; it never generates"
  - "Controller and service providers use ref.watch for service/repository/clock/prefs (rebuild only if the DB is swapped) and ref.read for the opt-in flag and UI state, so settings changes never reset the in-flight maps"

patterns-established:
  - "Future.whenComplete with a map remove() must use a block body: remove returns the future being completed and an arrow deadlocks"

requirements-completed: []
requirements-partial: [RPT-01, RPT-03, RPT-04]

duration: 50min
completed: 2026-10-03
---

# Phase 29 Plan 15: Weekly report providers and controller Summary

**Riverpod wiring for the weekly report plus an app-lifetime `WeeklyReportController` that generates a week once on open, fires the AI narrative automatically only on first open, and never re-calls the backend after a failure without an explicit user retry.**

## What was built

- `weekly_report_providers.dart`: `weeklyReportRepositoryProvider`, `weeklyReportInputsRepositoryProvider`, `weeklyReportServiceProvider` (per-day targets via `effectiveTargetsProvider(day).future`, errors become null), `weeklyReportProvider` (StreamProvider.family over `watchWeek`), `weeklyReportHistoryProvider` (StreamProvider over `watchHistory`), `weeklyReportEnabledProvider`, `weeklyReportDueWeekProvider` (via `IsoWeek.forNotificationTap` and `clockProvider`), `weeklyReportDismissedWeekProvider` (seeded from SharedPreferences key `weekly_report_dismissed_week`), `weeklyReportReadyProvider` (dashboard banner state: null while the row is loading, otherwise the due week when there is no row or the row is unviewed).
- `weekly_report_controller.dart`: sealed `WeeklyReportOpenResult` (Ready / NoData / Disabled / Failed); `open` shares one future per week; the row is persisted and stamped viewed before the narrative starts; `_narrate` sets `inFlight` synchronously and is not awaited by `open`; `retryNarrative` is the only path after a failure and shares an in-flight call or returns `alreadySaved`; every service error is converted to a failed outcome in `NarrativeUiState`. `narrativeStatusFor` is a pure mapping (saved -> ready, `loading` only from `ui.inFlight`, offline / quota / pending, skipped -> null). `weeklyReportControllerProvider` is a plain, non-autoDispose `Provider`.
- 34 tests (13 providers, 21 controller) using a Completer-gated fake backend, real repositories on the in-memory database and `FakeClock`.

## Task commits

| Task | Commit | Description |
| ---- | ------ | ----------- |
| 1 RED | 74b22c8 | failing providers test |
| 1 GREEN | f4c9247 | weekly report providers |
| 2 RED | 34f13e4 | failing controller test |
| 2 GREEN | 4a35321 | WeeklyReportController |

## Verification

- `flutter test test/features/weekly_report`: 322 passed (whole folder).
- `flutter analyze lib/features/weekly_report test/features/weekly_report`: no issues. `dart format`: clean. `check_structure` reports nothing for weekly_report.
- Greps: no `weekly_report_providers` import in `lib/features/nutrition`; no `autoDispose` on the controller provider; `weekly_report_dismissed_week` appears in both application files (the key constant lives in the providers file, the controller header comment names it and the controller uses the constant); no file imports `weekly_report_controller.dart` yet (views arrive in plans 17 and 18).
- Call-count assertions: concurrent opens -> 1 backend call; failure then 3 re-opens -> still 1 call and attempts 1; retry -> exactly 1 more call (attempts 2); concurrent retries -> 1 call; after save, open and retry -> 0 calls; opt-in off -> 0 calls and no row.
- TDD gate: `test(...)` commit precedes `feat(...)` for both tasks.

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 1 - Bug] Self-deadlock in the open() de-dupe**
- **Found during:** Task 2 (every test timed out)
- **Issue:** `_open(week).whenComplete(() => _opening.remove(week))` returns the future being completed from the callback, so `whenComplete` waited on itself forever.
- **Fix:** Block-bodied callback with a comment explaining why.
- **Files modified:** weekly_report_controller.dart
- **Commit:** 4a35321

### Notes

- The acceptance grep `grep -c "DateTime.now" weekly_report_controller.dart` prints 1, not 0. The match is the parameter declaration `required DateTime now` in `narrativeStatusFor` (the unescaped `.` matches the space). There is no wall-clock read in the file; all time goes through the injected `Clock` and the `now` argument.
- The plan's `NarrativeUiState` constructor sketch had no `readUiState` getter; the controller only writes UI state, so none was added.

## Known Stubs

None.

## Threat Flags

None. T-29-60 (in-flight maps, attempt counted before the call in the service, auto-fire only at attempts 0, call counts asserted), T-29-61 (opt-in checked first in `open`, tested), T-29-62 (controller touches only the service and `WeeklyReportRepository`) and T-29-63 (all service calls wrapped, tested with a throwing service) are mitigated as planned.

## Known limitations

- `weeklyReportDueWeekProvider` is evaluated when built; if the app stays open across the Sunday trigger the banner appears on the next rebuild (settings change, provider invalidation, restart). A resume hook belongs with the dashboard entry point (plan 18).
- A restart loses the in-memory failure state: a week whose narrative failed shows "pending" with Retry on, which is the intended recovery path.

## Requirements

RPT-01, RPT-03 and RPT-04 stay unchecked in REQUIREMENTS.md (partial-completion convention): views, the TDEE action and the dashboard entry point are plans 16 to 18.

## Hand-off

- Plan 16/17/18 consume: `weeklyReportControllerProvider` (`open`, `retryNarrative`), `narrativeUiStateProvider(week)` together with `narrativeStatusFor(record:, payload: WeeklyReportPayload.tryDecode(record.payloadJson), ui:, now: clock.now())`, `weeklyReportProvider(week)`, `weeklyReportHistoryProvider`, `weeklyReportReadyProvider`.
- Call `open(week)` once when the report screen is entered (the result is `Ready(record)` / `NoData` / `Disabled` / `Failed`); read the live row through `weeklyReportProvider(week)`.

## Self-Check: PASSED

- Files present: both application files and both test files.
- Commits present: 74b22c8, f4c9247, 34f13e4, 4a35321.
