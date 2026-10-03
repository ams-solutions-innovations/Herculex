---
phase: 29-weekly-report-herculex-ai-narrative
plan: 17
subsystem: weekly-report
tags: [flutter, widgets, history, dashboard, analytics, go_router, tdd]

requires:
  - phase: 29-weekly-report-herculex-ai-narrative
    provides: "IsoWeek and route constants (29-01), section widget conventions (29-13), history/enabled/ready providers (29-15)"
provides:
  - "WeeklyReportsHistoryView: newest-first history with unread dot, Narrative pending pill, opt-out banner and empty state"
  - "WeeklyReportsEntryCard (Analytics entry) and WeeklyReportReadyCard (dashboard banner)"
  - "One-widget hooks in insights_view.dart and dashboard_view.dart"
affects: [29-18]

tech-stack:
  added: []
  patterns:
    - "Conditional dashboard banner that owns its own bottom gap, so a hidden card leaves no empty space and the host view gains one line"
    - "Views read providers only; router tests use GoRouterTestHarness with stub routes keyed by the real AppRoutes constants"

key-files:
  created:
    - lib/features/weekly_report/presentation/views/weekly_reports_history_view.dart
    - lib/features/weekly_report/presentation/widgets/weekly_reports_entry_card.dart
    - lib/features/weekly_report/presentation/widgets/weekly_report_ready_card.dart
    - test/features/weekly_report/weekly_reports_history_view_test.dart
  modified:
    - lib/features/analytics/presentation/views/insights_view.dart
    - lib/features/dashboard/presentation/dashboard_view.dart

key-decisions:
  - "The history view sorts by IsoWeek descending itself rather than trusting provider order, so newest-first holds for any source"
  - "The ready card carries its own 24 bottom padding instead of a spacer line in dashboard_view, so there is no gap when it is hidden"
  - "The opt-out banner only navigates to AppRoutes.notifications; it never flips the setting (disclosure lives there)"
  - "Loading and error states in the history are plain labels; no raw exception text"

patterns-established:
  - "Host-view hooks are one import plus one widget line; the widget handles its own visibility and spacing"

requirements-completed: []
requirements-partial: [RPT-01, RPT-04]

duration: 30min
completed: 2026-10-03
---

# Phase 29 Plan 17: History, Analytics entry and dashboard ready card Summary

**A newest-first weekly report history screen plus an Analytics entry card and a dashboard "report ready" banner, hooked into the two large views with 3 and 2 added lines.**

## What was built

- `WeeklyReportsHistoryView` (`presentation/views/`): rows show "Week {n}", a "Mon 28 Sep – Sun 4 Oct" range (intl `DateFormat`), an 8x8 `hx.primary` unread dot with semantics label "Unread" when `viewedAt` is null, and an `HxTextPill` "Narrative pending" when no narrative is stored and the decoded payload `hasNarrativeSignal` (undecodable payloads show no pill and do not crash). Tap pushes `AppPaths.weeklyReport`. Opt-in off shows a "Turn on weekly report" banner pushing `AppRoutes.notifications`, history still visible. Empty state uses the UI-SPEC copy and, when opted in, a 48-high "Open this week's report" button resolving the week from `clockProvider`.
- `WeeklyReportsEntryCard`: `HxCard` "Weekly reports" with chevron, min 48 high, pushes `AppRoutes.weeklyReports`.
- `WeeklyReportReadyCard`: watches `weeklyReportReadyProvider`; `SizedBox.shrink` when null, otherwise an `hx.primary` accented `HxCard` with `Icons.insights`, "Your week {n} report is ready" / "Tap to open", pushing the week's report path. It vanishes reactively when the provider turns null.
- `insights_view.dart` +3 lines (import, card, spacer); `dashboard_view.dart` +2 lines (import, card). No new `DashboardWidgetType`.

## Task commits

| Task | Commit | Description |
| ---- | ------ | ----------- |
| 1 RED | aa7d216 | failing history view test |
| 1 GREEN | 8638caa | WeeklyReportsHistoryView |
| 2 RED | 5279759 | failing entry card and ready card tests |
| 2 GREEN | 6a72120 | entry card, ready card and hooks |

## Verification

- `flutter test test/features/weekly_report/weekly_reports_history_view_test.dart`: 14 passed.
- `flutter test test/features/analytics`: passed. No test in the repo references `DashboardView` or `InsightsView`, so there is no dashboard test folder to run.
- `flutter analyze` on the weekly_report, analytics and dashboard features plus tests: no issues in new code; 2 pre-existing infos in `analytics/domain` (unrelated).
- Greps: no `AppColors.`, `Color(0x`, `appDatabaseProvider`, `DateTime.now` in the new files; no `DashboardWidgetType` under `lib/features/weekly_report`; route constants only.
- TDD gate: `test(...)` commits precede `feat(...)` commits for both tasks.

## Deviations from Plan

### Judgement calls (no rule triggered)

1. **Spacer placement.** The plan asked for a widget plus a spacer in the dashboard column. A fixed spacer would leave a 16-24 gap whenever the card is hidden (the normal state), so the gap lives inside `WeeklyReportReadyCard` instead. The dashboard hook is therefore 2 added lines.
2. **No dashboard test folder.** The plan's verify command lists `test/features/dashboard`, which does not exist; analytics tests were run instead.
3. **Large-file line counts.** insights_view is now 821 lines and dashboard_view 1315 (already over the 600 cap before this plan; the structure checker already lists them). Grown by the minimum possible; splitting them belongs to the UI-rework track.

## Known Stubs

None.

## Threat Flags

None. T-29-69 (malformed payload no crash, tested), T-29-70 (banner navigates to settings only), T-29-71 (banner shows only the week number), T-29-72 (no new dashboard widget type) are mitigated as planned.

## Known limitations

- The ready card still depends on `weeklyReportDueWeekProvider`, which is evaluated at build time: a Sunday trigger passing while the app stays open shows the card only after a rebuild. The resume hook noted in 29-15 is not part of this plan and belongs with plan 18.
- The routes `AppRoutes.weeklyReports` and `AppRoutes.weeklyReport` are not yet registered in `router.dart` (plan 18), so tapping these entries in the running app resolves only once that lands.

## Requirements

RPT-01 and RPT-04 stay unchecked in REQUIREMENTS.md (partial-completion convention): the report view and router registration are plan 18.

## Self-Check: PASSED

Files present: the three new presentation files and the test file. Commits present: aa7d216, 8638caa, 5279759, 6a72120.
