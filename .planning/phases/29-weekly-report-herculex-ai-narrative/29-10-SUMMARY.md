---
phase: 29-weekly-report-herculex-ai-narrative
plan: 10
subsystem: weekly-report
tags: [notification-tap, deep-link, background-isolate, shared-preferences-queue, cold-start, tdd]

requires:
  - phase: 29-01
    provides: "IsoWeek.forNotificationTap, AppPaths.weeklyReport, AppRoutes.app"
  - phase: 29-04
    provides: "isWeeklyReportPayload / weeklyReportNotificationPayload, NotificationSettings.weeklyReportTimeHHMM"
provides:
  - "WorkoutNotificationService.onWeeklyReportTap and dispatchWeeklyReportPayload (foreground tap, checked before the actionId guard)"
  - "handleWeeklyReportBackgroundTap (background isolate, queues a flag before the actionId guard)"
  - "PendingWeeklyReportOpenQueue (prefs key pending_weekly_report_open)"
  - "WeeklyReportDeepLink.weekForTap / launchedByWeeklyReport / checkColdStart"
  - "app.dart wiring: onWeeklyReportTap assignment, queue drain at start and on resume, one-time cold-start check"
affects: [29-18, 29-20]

tech-stack:
  added: []
  patterns:
    - "Payload-only notification taps are matched before the actionId guard in both callbacks"
    - "Tap path carries no week: the week is resolved at open time from Clock and settings"

key-files:
  created:
    - lib/features/weekly_report/data/weekly_report_action_queue.dart
    - lib/features/weekly_report/application/weekly_report_deep_link.dart
    - test/weekly_report_notification_payload_test.dart
    - test/features/weekly_report/weekly_report_deep_link_test.dart
  modified:
    - lib/services/platform/workout_notification_service.dart
    - lib/app/app.dart

key-decisions:
  - "Background half extracted as top-level handleWeeklyReportBackgroundTap(payload, prefs) so it is unit-testable without a plugin"
  - "Queue is a boolean, not a week: the queued tap is resolved when drained, so a tap queued on Sunday evening and drained on Monday still resolves to the right ISO week"
  - "app.dart does not import clock.dart: app/providers.dart already re-exports clockProvider"

patterns-established:
  - "New notification payload kinds go in the platform service as a dispatch helper plus a prefs queue in the owning feature's data/"

requirements-completed: []
requirements-partial: [RPT-03]

duration: 25min
completed: 2026-10-03
---

# Phase 29 Plan 10: Notification tap deep link Summary

**Tapping the Sunday weekly-report notification now opens the correct week's report route in all three launch situations (app alive, background isolate, cold start), and no callback does any generation, database or AI work.**

## What was built

- `workout_notification_service.dart` (484 to 518 lines): `onWeeklyReportTap` callback, `dispatchWeeklyReportPayload` (true for the weekly marker even with no callback registered), and `handleWeeklyReportBackgroundTap`. In both `onDidReceiveNotificationResponse` and `workoutNotificationTapBackground` the weekly check is the first payload check, ahead of the fasting check and the `actionId` guard (a bare tap has no actionId, so a later check would silently drop it).
- `PendingWeeklyReportOpenQueue`: `isPending`, `enqueue`, `take` (clears and reports whether it was set).
- `WeeklyReportDeepLink`: `weekForTap` delegates to `IsoWeek.forNotificationTap`; `launchedByWeeklyReport` is true only for `didNotificationLaunchApp` with the weekly payload; `checkColdStart` wraps `getNotificationAppLaunchDetails` in try/catch.
- `app.dart` (+32 lines): `_openWeeklyReport` (reads `clockProvider` and `notificationSettingsProvider`, then `router.go(AppRoutes.app)` and `router.push(AppPaths.weeklyReport(isoYear, isoWeek))`), `_drainPendingWeeklyReportOpen` (initState microtask and `_onForeground`), a one-time cold-start microtask, and the `onWeeklyReportTap` assignment next to `onFastingScheduleTap`.

## Task commits

| Task | Commit | Description |
| ---- | ------ | ----------- |
| 1 RED | 86e7315 | failing payload dispatch and queue tests |
| 1 GREEN | 65941b3 | platform-service dispatch plus PendingWeeklyReportOpenQueue |
| 2 RED | 955c75a | failing deep-link helper tests |
| 2 GREEN | 81c86e5 | WeeklyReportDeepLink and app.dart wiring |

## Verification

- `flutter test test/weekly_report_notification_payload_test.dart test/fasting_schedule_payload_test.dart test/features/weekly_report/weekly_report_deep_link_test.dart`: all pass (15 in the two weekly files plus the 3 fasting tests).
- `flutter analyze lib/app/app.dart lib/features/weekly_report lib/services`: no issues. A wider run of `lib/app` also reports two `directives_ordering` infos in `lib/app/providers.dart`; that file is untouched by this plan (pre-existing).
- `dart run tool/check_structure.dart`: 57 violations, the unchanged baseline; none mention weekly_report or workout_notification_service.
- Ordering greps: `handleWeeklyReportBackgroundTap` call (line 26) precedes `final actionId` (line 39) in the background function; `dispatchWeeklyReportPayload` call precedes the foreground actionId check.
- `AppPaths.weeklyReport` appears in `app.dart`; no `'/weekly-report` literal there. `git diff --stat lib/app/app.dart`: 32 insertions (limit 35).

## Deviations from Plan

None - plan executed exactly as written. The `app.dart` clock import was dropped after the analyzer flagged it redundant (providers.dart re-exports `clockProvider`).

## Notes for later plans

- The cold-start path cannot be unit-tested (assumption A10, needs a real launch from a notification) and is a manual UAT item in plan 20. The pure parts (`launchedByWeeklyReport`, `weekForTap`) are covered.
- The fasting-schedule tap path has the same latent cold-start gap (no `getNotificationAppLaunchDetails` check). Out of scope here; not changed.
- The route `AppPaths.weeklyReport` is registered in the router by plan 18; until then a tap would navigate to an unregistered location.

## Known Stubs

None.

## Threat Flags

None. T-29-40 (no work in callbacks), T-29-41 (constant payload, week resolved by the pure resolver), T-29-42 (no data in payload) mitigated as planned; T-29-43 accepted (device UAT in plan 20).

## Self-Check: PASSED

All four created files and two modified files exist; commits 86e7315, 65941b3, 955c75a and 81c86e5 are in git history.
