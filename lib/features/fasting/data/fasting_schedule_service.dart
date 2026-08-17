import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/timezone.dart' as tz;

import '../../../data/local/database.dart';
import '../domain/fasting_plan.dart';
import '../domain/fasting_schedule_occurrence.dart';
import '../domain/fasting_schedule_payload.dart';

/// Schedules and cancels the recurring "notify to start" reminders for
/// [FastingScheduleData] rows. One `zonedSchedule` call per enabled weekday
/// per schedule, using `matchDateTimeComponents:
/// DateTimeComponents.dayOfWeekAndTime` so the platform itself re-derives
/// the next matching wall-clock instant week over week — including across
/// DST — with no manual reschedule-tomorrow bookkeeping. That correctness
/// depends on `tz.local` actually being the device's zone (wired in
/// `main.dart`); without it every fire time would be off by the device's
/// UTC offset.
///
/// True silent background auto-start does not exist here: neither platform
/// runs Dart code when a scheduled notification is merely *delivered* while
/// the app isn't running, only when the user taps it. [FastingScheduleData.
/// autoStart] means "tapping this notification starts the fast immediately"
/// rather than "opens the Fasting page for review" — see the dispatch
/// wiring in `services/workout_notification_service.dart` and `app/app.dart`.
class FastingScheduleService {
  static const channelId = 'fasting_schedule';

  /// 2100+ per the UI-rework roadmap's notification id plan — the existing
  /// fasting-goal-reached notification owns 2001. `scheduleId * 10 +
  /// (weekday - 1)` gives each of a schedule's up to 7 weekday firings a
  /// stable, collision-free id, cancellable individually or as a block.
  static const _baseNotifId = 2100;

  final FlutterLocalNotificationsPlugin _plugin;

  FastingScheduleService(this._plugin);

  static int notifId(int scheduleId, int weekday) =>
      _baseNotifId + scheduleId * 10 + (weekday - 1);

  Future<void> cancelForSchedule(int scheduleId) async {
    for (var weekday = 1; weekday <= 7; weekday++) {
      try {
        await _plugin.cancel(notifId(scheduleId, weekday));
      } catch (e) {
        debugPrint('FastingScheduleService: cancel failed ($e)');
      }
    }
  }

  /// Cancel-and-reschedule for one row — the only safe way to apply an edit,
  /// since a changed day/time must drop notification ids that no longer
  /// apply before any new ones are added.
  Future<void> rescheduleOne(FastingScheduleData schedule) async {
    await cancelForSchedule(schedule.id);
    if (!schedule.enabled) return;

    final plan = resolveSchedulePlan(schedule.planName);
    final targetSeconds = resolveScheduleTargetSeconds(
      schedule.planName,
      schedule.customTargetSeconds,
    );
    final planLabel = plan == FastingPlan.custom
        ? '${targetSeconds ~/ 3600}h'
        : plan.nameString;

    for (var weekday = 1; weekday <= 7; weekday++) {
      if (!hasWeekday(schedule.daysOfWeek, weekday)) continue;
      await _scheduleOne(schedule, weekday, planLabel);
    }
  }

  /// Rehydrates every row — call on app launch (an Android reboot clears
  /// exact alarms, and edits made offline before the app closed still need
  /// to land) and whenever the schedule list changes wholesale.
  Future<void> rescheduleAll(List<FastingScheduleData> schedules) async {
    for (final schedule in schedules) {
      await rescheduleOne(schedule);
    }
  }

  Future<void> _scheduleOne(
    FastingScheduleData schedule,
    int weekday,
    String planLabel,
  ) async {
    final now = tz.TZDateTime.now(tz.local);
    final next = nextOccurrence(
      daysOfWeek: weekdayBit(weekday),
      startTimeMinutes: schedule.startTimeMinutes,
      from: now,
    )!;
    final scheduled = tz.TZDateTime(
      tz.local,
      next.year,
      next.month,
      next.day,
      next.hour,
      next.minute,
    );

    const androidDetails = AndroidNotificationDetails(
      channelId,
      'Fasting Schedule',
      channelDescription: 'Reminders to start a scheduled fast',
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
      await _plugin.zonedSchedule(
        notifId(schedule.id, weekday),
        '⏱️ Time to start fasting',
        schedule.autoStart
            ? 'Tap to start your $planLabel fast now.'
            : '$planLabel fast scheduled now — tap to review and start.',
        scheduled,
        details,
        androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
        uiLocalNotificationDateInterpretation:
            UILocalNotificationDateInterpretation.absoluteTime,
        matchDateTimeComponents: DateTimeComponents.dayOfWeekAndTime,
        payload: fastingSchedulePayload(schedule.id),
      );
    } catch (e) {
      debugPrint('FastingScheduleService: schedule failed ($e)');
    }
  }
}
