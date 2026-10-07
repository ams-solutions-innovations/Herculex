import 'package:drift/native.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:herculex/app/providers.dart';
import 'package:herculex/core/utils/clock.dart';
import 'package:herculex/data/local/database.dart';
import 'package:herculex/features/fasting/data/fasting_notification_scheduler.dart';
import 'package:herculex/features/notifications/application/notification_settings_provider.dart';
import 'package:herculex/features/notifications/data/daily_log_notification_scheduler.dart';
import 'package:herculex/features/notifications/data/meal_notification_scheduler.dart';
import 'package:herculex/features/notifications/data/notification_sync_service.dart';
import 'package:herculex/features/notifications/domain/notification_settings.dart';
import 'package:herculex/features/nutrition/domain/meal_slots.dart';
import 'package:herculex/features/supplements/data/supplement_notification_scheduler.dart';
import 'package:herculex/features/supplements/domain/supplement.dart';
import 'package:herculex/features/supplements/domain/supplement_notification_payload.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:timezone/data/latest_all.dart' as tz;
import 'package:timezone/timezone.dart' as tz;

class FakeLocalNotificationsPlugin extends Fake
    implements FlutterLocalNotificationsPlugin {
  final List<int> cancelledIds = [];
  final List<Map<String, dynamic>> scheduledCalls = [];

  @override
  Future<void> cancel(int id, {String? tag}) async {
    cancelledIds.add(id);
  }

  @override
  Future<void> zonedSchedule(
    int id,
    String? title,
    String? body,
    tz.TZDateTime scheduledDate,
    NotificationDetails notificationDetails, {
    required AndroidScheduleMode androidScheduleMode,
    DateTimeComponents? matchDateTimeComponents,
    String? payload,
    required UILocalNotificationDateInterpretation
    uiLocalNotificationDateInterpretation,
  }) async {
    scheduledCalls.add({
      'id': id,
      'title': title,
      'body': body,
      'scheduledDate': scheduledDate,
      'notificationDetails': notificationDetails,
      'matchDateTimeComponents': matchDateTimeComponents,
      'payload': payload,
    });
  }
}

class _TestClock implements Clock {
  final DateTime _now;
  const _TestClock(this._now);
  @override
  DateTime now() => _now;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  tz.initializeTimeZones();
  tz.setLocalLocation(tz.getLocation('UTC'));

  group('MealNotificationScheduler', () {
    test('schedules enabled meal slots daily and cancels old ones', () async {
      final fakePlugin = FakeLocalNotificationsPlugin();
      final scheduler = MealNotificationScheduler(fakePlugin);

      const settings = NotificationSettings(
        mealRemindersEnabled: true,
        mealTimes: {'breakfast': '08:00', 'lunch': '12:30'},
        mealEnabled: {'breakfast': true, 'lunch': false},
      );

      final mealSlots = [
        const MealSlot(key: 'breakfast', label: 'Breakfast'),
        const MealSlot(key: 'lunch', label: 'Lunch'),
      ];

      await scheduler.rescheduleAll(settings: settings, mealSlots: mealSlots);

      // Cancelled previous slots
      expect(fakePlugin.cancelledIds, isNotEmpty);
      // Scheduled only breakfast
      expect(fakePlugin.scheduledCalls.length, 1);
      expect(
        fakePlugin.scheduledCalls.first['title'],
        '🍽️ Breakfast reminder',
      );
      expect(
        fakePlugin.scheduledCalls.first['matchDateTimeComponents'],
        DateTimeComponents.time,
      );
    });

    test(
      'cancels all and schedules nothing when mealRemindersEnabled is false',
      () async {
        final fakePlugin = FakeLocalNotificationsPlugin();
        final scheduler = MealNotificationScheduler(fakePlugin);

        const settings = NotificationSettings(mealRemindersEnabled: false);
        final mealSlots = [
          const MealSlot(key: 'breakfast', label: 'Breakfast'),
        ];

        await scheduler.rescheduleAll(settings: settings, mealSlots: mealSlots);

        expect(fakePlugin.cancelledIds, isNotEmpty);
        expect(fakePlugin.scheduledCalls, isEmpty);
      },
    );
  });

