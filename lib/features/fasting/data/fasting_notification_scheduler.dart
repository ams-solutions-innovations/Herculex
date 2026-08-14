import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/timezone.dart' as tz;

class FastingNotificationScheduler {
  static const String channelId = 'fasting_notifications';
  static const int notifId = 2001;

  final FlutterLocalNotificationsPlugin _plugin;

  FastingNotificationScheduler(this._plugin);

  /// Schedules a notification when the fasting window completes.
  Future<void> scheduleFastingGoal(DateTime targetTime, {String planName = 'Fasting'}) async {
    final now = DateTime.now();
    if (targetTime.isBefore(now)) {
      return;
    }

    const androidDetails = AndroidNotificationDetails(
      channelId,
      'Fasting Reminders',
      channelDescription: 'Notifications when your fasting goal is reached',
      importance: Importance.high,
      priority: Priority.high,
    );

    const iOSDetails = DarwinNotificationDetails(
      presentAlert: true,
      presentBadge: false,
      presentSound: true,
    );

    const details = NotificationDetails(
      android: androidDetails,
      iOS: iOSDetails,
    );

    try {
      final scheduledTz = tz.TZDateTime.from(targetTime, tz.local);
      await _plugin.zonedSchedule(
        notifId,
        '🎉 Fasting Goal Reached!',
        'You completed your $planName fast. You can break your fast whenever you are ready.',
        scheduledTz,
        details,
        androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
        uiLocalNotificationDateInterpretation:
            UILocalNotificationDateInterpretation.absoluteTime,
      );
    } catch (e) {
      debugPrint('FastingNotificationScheduler: schedule failed ($e)');
    }
  }

  /// Cancels any scheduled fasting target notification.
  Future<void> cancelFastingGoal() async {
    try {
      await _plugin.cancel(notifId);
    } catch (e) {
      debugPrint('FastingNotificationScheduler: cancel failed ($e)');
    }
  }
}
