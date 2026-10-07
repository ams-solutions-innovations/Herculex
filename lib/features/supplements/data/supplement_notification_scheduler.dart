import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:herculex/core/utils/clock.dart';
import 'package:herculex/features/supplements/domain/supplement.dart';
import 'package:herculex/features/supplements/domain/supplement_notification_payload.dart';
import 'package:timezone/timezone.dart' as tz;

/// Schedules and cancels daily timed notifications and snoozed reminders
/// for supplements that have [SupplementSchedule.time] set. Post-workout
/// supplements are triggered imperatively from the workout session end handler.
class SupplementNotificationScheduler {
  static const _channelId = 'supplement_reminders';
  // Notification IDs for timed supplements start at 1000 to avoid collisions.
  static const _baseNotifId = 1000;
  // Notification IDs for snoozed supplement reminders start at 1500.
  static const _snoozeBaseNotifId = 1500;
  static const categoryIdentifier = 'supplement_reminders_category';

  final FlutterLocalNotificationsPlugin _plugin;
  final Clock _clock;

  SupplementNotificationScheduler(
    this._plugin, {
    Clock clock = const SystemClock(),
  }) : _clock = clock;

  static const _androidDetails = AndroidNotificationDetails(
    _channelId,
    'Supplement Reminders',
    channelDescription: 'Daily supplement intake reminders',
    importance: Importance.high,
    priority: Priority.high,
    actions: <AndroidNotificationAction>[
      AndroidNotificationAction(
        SupplementNotificationActionIds.done,
        'Done',
        showsUserInterface: false,
        cancelNotification: true,
      ),
      AndroidNotificationAction(
        SupplementNotificationActionIds.snooze30,
        '+30 min',
        showsUserInterface: false,
        cancelNotification: true,
      ),
      AndroidNotificationAction(
        SupplementNotificationActionIds.snooze60,
        '+1 hour',
        showsUserInterface: false,
        cancelNotification: true,
      ),
    ],
  );

  static const _iOSDetails = DarwinNotificationDetails(
    presentAlert: true,
    presentBadge: false,
    presentSound: true,
    categoryIdentifier: categoryIdentifier,
  );

  /// Reschedules daily timed notifications for all supplements with
  /// [SupplementSchedule.time]. Cancels any previously scheduled ones first.
  ///
  /// If a supplement has already been marked taken today ([takenTodayIds]),
  /// today's reminder is skipped and rescheduled for tomorrow at that time.
  Future<void> reschedule(
    List<Supplement> supplements, {
    Set<String> takenTodayIds = const {},
    bool enabled = true,
  }) async {
    // Cancel all existing timed supplement notifications.
    await cancelAll(supplements.length + 10);
    if (!enabled) {
      await cancelAllSnoozes(supplements.length + 10);
      return;
    }

    final now = tz.TZDateTime.from(_clock.now(), tz.local);

    int idOffset = 0;
    for (final supplement in supplements) {
      final isTakenToday = takenTodayIds.contains(supplement.id);

      // If already taken today, cancel any pending snooze for this slot.
      if (isTakenToday) {
        await cancelSnooze(idOffset);
      }

      if (supplement.schedule != SupplementSchedule.time) {
        idOffset++;
        continue;
      }
      final time = supplement.timeHHMM;
      if (time == null) {
        idOffset++;
        continue;
      }

      final parts = time.split(':');
      if (parts.length != 2) {
        idOffset++;
        continue;
      }
      final hour = int.tryParse(parts[0]);
      final minute = int.tryParse(parts[1]);
      if (hour == null || minute == null) {
        idOffset++;
        continue;
      }

      var scheduled = tz.TZDateTime(
        tz.local,
        now.year,
        now.month,
        now.day,
        hour,
        minute,
      );

      // If the supplement was already taken today OR its scheduled time has
      // already passed today, schedule for tomorrow.
      if (isTakenToday || scheduled.isBefore(now)) {
        scheduled = scheduled.add(const Duration(days: 1));
      }

      final notifId = _baseNotifId + idOffset;
      final payload = supplementNotificationPayload(supplement.id);

      await _scheduleNotification(
        id: notifId,
        title: '💊 Supplement reminder',
        body: 'Time to take ${supplement.name}',
        scheduled: scheduled,
        payload: payload,
        matchDateTimeComponents: DateTimeComponents.time, // repeat daily
      );

      idOffset++;
    }
  }

  /// Schedules a one-shot postponed / snoozed reminder for [supplement].
  Future<void> snooze(
    Supplement supplement, {
    required Duration duration,
    int? index,
  }) async {
    final now = tz.TZDateTime.from(_clock.now(), tz.local);
    final scheduled = now.add(duration);
    final offset = index ?? (supplement.id.hashCode.abs() % 400);
    final notifId = _snoozeBaseNotifId + offset;
    final payload = supplementNotificationPayload(supplement.id);

    try {
      await _plugin.cancel(notifId);
    } catch (_) {}

    await _scheduleNotification(
      id: notifId,
      title: '💊 Supplement reminder',
      body: 'Time to take ${supplement.name}',
      scheduled: scheduled,
      payload: payload,
      matchDateTimeComponents: null, // one-shot, does not repeat daily
    );
  }

  /// Snoozes a supplement reminder by [supplementId] using the current list of
  /// [supplements] for metadata.
  Future<void> snoozeById(
    String supplementId,
    List<Supplement> supplements, {
    required Duration duration,
  }) async {
    final index = supplements.indexWhere((s) => s.id == supplementId);
    final supplement = index != -1
        ? supplements[index]
        : Supplement(id: supplementId, name: 'Supplement');
    await snooze(
      supplement,
      duration: duration,
      index: index != -1 ? index : null,
    );
  }

  /// Cancels all timed supplement notifications up to [count] slots.
  Future<void> cancelAll(int count) async {
    for (int i = 0; i < count; i++) {
      try {
        await _plugin.cancel(_baseNotifId + i);
      } catch (_) {}
    }
  }

  /// Cancels a snoozed supplement reminder slot.
  Future<void> cancelSnooze(int index) async {
    try {
      await _plugin.cancel(_snoozeBaseNotifId + index);
    } catch (_) {}
  }

  /// Cancels all snoozed supplement notifications up to [count] slots.
  Future<void> cancelAllSnoozes(int count) async {
    for (int i = 0; i < count; i++) {
      await cancelSnooze(i);
    }
  }

  Future<void> _scheduleNotification({
    required int id,
    required String title,
    required String body,
    required tz.TZDateTime scheduled,
    required String payload,
    DateTimeComponents? matchDateTimeComponents,
  }) async {
    const details = NotificationDetails(
      android: _androidDetails,
      iOS: _iOSDetails,
    );

    try {
      await _plugin.zonedSchedule(
        id,
        title,
        body,
        scheduled,
        details,
        payload: payload,
        androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
        uiLocalNotificationDateInterpretation:
            UILocalNotificationDateInterpretation.absoluteTime,
        matchDateTimeComponents: matchDateTimeComponents,
      );
    } catch (_) {
      try {
        await _plugin.zonedSchedule(
          id,
          title,
          body,
          scheduled,
          details,
          payload: payload,
          androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
          uiLocalNotificationDateInterpretation:
              UILocalNotificationDateInterpretation.absoluteTime,
          matchDateTimeComponents: matchDateTimeComponents,
        );
      } catch (_) {
        // Silently skip if scheduling completely fails
      }
    }
  }
}