  group('DailyLogNotificationScheduler', () {
    test('schedules daily check-in when enabled', () async {
      final fakePlugin = FakeLocalNotificationsPlugin();
      final scheduler = DailyLogNotificationScheduler(fakePlugin);

      const settings = NotificationSettings(
        dailyLogReminderEnabled: true,
        dailyLogTimeHHMM: '20:30',
      );

      await scheduler.reschedule(settings);

      expect(fakePlugin.scheduledCalls.length, 1);
      expect(
        fakePlugin.scheduledCalls.first['id'],
        DailyLogNotificationScheduler.notifId,
      );
      expect(fakePlugin.scheduledCalls.first['title'], '📊 Daily check-in');
    });

    test('cancels when dailyLogReminderEnabled is false', () async {
      final fakePlugin = FakeLocalNotificationsPlugin();
      final scheduler = DailyLogNotificationScheduler(fakePlugin);

      const settings = NotificationSettings(dailyLogReminderEnabled: false);
      await scheduler.reschedule(settings);

      expect(fakePlugin.scheduledCalls, isEmpty);
      expect(
        fakePlugin.cancelledIds,
        contains(DailyLogNotificationScheduler.notifId),
      );
    });
  });

  group('SupplementNotificationScheduler', () {
    test(
      'reschedules supplements when enabled and skips when disabled',
      () async {
        final fakePlugin = FakeLocalNotificationsPlugin();
        final scheduler = SupplementNotificationScheduler(fakePlugin);

        final supplements = [
          const Supplement(
            id: 'creatine',
            name: 'Creatine',
            schedule: SupplementSchedule.time,
            timeHHMM: '09:00',
          ),
        ];

        await scheduler.reschedule(supplements, enabled: true);
        expect(fakePlugin.scheduledCalls.length, 1);
        expect(
          fakePlugin.scheduledCalls.first['title'],
          '💊 Supplement reminder',
        );

        fakePlugin.scheduledCalls.clear();

        await scheduler.reschedule(supplements, enabled: false);
        expect(fakePlugin.scheduledCalls, isEmpty);
      },
    );

    test(
      'schedules for today if not taken yet and time is in the future',
      () async {
        final fakePlugin = FakeLocalNotificationsPlugin();
        // Clock is 08:00 AM on 2026-10-06 UTC
        final testClock = _TestClock(DateTime.utc(2026, 10, 6, 8, 0));
        final scheduler = SupplementNotificationScheduler(
          fakePlugin,
          clock: testClock,
        );

        final supplements = [
          const Supplement(
            id: 'creatine',
            name: 'Creatine',
            schedule: SupplementSchedule.time,
            timeHHMM: '18:00',
          ),
        ];

        await scheduler.reschedule(
          supplements,
          takenTodayIds: {},
          enabled: true,
        );

        expect(fakePlugin.scheduledCalls.length, 1);
        final call = fakePlugin.scheduledCalls.first;
        final scheduledDate = call['scheduledDate'] as tz.TZDateTime;
        expect(scheduledDate.day, 6);
        expect(scheduledDate.hour, 18);
        expect(scheduledDate.minute, 0);
        expect(call['payload'], 'supplement:creatine');

        final details = call['notificationDetails'] as NotificationDetails;
        expect(details.android?.actions?.length, 3);
        expect(
          details.android?.actions?[0].id,
          SupplementNotificationActionIds.done,
        );
        expect(details.android?.actions?[0].title, 'Done');
        expect(
          details.android?.actions?[1].id,
          SupplementNotificationActionIds.snooze30,
        );
        expect(details.android?.actions?[1].title, '+30 min');
        expect(
          details.android?.actions?[2].id,
          SupplementNotificationActionIds.snooze60,
        );
        expect(details.android?.actions?[2].title, '+1 hour');
      },
    );

    test(
      'schedules for tomorrow if already taken today in the morning',
      () async {
        final fakePlugin = FakeLocalNotificationsPlugin();
        // Clock is 08:00 AM on 2026-10-06 UTC, user checked it off in the morning
        final testClock = _TestClock(DateTime.utc(2026, 10, 6, 8, 0));
        final scheduler = SupplementNotificationScheduler(
          fakePlugin,
          clock: testClock,
        );

        final supplements = [
          const Supplement(
            id: 'creatine',
            name: 'Creatine',
            schedule: SupplementSchedule.time,
            timeHHMM: '18:00',
          ),
        ];

        // Marked as taken today!
        await scheduler.reschedule(
          supplements,
          takenTodayIds: {'creatine'},
          enabled: true,
        );

        expect(fakePlugin.scheduledCalls.length, 1);
        final call = fakePlugin.scheduledCalls.first;
        final scheduledDate = call['scheduledDate'] as tz.TZDateTime;
        // Scheduled for tomorrow (day 7), NOT today (day 6)!
        expect(scheduledDate.day, 7);
        expect(scheduledDate.hour, 18);
        expect(scheduledDate.minute, 0);
      },
    );

    test('schedules one-shot snooze when snooze is called', () async {
      final fakePlugin = FakeLocalNotificationsPlugin();
      final testClock = _TestClock(DateTime.utc(2026, 10, 6, 18, 0));
      final scheduler = SupplementNotificationScheduler(
        fakePlugin,
        clock: testClock,
      );

      const supplement = Supplement(
        id: 'creatine',
        name: 'Creatine',
        schedule: SupplementSchedule.time,
        timeHHMM: '18:00',
      );

      await scheduler.snooze(supplement, duration: const Duration(minutes: 30));

      expect(fakePlugin.scheduledCalls.length, 1);
      final call = fakePlugin.scheduledCalls.first;
      final scheduledDate = call['scheduledDate'] as tz.TZDateTime;
      expect(scheduledDate.day, 6);
      expect(scheduledDate.hour, 18);
      expect(scheduledDate.minute, 30);
      expect(call['matchDateTimeComponents'], isNull); // one-shot!
      expect(call['id'], 1500 + (supplement.id.hashCode.abs() % 400));
      expect(call['payload'], 'supplement:creatine');
    });

    test('reschedule with taken today cancels pending snooze', () async {
      final fakePlugin = FakeLocalNotificationsPlugin();
      final scheduler = SupplementNotificationScheduler(fakePlugin);

      final supplements = [
        const Supplement(
          id: 'creatine',
          name: 'Creatine',
          schedule: SupplementSchedule.time,
          timeHHMM: '18:00',
        ),
      ];

      await scheduler.reschedule(
        supplements,
        takenTodayIds: {'creatine'},
        enabled: true,
      );

      // Snooze ID for slot 0 is 1500 + 0 = 1500
      expect(fakePlugin.cancelledIds, contains(1500));
    });
  });

