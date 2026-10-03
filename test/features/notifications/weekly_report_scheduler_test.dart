import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:herculex/core/utils/clock.dart';
import 'package:herculex/features/notifications/data/weekly_report_notification_scheduler.dart';
import 'package:herculex/features/notifications/domain/notification_settings.dart';
import 'package:herculex/features/weekly_report/domain/weekly_report_notification_payload.dart';
import 'package:timezone/data/latest_all.dart' as tz;
import 'package:timezone/timezone.dart' as tz;

import 'notification_schedulers_test.dart' show FakeLocalNotificationsPlugin;

class _FixedClock implements Clock {
  _FixedClock(this._now);
  final DateTime _now;
  @override
  DateTime now() => _now;
}

class _ThrowingCancelPlugin extends FakeLocalNotificationsPlugin {
  @override
  Future<void> cancel(int id, {String? tag}) async {
    throw StateError('boom');
  }
}

WeeklyReportNotificationScheduler _scheduler(
  FakeLocalNotificationsPlugin plugin,
  DateTime now,
) => WeeklyReportNotificationScheduler(plugin, clock: _FixedClock(now));

const _enabled = NotificationSettings(
  weeklyReportEnabled: true,
  weeklyReportTimeHHMM: '18:00',
);

void main() {
  tz.initializeTimeZones();
  tz.setLocalLocation(tz.getLocation('UTC'));

  group('WeeklyReportNotificationScheduler', () {
    test('Wednesday schedules the coming Sunday 18:00 weekly', () async {
      final plugin = FakeLocalNotificationsPlugin();
      // 2026-09-30 is a Wednesday.
      await _scheduler(
        plugin,
        DateTime.utc(2026, 9, 30, 10),
      ).reschedule(_enabled);

      expect(plugin.cancelledIds, contains(5001));
      expect(plugin.scheduledCalls.length, 1);
      final call = plugin.scheduledCalls.single;
      expect(call['id'], 5001);
      expect(call['id'], WeeklyReportNotificationScheduler.notifId);
      final when = call['scheduledDate'] as tz.TZDateTime;
      expect(when.weekday, DateTime.sunday);
      expect(when.year, 2026);
      expect(when.month, 10);
      expect(when.day, 4);
      expect(when.hour, 18);
      expect(when.minute, 0);
      expect(
        call['matchDateTimeComponents'],
        DateTimeComponents.dayOfWeekAndTime,
      );
      expect(call['payload'], 'weekly_report');
      expect(call['payload'], weeklyReportNotificationPayload);
      expect(call['title'], 'Your weekly report is ready');
      expect(call['body'], 'See how your week went.');
    });

    test('Sunday before the time fires the same day', () async {
      final plugin = FakeLocalNotificationsPlugin();
      await _scheduler(
        plugin,
        DateTime.utc(2026, 10, 4, 17),
      ).reschedule(_enabled);

      final when =
          plugin.scheduledCalls.single['scheduledDate'] as tz.TZDateTime;
      expect([when.year, when.month, when.day, when.hour], [2026, 10, 4, 18]);
    });

    test('Sunday after the time fires next Sunday', () async {
      final plugin = FakeLocalNotificationsPlugin();
      await _scheduler(
        plugin,
        DateTime.utc(2026, 10, 4, 18, 1),
      ).reschedule(_enabled);

      final when =
          plugin.scheduledCalls.single['scheduledDate'] as tz.TZDateTime;
      expect([when.year, when.month, when.day, when.hour], [2026, 10, 11, 18]);
      expect(when.weekday, DateTime.sunday);
    });

    test('disabled cancels and schedules nothing', () async {
      final plugin = FakeLocalNotificationsPlugin();
      await _scheduler(
        plugin,
        DateTime.utc(2026, 9, 30, 10),
      ).reschedule(const NotificationSettings());

      expect(plugin.cancelledIds, contains(5001));
      expect(plugin.scheduledCalls, isEmpty);
    });

    test('malformed time schedules nothing but still cancels first', () async {
      for (final bad in ['garbage', '18', '18:xx', '25:00', '18:99', '']) {
        final plugin = FakeLocalNotificationsPlugin();
        await _scheduler(plugin, DateTime.utc(2026, 9, 30, 10)).reschedule(
          NotificationSettings(
            weeklyReportEnabled: true,
            weeklyReportTimeHHMM: bad,
          ),
        );
        expect(plugin.cancelledIds, contains(5001), reason: bad);
        expect(plugin.scheduledCalls, isEmpty, reason: bad);
      }
    });

    test('cancel() cancels 5001 and never throws', () async {
      final plugin = FakeLocalNotificationsPlugin();
      await _scheduler(plugin, DateTime.utc(2026, 9, 30)).cancel();
      expect(plugin.cancelledIds, [5001]);

      final throwing = _ThrowingCancelPlugin();
      await expectLater(
        _scheduler(throwing, DateTime.utc(2026, 9, 30)).cancel(),
        completes,
      );
    });
  });

  group('isWeeklyReportPayload', () {
    test('matches only the exact payload', () {
      expect(isWeeklyReportPayload('weekly_report'), isTrue);
      expect(isWeeklyReportPayload(null), isFalse);
      expect(isWeeklyReportPayload(''), isFalse);
      expect(isWeeklyReportPayload('fasting_schedule:3'), isFalse);
      expect(isWeeklyReportPayload('weekly_report_x'), isFalse);
    });
  });
}
