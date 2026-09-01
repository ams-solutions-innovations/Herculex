import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/timezone.dart' as tz;

import '../../../data/local/database.dart';
import '../domain/fasting_plan.dart';
import '../domain/fasting_schedule_occurrence.dart';
import '../domain/fasting_schedule_payload.dart';
import 'fasting_notification_scheduler.dart';
import 'fasting_repository.dart';

/// Schedules and cancels recurring notifications for [FastingScheduleData]
/// rows, and handles auto-starting fasts when their scheduled window begins.
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
  Future<void> rescheduleOne(
    FastingScheduleData schedule, {
    bool enabled = true,
  }) async {
    await cancelForSchedule(schedule.id);
    if (!enabled || !schedule.enabled) return;

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
  Future<void> rescheduleAll(
    List<FastingScheduleData> schedules, {
    bool enabled = true,
  }) async {
    for (final schedule in schedules) {
      await rescheduleOne(schedule, enabled: enabled);
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
    } catch (_) {
      try {
        await _plugin.zonedSchedule(
          notifId(schedule.id, weekday),
          '⏱️ Time to start fasting',
          schedule.autoStart
              ? 'Tap to start your $planLabel fast now.'
              : '$planLabel fast scheduled now — tap to review and start.',
          scheduled,
          details,
          androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
          uiLocalNotificationDateInterpretation:
              UILocalNotificationDateInterpretation.absoluteTime,
          matchDateTimeComponents: DateTimeComponents.dayOfWeekAndTime,
          payload: fastingSchedulePayload(schedule.id),
        );
      } catch (e) {
        if (kDebugMode) {
          debugPrint('FastingScheduleService: schedule failed ($e)');
        }
      }
    }
  }

  /// Checks all enabled schedules with `autoStart == true`. If the current
  /// time is within a schedule's active fasting window, and no active fast
  /// is currently running and no past fast in history already covers this
  /// scheduled start, starts the session automatically and schedules the
  /// goal reached notification.
  Future<void> checkAndAutoStartSchedules({
    required FastingRepository repository,
    required FastingNotificationScheduler notificationScheduler,
    required bool goalNotificationEnabled,
    DateTime? now,
  }) async {
    final active = await repository.activeSession();
    if (active != null) return;

    final currentTime = now ?? DateTime.now();
    final schedules = await repository.watchSchedules().first;
    final pastSessions = await repository.history(limit: 10);

    for (final schedule in schedules) {
      if (!schedule.enabled || !schedule.autoStart || schedule.daysOfWeek == 0) {
        continue;
      }

      final mostRecent = mostRecentOccurrence(
        daysOfWeek: schedule.daysOfWeek,
        startTimeMinutes: schedule.startTimeMinutes,
        from: currentTime,
      );
      if (mostRecent == null) continue;

      final targetSeconds = resolveScheduleTargetSeconds(
        schedule.planName,
        schedule.customTargetSeconds,
      );
      final scheduledEnd = mostRecent.add(Duration(seconds: targetSeconds));

      // Check if currentTime is within [mostRecent, scheduledEnd)
      final isCurrentlyInWindow = (currentTime.isAfter(mostRecent) ||
              currentTime.isAtSameMomentAs(mostRecent)) &&
          currentTime.isBefore(scheduledEnd);

      if (!isCurrentlyInWindow) continue;

      // Check if a session already exists that covers this start time:
      // i.e., started within 45 minutes of scheduled start, or ended after scheduled start.
      final alreadyCovered = pastSessions.any((s) {
        final startedDiff = s.startedAt.difference(mostRecent).inMinutes.abs();
        if (startedDiff <= 45) return true;
        if (s.startedAt.isAfter(mostRecent) &&
            s.startedAt.isBefore(scheduledEnd)) {
          return true;
        }
        if (s.endedAt != null && s.endedAt!.isAfter(mostRecent)) {
          return true;
        }
        return false;
      });

      if (alreadyCovered) continue;

      // Auto-start the fast with the scheduled start time
      await repository.startSession(
        targetSeconds,
        customStartTime: mostRecent,
      );

      final plan = resolveSchedulePlan(schedule.planName);
      final planLabel = plan == FastingPlan.custom
          ? '${targetSeconds ~/ 3600}h'
          : plan.nameString;

      await notificationScheduler.scheduleFastingGoal(
        scheduledEnd,
        planName: planLabel,
        enabled: goalNotificationEnabled,
      );

      // Successfully started one fast, stop checking further schedules.
      break;
    }
  }
}

