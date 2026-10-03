import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:herculex/features/weekly_report/domain/iso_week.dart';
import 'package:herculex/features/weekly_report/domain/weekly_report_notification_payload.dart';

/// Pure helpers for opening the weekly report from the Sunday notification.
///
/// Nothing here generates a report, touches the database or calls AI: the tap
/// path only resolves which week to show and navigates (RPT-03). Generation
/// happens in the report view's controller once the route is open.
abstract final class WeeklyReportDeepLink {
  /// The week a tap should open. Resolved at tap time, never from the payload.
  static IsoWeek weekForTap({
    required DateTime now,
    required String timeHHMM,
  }) => IsoWeek.forNotificationTap(now, timeHHMM);

  /// True only when the notification that launched the app was the weekly one.
  static bool launchedByWeeklyReport(NotificationAppLaunchDetails? details) {
    if (details == null || !details.didNotificationLaunchApp) return false;
    return isWeeklyReportPayload(details.notificationResponse?.payload);
  }

  /// Cold start: the plugin does not fire `onDidReceiveNotificationResponse`
  /// for the tap that launched the app, so ask it once at startup. Any plugin
  /// failure (missing channel in tests, unsupported platform) means "no".
  static Future<bool> checkColdStart(
    FlutterLocalNotificationsPlugin plugin,
  ) async {
    try {
      return launchedByWeeklyReport(
        await plugin.getNotificationAppLaunchDetails(),
      );
    } catch (_) {
      return false;
    }
  }
}
