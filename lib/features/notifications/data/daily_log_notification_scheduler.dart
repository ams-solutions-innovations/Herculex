import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/timezone.dart' as tz;

import '../domain/notification_settings.dart';

/// Schedules and cancels daily evening reminders to log food and review habits.
class DailyLogNotificationScheduler {
  static const channelId = 'daily_log_reminders';
  static const notifId = 4001;

  final FlutterLocalNotificationsPlugin _plugin;

  DailyLogNotificationScheduler(this._plugin);

  Future<void> reschedule(NotificationSettings settings) async {
    await cancel();
    if (!settings.dailyLogReminderEnabled) return;

    final parts = settings.dailyLogTimeHHMM.split(':');
    if (parts.length != 2) return;
    final hour = int.tryParse(parts[0]);
    final minute = int.tryParse(parts[1]);
    if (hour == null || minute == null) return;

    final now = tz.TZDateTime.now(tz.local);
    var scheduled = tz.TZDateTime(
      tz.local,
      now.year,
      now.month,
      now.day,
      hour,
      minute,
    );
    if (scheduled.isBefore(now)) {
      scheduled = scheduled.add(const Duration(days: 1));
    }

    const androidDetails = AndroidNotificationDetails(
      channelId,
      'Daily Log Reminders',
      channelDescription: 'Daily evening reminder to review and log habits',
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
        '📊 Daily check-in',
        "Don't forget to log today's meals and check your targets in Herculex!",
        scheduled,
        const NotificationDetails(android: androidDetails, iOS: iOSDetails),
        androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
        uiLocalNotificationDateInterpretation:
            UILocalNotificationDateInterpretation.absoluteTime,
        matchDateTimeComponents: DateTimeComponents.time,
      );
    } catch (_) {
      try {
        await _plugin.zonedSchedule(
          notifId,
          '📊 Daily check-in',
          "Don't forget to log today's meals and check your targets in Herculex!",
          scheduled,
          const NotificationDetails(android: androidDetails, iOS: iOSDetails),
          androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
          uiLocalNotificationDateInterpretation:
              UILocalNotificationDateInterpretation.absoluteTime,
          matchDateTimeComponents: DateTimeComponents.time,
        );
      } catch (e) {
        if (kDebugMode) {
          debugPrint('DailyLogNotificationScheduler: schedule failed ($e)');
        }
      }
    }
  }

  Future<void> cancel() async {
    try {
      await _plugin.cancel(notifId);
    } catch (_) {}
  }
}