  group('FastingNotificationScheduler & FastingScheduleService', () {
    test('scheduleFastingGoal respects enabled flag', () async {
      final fakePlugin = FakeLocalNotificationsPlugin();
      final scheduler = FastingNotificationScheduler(fakePlugin);

      final target = DateTime.now().add(const Duration(hours: 16));
      await scheduler.scheduleFastingGoal(target, enabled: false);
      expect(fakePlugin.scheduledCalls, isEmpty);
      expect(
        fakePlugin.cancelledIds,
        contains(FastingNotificationScheduler.notifId),
      );

      await scheduler.scheduleFastingGoal(target, enabled: true);
      expect(fakePlugin.scheduledCalls.length, 1);
      expect(
        fakePlugin.scheduledCalls.first['title'],
        '🎉 Fasting Goal Reached!',
      );
    });
  });

  group('NotificationSyncService', () {
    test('syncAll coordinates schedulers without error', () async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();

      final fakePlugin = FakeLocalNotificationsPlugin();
      final db = AppDatabase.forTesting(NativeDatabase.memory());

      final container = ProviderContainer(
        overrides: [
          appDatabaseProvider.overrideWithValue(db),
          sharedPreferencesProvider.overrideWithValue(prefs),
          localNotificationsPluginProvider.overrideWithValue(fakePlugin),
        ],
      );

      final syncService = container.read(notificationSyncServiceProvider);
      await syncService.syncAll();

      container.dispose();
      await db.close();
    });
  });
}
