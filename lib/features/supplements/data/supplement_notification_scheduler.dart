import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/timezone.dart' as tz;

import '../domain/supplement.dart';

/// Schedules and cancels daily timed notifications for supplements that have
/// [SupplementSchedule.time] set. Post-workout supplements are triggered
/// imperatively from the workout session end handler.
class SupplementNotificationScheduler {
  static const _channelId = 'supplement_reminders';
  // Notification IDs for timed supplements start at 1000 to avoid collisions.
  static const _baseNotifId = 1000;

  final FlutterLocalNotificationsPlugin _plugin;

  SupplementNotificationScheduler(this._plugin);

  /// Reschedules daily timed notifications for all supplements with
  /// [SupplementSchedule.time]. Cancels any previously scheduled ones first.
  Future<void> reschedule(List<Supplement> supplements) async {
    // Cancel all existing timed supplement notifications.
    await cancelAll(supplements.length + 10);

    int idOffset = 0;
    for (final supplement in supplements) {
      if (supplement.schedule != SupplementSchedule.time) continue;
      final time = supplement.timeHHMM;
      if (time == null) continue;

      final parts = time.split(':');
      if (parts.length != 2) continue;
      final hour = int.tryParse(parts[0]);
      final minute = int.tryParse(parts[1]);
      if (hour == null || minute == null) continue;

      final now = tz.TZDateTime.now(tz.local);
      var scheduled = tz.TZDateTime(
          tz.local, now.year, now.month, now.day, hour, minute);
      // If the time has already passed today, schedule for tomorrow.
      if (scheduled.isBefore(now)) {
        scheduled = scheduled.add(const Duration(days: 1));
      }

      const androidDetails = AndroidNotificationDetails(
        _channelId,
        'Supplement Reminders',
        channelDescription: 'Daily supplement intake reminders',
        importance: Importance.high,
        priority: Priority.high,
      );
      const iOSDetails = DarwinNotificationDetails(
        presentAlert: true,
        presentBadge: false,
        presentSound: true,
      );

      try {
        await _plugin.zonedSchedule(
          _baseNotifId + idOffset,
          '💊 Supplement reminder',
          'Time to take ${supplement.name}',
          scheduled,
          const NotificationDetails(
            android: androidDetails,
            iOS: iOSDetails,
          ),
          androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
          uiLocalNotificationDateInterpretation:
              UILocalNotificationDateInterpretation.absoluteTime,
          matchDateTimeComponents: DateTimeComponents.time, // repeat daily
        );
      } catch (_) {
        // Silently skip if scheduling fails (e.g. missing exact alarm permission).
      }
      idOffset++;
    }
  }

  /// Cancels all timed supplement notifications up to [count] slots.
  Future<void> cancelAll(int count) async {
    for (int i = 0; i < count; i++) {
      try {
        await _plugin.cancel(_baseNotifId + i);
      } catch (_) {}
    }
  }
}
