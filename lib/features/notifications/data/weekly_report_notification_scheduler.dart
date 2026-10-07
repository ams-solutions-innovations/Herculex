import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:herculex/core/utils/clock.dart';
import 'package:herculex/features/notifications/domain/notification_settings.dart';
import 'package:herculex/features/weekly_report/domain/weekly_report_notification_payload.dart';
import 'package:timezone/timezone.dart' as tz;

/// Schedules the opt-in Sunday weekly report notification (D-07, D-08).
///
/// This class only schedules. The notification callback never runs Dart work;
/// the report is generated when the user opens it.
class WeeklyReportNotificationScheduler {
  static const channelId = 'weekly_report';
  static const notifId = 5001;

  static const _title = 'Your weekly report is ready';
  static const _body = 'See how your week went.';

  final FlutterLocalNotificationsPlugin _plugin;
  final Clock _clock;

  WeeklyReportNotificationScheduler(
    this._plugin, {
    Clock clock = const SystemClock(),
  }) : _clock = clock;

  Future<void> reschedule(NotificationSettings settings) async {
    await cancel();
    if (!settings.weeklyReportEnabled) return;

    final parts = settings.weeklyReportTimeHHMM.split(':');
    if (parts.length != 2) return;
    final hour = int.tryParse(parts[0]);
    final minute = int.tryParse(parts[1]);
    if (hour == null || minute == null) return;
    if (hour < 0 || hour > 23 || minute < 0 || minute > 59) return;

    final now = tz.TZDateTime.from(_clock.now(), tz.local);
    final scheduled = nextSunday(now, hour, minute);

    const androidDetails = AndroidNotificationDetails(
      channelId,
      'Weekly Report',
      channelDescription: 'Weekly summary reminder on Sunday',
      importance: Importance.defaultImportance,
      priority: Priority.defaultPriority,
    );
    const iOSDetails = DarwinNotificationDetails(
      presentAlert: true,
      presentBadge: false,
      presentSound: true,
    );

    try {
      await _plugin.zonedSchedule(
        notifId,
        _title,
        _body,
        scheduled,
        const NotificationDetails(android: androidDetails, iOS: iOSDetails),
        androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
        uiLocalNotificationDateInterpretation:
            UILocalNotificationDateInterpretation.absoluteTime,
        matchDateTimeComponents: DateTimeComponents.dayOfWeekAndTime,
        payload: weeklyReportNotificationPayload,
      );
    } catch (_) {
      try {
        await _plugin.zonedSchedule(
          notifId,
          _title,
          _body,
          scheduled,
          const NotificationDetails(android: androidDetails, iOS: iOSDetails),
          androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
          uiLocalNotificationDateInterpretation:
              UILocalNotificationDateInterpretation.absoluteTime,
          matchDateTimeComponents: DateTimeComponents.dayOfWeekAndTime,
          payload: weeklyReportNotificationPayload,
        );
      } catch (e) {
        if (kDebugMode) {
          debugPrint('WeeklyReportNotificationScheduler: schedule failed ($e)');
        }
      }
    }
  }

  /// First Sunday at [hour]:[minute] local that is not before [after].
  ///
  /// [after] comes from the injected Clock, never the wall clock.
  ///
  /// The plugin derives the repeating weekday from the scheduled date, so the
  /// first fire must itself be a Sunday. Built with the calendar constructor
  /// (not `add(Duration)`) so DST shifts cannot move the wall-clock time.
  @visibleForTesting
  static tz.TZDateTime nextSunday(tz.TZDateTime after, int hour, int minute) {
    for (var n = 0; n <= 7; n++) {
      final candidate = tz.TZDateTime(
        tz.local,
        after.year,
        after.month,
        after.day + n,
        hour,
        minute,
      );
      if (candidate.weekday == DateTime.sunday && !candidate.isBefore(after)) {
        return candidate;
      }
    }
    // Unreachable: within 8 consecutive days there is always a qualifying Sunday.
    throw StateError('No upcoming Sunday found');
  }

  Future<void> cancel() async {
    try {
      await _plugin.cancel(notifId);
    } catch (_) {}
  }
}
