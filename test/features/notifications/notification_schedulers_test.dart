import 'package:drift/native.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:herculex/app/providers.dart';
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
      'matchDateTimeComponents': matchDateTimeComponents,
      'payload': payload,
    });
  }
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
