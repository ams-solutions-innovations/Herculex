---
phase: 29-weekly-report-herculex-ai-narrative
plan: 04
subsystem: notifications
tags: [flutter_local_notifications, timezone, clock, weekly-report, opt-in]

requires:
  - phase: 29-weekly-report-herculex-ai-narrative
    provides: "29-01 IsoWeek.forNotificationTap (tap-time week resolution, used by plan 10)"
provides:
  - "NotificationSettings.weeklyReportEnabled (default false) and weeklyReportTimeHHMM (default 18:00), back-compatible JSON"
  - "WeeklyReportNotificationScheduler (channel weekly_report, id 5001, Sunday dayOfWeekAndTime, Clock-injected)"
  - "weeklyReportNotificationPayload / isWeeklyReportPayload in plain-Dart weekly_report/domain"
affects: [29-08 toggle UI and NotificationSyncService wiring, 29-10 notification tap path]

tech-stack:
  added: []
  patterns:
    - "Scheduler takes an injectable Clock; 'now' is tz.TZDateTime.from(clock.now(), tz.local), never TZDateTime.now"
    - "Repeating schedule carries one static payload; target week resolved at tap time"

key-files:
  created:
    - lib/features/notifications/data/weekly_report_notification_scheduler.dart
    - lib/features/weekly_report/domain/weekly_report_notification_payload.dart
    - test/features/notifications/notification_settings_weekly_test.dart
    - test/features/notifications/weekly_report_scheduler_test.dart
  modified:
    - lib/features/notifications/domain/notification_settings.dart

key-decisions:
  - "Notification text is generic (no numbers, no emoji): nothing sensitive on the lock screen (T-29-14)"
  - "HH:MM is range-checked (0-23, 0-59) in addition to int.tryParse, so '25:00' schedules nothing instead of rolling over (T-29-15)"
  - "nextSunday builds candidates with the calendar TZDateTime constructor, not add(Duration), so DST cannot shift wall-clock time"

patterns-established:
  - "Weekly-report scheduler test reuses FakeLocalNotificationsPlugin from notification_schedulers_test.dart via import rather than forking it"

requirements-completed: []
requirements-partial: [RPT-01, RPT-03]

duration: 25min
completed: 2026-10-03
---

# Phase 29 Plan 04: Weekly Report Notification Scheduler Summary

**Opt-in Sunday weekly-report notification: settings fields (default off, 18:00) plus a Clock-injected `dayOfWeekAndTime` scheduler on id 5001 with a static `weekly_report` payload and generic lock-screen copy.**

## Performance

- **Tasks:** 2/2
- **Files:** 5 (2 lib created, 1 lib modified, 2 test created)

## Accomplishments
- `NotificationSettings` gained `weeklyReportEnabled` (false) and `weeklyReportTimeHHMM` ('18:00') in constructor, copyWith, toJson and fromJson. Old blobs and wrong-typed values (`'yes'`, `1800`) fall back to defaults without throwing.
- `WeeklyReportNotificationScheduler` cancels first, returns when disabled or the time is malformed, and otherwise schedules the first Sunday at HH:MM with `DateTimeComponents.dayOfWeekAndTime`, exact-then-inexact fallback, swallowed errors.
- Payload constant lives in `weekly_report/domain` (no Flutter import) so the platform service can use it without importing UI.

## Task Commits

1. **Task 1: NotificationSettings weekly-report fields** - `0f70777` (feat)
2. **Task 2: Payload constant and scheduler** - `8aa28e7` (feat)

Tests were written first in each task (RED confirmed as compile errors against the missing members) and committed together with the implementation.

## Verification
- `flutter test test/features/notifications/` 30/30 pass (includes the pre-existing scheduler and settings tests).
- `flutter analyze lib/features/notifications lib/features/weekly_report test/features/notifications` no issues.
- `dart run tool/check_structure.dart` 57 violations, the unchanged baseline; all new files are small.
- Acceptance greps: `notifId = 5001` present and the only use of 5001 in `lib`; no non-comment `DateTime.now`/`TZDateTime.now`; `Clock` appears 3 times; `dayOfWeekAndTime` and `weeklyReportNotificationPayload` present; payload file has no `package:flutter` import.

## Deviations from Plan

### Auto-fixed / small adjustments

**1. [Rule 2 - Input validation] Range check on parsed HH:MM**
- **Issue:** The daily-log analog only checks `int.tryParse`; `'25:00'` would roll into the next day via the `TZDateTime` constructor and still schedule.
- **Fix:** Added `hour < 0 || hour > 23 || minute < 0 || minute > 59` guard, satisfying the plan's "malformed time schedules nothing" behavior and T-29-15. Covered by the test with `'25:00'` and `'18:99'`.

**2. [Rule 3 - Acceptance grep] Renamed `nextSunday` parameter `now` to `after`**
- The plan's own acceptance regex `DateTime.now` (unescaped dot) false-matched `TZDateTime now,` in the signature. Renaming satisfies the grep with no behavior change.

Otherwise the plan was executed as written.

## Issues Encountered
None blocking.

## Known Stubs
None. The scheduler is intentionally not yet wired: the Riverpod provider and `NotificationSyncService` hookup belong to plan 08, and the tap route to plan 10.

## Threat Flags
None beyond the plan's threat model.

## Next Phase Readiness
Plan 08 can add the toggle UI and call `WeeklyReportNotificationScheduler.reschedule` from `NotificationSyncService`; plan 10 can match `isWeeklyReportPayload` in the platform notification tap handler. RPT-01/RPT-03 stay unchecked in REQUIREMENTS.md (partial-completion convention): no toggle, wiring or tap path exists yet.

## Self-Check: PASSED
All five files exist; commits `0f70777` and `8aa28e7` found in git log.
