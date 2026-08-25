import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/timezone.dart' as tz;

import '../../nutrition/domain/meal_slots.dart';
import '../domain/notification_settings.dart';

/// Schedules and cancels daily repeating notifications for meal reminders.
/// Each meal slot (Breakfast, Lunch, Dinner, Snacks, custom) can have its own
/// time and enabled state.
class MealNotificationScheduler {
  static const channelId = 'meal_reminders';
  // Notification IDs for meal reminders start at 3000 to avoid collisions.
  static const _baseNotifId = 3000;

  final FlutterLocalNotificationsPlugin _plugin;

  MealNotificationScheduler(this._plugin);

  /// Reschedules all meal reminders according to current [settings] and [mealSlots].
  Future<void> rescheduleAll({
    required NotificationSettings settings,
    required List<MealSlot> mealSlots,
  }) async {
    // Cancel up to max possible slots first to clear removed or disabled ones.
    await cancelAll(mealSlots.length + 20);

    if (!settings.mealRemindersEnabled) return;

    int slotIndex = 0;
    for (final slot in mealSlots) {
      final isEnabled = settings.isMealEnabled(slot.key);
      if (!isEnabled) {
        slotIndex++;
        continue;
      }

      final timeHHMM = settings.mealTimeFor(slot.key);
      final parts = timeHHMM.split(':');
      if (parts.length != 2) {
        slotIndex++;
        continue;
      }

      final hour = int.tryParse(parts[0]);
      final minute = int.tryParse(parts[1]);
      if (hour == null || minute == null) {
        slotIndex++;
        continue;
      }

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
        'Meal Reminders',
        channelDescription: 'Daily meal time reminders',
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
          _baseNotifId + slotIndex,
          '🍽️ ${slot.label} reminder',
          'Time for ${slot.label.toLowerCase()}! Tap to log your food in Herculex.',
          scheduled,
          const NotificationDetails(
            android: androidDetails,
            iOS: iOSDetails,
          ),
          androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
          uiLocalNotificationDateInterpretation:
              UILocalNotificationDateInterpretation.absoluteTime,
          matchDateTimeComponents: DateTimeComponents.time,
        );
      } catch (e) {
        if (kDebugMode) {
          debugPrint('MealNotificationScheduler: schedule failed ($e)');
        }
      }

      slotIndex++;
    }
  }

  /// Cancels all scheduled meal notifications.
  Future<void> cancelAll(int count) async {
    for (int i = 0; i < count; i++) {
      try {
        await _plugin.cancel(_baseNotifId + i);
      } catch (_) {}
    }
  }
}
