---
phase: 29-weekly-report-herculex-ai-narrative
plan: 08
subsystem: notifications
tags: [riverpod, flutter_local_notifications, settings-ui, gdpr, privacy, opt-in]

requires:
  - phase: 29-weekly-report-herculex-ai-narrative
    provides: "29-04 NotificationSettings.weeklyReportEnabled/weeklyReportTimeHHMM and WeeklyReportNotificationScheduler (id 5001)"
provides:
  - "NotificationSettingsNotifier.setWeeklyReportEnabled / setWeeklyReportTime"
  - "weeklyReportNotificationSchedulerProvider (Clock-injected)"
  - "NotificationSyncService._syncWeeklyReport in the settings listener and syncAll()"
  - "Weekly report toggle, Report Time row and AI processing disclosure in notification settings"
  - "weekly_reports documented in PRIVACY_POLICY, GDPR_ARTICLE_9_COMPLIANCE and DATA_TRUTH_TABLE"
affects: [29-10 notification tap path, 29-09 history empty-state copy that points at this toggle]

tech-stack:
  added: []
  patterns:
    - "New private _TimePillRow widget in the view for time rows (daily-log row left untouched)"
    - "Sync-service tests drive the real notifier with a fake plugin and a fixed Clock"

key-files:
  created:
    - test/features/notifications/weekly_report_sync_test.dart
  modified:
    - lib/features/notifications/application/notification_settings_provider.dart
    - lib/features/notifications/data/notification_sync_service.dart
    - lib/features/notifications/presentation/notification_settings_view.dart
    - test/features/notifications/notification_settings_provider_test.dart
    - test/features/notifications/notification_settings_view_test.dart
    - docs/PRIVACY_POLICY.md
    - docs/GDPR_ARTICLE_9_COMPLIANCE.md
    - docs/DATA_TRUTH_TABLE.md

key-decisions:
  - "Disclosure sentence is always visible in the toggle sub-label (not only once on), so the user reads it before opting in"
  - "Weekly report sits in its own card directly under the Daily Habits & Log card, with no new section header"
  - "Time pill uses hx.primaryText (not hx.primary) for 4.5:1 contrast per the UI spec, with a 48 high tap target"

patterns-established:
  - "Sync-service behaviour test: ProviderContainer with appDatabaseProvider, sharedPreferencesProvider, localNotificationsPluginProvider and clockProvider overrides"

requirements-completed: []
requirements-partial: [RPT-01, RPT-03]

duration: 35min
completed: 2026-10-03
---

# Phase 29 Plan 08: Weekly Report Opt-in Wiring Summary

**Notification settings now carry a Weekly report toggle and Report Time row that schedule/cancel the Sunday notification live and at launch, with the Herculex AI (Google Gemini) processing disclosed in the UI and in three privacy documents.**

## Accomplishments
- Notifier setters, `weeklyReportNotificationSchedulerProvider` (injects `clockProvider`, so Sunday math goes through Clock), and `_syncWeeklyReport` in the listener and `syncAll()` (reboot path). Errors are swallowed like the other schedulers (T-29-34).
- Settings screen: "Weekly report" switch (`Icons.insights_outlined`), sub-label "Sundays at HH:MM." plus the disclosure, and a "Report Time" row (shown only when on) that opens `showTimePicker` initialised to the stored time (default 18:00).
- Docs: `weekly_reports` described as opt-in, off by default, synced, GDPR Art. 9, removed on account deletion and local wipe, with aggregate-only Gemini processing. Open decision on explicit AI consent (`privacyConsent`) recorded as an unchecked item in the GDPR memo.

## Task Commits
1. **Task 1: setters, scheduler provider, sync wiring** - `60e067f` (feat)
2. **Task 2: toggle and time row in settings view** - `8430ed1` (feat)
3. **Task 3: privacy, GDPR and data-truth docs** - `7d34582` (docs)

Task 1 and 2 tests were written first and confirmed failing as compile errors before implementation.

## Verification
- `flutter test test/features/notifications/` 40/40 pass.
- `flutter analyze lib/features/notifications test/features/notifications` no issues.
- `dart run tool/check_structure.dart` 57 violations, the unchanged baseline.
- `notification_settings_view.dart` is 596 lines (limit 600). No `AppColors.`/`Color(0x` in the added lines.

## For the owner to confirm (flagged)
- **Disclosure wording names the processor** ("A numeric summary of your week is processed by Herculex AI (powered by Google Gemini) to write the summary."). This deliberately breaks the KB-03 "Herculex AI only" copy rule because consent genuinely requires naming the third-party processor. Please confirm or reword.
- **Open consent decision** (GDPR memo): whether an explicit AI-processing consent step (`privacyConsent`) is needed for weekly aggregates (Phase 29 open question 5). Currently the toggle is the only consent surface.

## Deviations from Plan

### Auto-fixed / small adjustments

**1. [Rule 3 - structure] New `_TimePillRow` widget instead of cloning the daily-log row inline**
- Cloning the daily-log row inline would have pushed the file past 600 lines. A small private widget keeps the addition contained. The file still ends at 596 lines, so the next edit to this view should extract a `part` file or trim.

**2. [Test scope] Time picker test confirms the dialog and OK path; 19:30 is set via the notifier**
- The plan allowed asserting through the notifier if the suite does not drive pickers. The test opens `TimePickerDialog`, confirms (time stays 18:00), then sets 19:30 via the notifier and asserts the subtitle and pill update.

**3. [Test detail] Persisted-settings key** - the syncAll reboot test seeds `app_notification_settings_v1` (the repository's actual key).

Otherwise the plan was executed as written.

## Known Stubs
None.

## Threat Flags
None beyond the plan's threat model. T-29-32 mitigated (disclosure, docs, default off); T-29-34 mitigated (errors swallowed, covered by test); T-29-35 inherited from plan 04 (generic copy). T-29-33 accepted as planned.

## Next Phase Readiness
The opt-in is functional end to end for scheduling. RPT-01/RPT-03 stay partial: the notification tap route (plan 10) and report generation remain.

## Self-Check: PASSED
All created/modified files exist; commits `60e067f`, `8430ed1`, `7d34582` found in git log.
