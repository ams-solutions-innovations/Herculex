import 'package:drift/native.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:herculex/app/providers.dart';
import 'package:herculex/core/utils/clock.dart';
import 'package:herculex/data/local/database.dart';
import 'package:herculex/features/notifications/application/notification_settings_provider.dart';
import 'package:herculex/features/notifications/data/notification_sync_service.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:timezone/data/latest_all.dart' as tz;
import 'package:timezone/timezone.dart' as tz;

import 'notification_schedulers_test.dart' show FakeLocalNotificationsPlugin;

class _FixedClock implements Clock {
  _FixedClock(this._now);
  final DateTime _now;
  @override
  DateTime now() => _now;
}

class _ThrowingPlugin extends FakeLocalNotificationsPlugin {
  @override
  Future<void> cancel(int id, {String? tag}) async {
    throw StateError('boom');
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  tz.initializeTimeZones();
  tz.setLocalLocation(tz.getLocation('UTC'));

  late AppDatabase db;
  late ProviderContainer container;

  Future<FakeLocalNotificationsPlugin> setUpContainer({
    Map<String, Object> prefsValues = const {},
    FakeLocalNotificationsPlugin? plugin,
  }) async {
    SharedPreferences.setMockInitialValues(prefsValues);
    final prefs = await SharedPreferences.getInstance();
    final fake = plugin ?? FakeLocalNotificationsPlugin();
    db = AppDatabase.forTesting(NativeDatabase.memory());
    container = ProviderContainer(
      overrides: [
        appDatabaseProvider.overrideWithValue(db),
        sharedPreferencesProvider.overrideWithValue(prefs),
        localNotificationsPluginProvider.overrideWithValue(fake),
        // 2026-09-30 is a Wednesday.
        clockProvider.overrideWithValue(
          _FixedClock(DateTime.utc(2026, 9, 30, 10)),
        ),
      ],
    );
    // Constructing the service registers the settings listeners.
    container.read(notificationSyncServiceProvider);
    return fake;
  }

  tearDown(() async {
    container.dispose();
    await db.close();
  });

  List<Map<String, dynamic>> weeklyCalls(FakeLocalNotificationsPlugin p) =>
      p.scheduledCalls.where((c) => c['id'] == 5001).toList();

  test(
    'turning the toggle on schedules one Sunday 18:00 notification',
    () async {
      final plugin = await setUpContainer();
      final notifier = container.read(notificationSettingsProvider.notifier);

      await notifier.setWeeklyReportEnabled(true);
      await pumpEventQueue();

      final calls = weeklyCalls(plugin);
      expect(calls.length, 1);
      final when = calls.single['scheduledDate'] as tz.TZDateTime;
      expect(when.weekday, DateTime.sunday);
      expect(
        [when.year, when.month, when.day, when.hour, when.minute],
        [2026, 10, 4, 18, 0],
      );
      expect(
        calls.single['matchDateTimeComponents'].toString(),
        contains('dayOfWeekAndTime'),
      );
    },
  );

  test('changing the time reschedules at the new HH:MM', () async {
    final plugin = await setUpContainer();
    final notifier = container.read(notificationSettingsProvider.notifier);

    await notifier.setWeeklyReportEnabled(true);
    await pumpEventQueue();
    await notifier.setWeeklyReportTime('19:30');
    await pumpEventQueue();

    final calls = weeklyCalls(plugin);
    expect(calls.length, 2);
    final when = calls.last['scheduledDate'] as tz.TZDateTime;
    expect([when.hour, when.minute], [19, 30]);
  });

  test(
    'turning the toggle off cancels id 5001 and schedules nothing',
    () async {
      final plugin = await setUpContainer();
      final notifier = container.read(notificationSettingsProvider.notifier);

      await notifier.setWeeklyReportEnabled(true);
      await pumpEventQueue();
      plugin.cancelledIds.clear();
      plugin.scheduledCalls.clear();

      await notifier.setWeeklyReportEnabled(false);
      await pumpEventQueue();

      expect(plugin.cancelledIds, contains(5001));
      expect(weeklyCalls(plugin), isEmpty);
    },
  );

  test('syncAll schedules the weekly notification when already on', () async {
    final plugin = await setUpContainer(
      prefsValues: {
        'app_notification_settings_v1':
            '{"weeklyReportEnabled":true,"weeklyReportTimeHHMM":"18:00"}',
      },
    );
    expect(
      container.read(notificationSettingsProvider).weeklyReportEnabled,
      isTrue,
    );

    await container.read(notificationSyncServiceProvider).syncAll();

    expect(weeklyCalls(plugin).length, 1);
  });

  test('a scheduler exception never propagates', () async {
    await setUpContainer(plugin: _ThrowingPlugin());
    final notifier = container.read(notificationSettingsProvider.notifier);

    await notifier.setWeeklyReportEnabled(true);
    await pumpEventQueue();

    await expectLater(
      container.read(notificationSyncServiceProvider).syncAll(),
      completes,
    );
  });
}
