import 'package:drift/native.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:herculex/app/providers.dart';
import 'package:herculex/data/local/database.dart';
import 'package:herculex/features/notifications/application/notification_settings_provider.dart';
import 'package:herculex/features/notifications/data/notification_sync_service.dart';
import 'package:herculex/features/notifications/domain/notification_settings.dart';
import 'package:herculex/features/supplements/application/supplement_providers.dart';
import 'package:herculex/features/supplements/data/pending_supplement_action_queue.dart';
import 'package:herculex/features/supplements/data/supplement_notification_scheduler.dart';
import 'package:herculex/features/supplements/data/supplement_repository.dart';
import 'package:herculex/features/supplements/domain/supplement.dart';
import 'package:herculex/features/supplements/domain/supplement_notification_payload.dart';
import 'package:herculex/services/platform/workout_notification_service.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:timezone/data/latest_all.dart' as tz;
import 'package:timezone/timezone.dart' as tz;

class _TestFakeNotificationsPlugin extends Fake
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

  group('Supplement notification background action handler', () {
    test(
      'marks supplement taken in prefs and enqueues on Done action',
      () async {
        SharedPreferences.setMockInitialValues({
          'supplements_config_v1': Supplement.listToJson([
            const Supplement(
              id: 'omega3',
              name: 'Omega 3',
              schedule: SupplementSchedule.time,
              timeHHMM: '18:00',
            ),
          ]),
        });
        final prefs = await SharedPreferences.getInstance();

        final response = NotificationResponse(
          notificationResponseType:
              NotificationResponseType.selectedNotificationAction,
          actionId: SupplementNotificationActionIds.done,
          payload: supplementNotificationPayload('omega3'),
        );

        final handled = await handleSupplementBackgroundTap(response, prefs);
        expect(handled, isTrue);

        final taken = SupplementRepository.loadTakenFromPrefs(prefs);
        expect(taken, contains('omega3'));

        final pending = PendingSupplementActionQueue.read(prefs);
        expect(pending, contains('omega3'));
      },
    );

    test('snooze action in background returns true', () async {
      SharedPreferences.setMockInitialValues({
        'supplements_config_v1': Supplement.listToJson([
          const Supplement(
            id: 'creatine',
            name: 'Creatine',
            schedule: SupplementSchedule.time,
            timeHHMM: '18:00',
          ),
        ]),
      });
      final prefs = await SharedPreferences.getInstance();

      final response30 = NotificationResponse(
        notificationResponseType:
            NotificationResponseType.selectedNotificationAction,
        actionId: SupplementNotificationActionIds.snooze30,
        payload: supplementNotificationPayload('creatine'),
      );
      final handled30 = await handleSupplementBackgroundTap(response30, prefs);
      expect(handled30, isTrue);

      final response60 = NotificationResponse(
        notificationResponseType:
            NotificationResponseType.selectedNotificationAction,
        actionId: SupplementNotificationActionIds.snooze60,
        payload: supplementNotificationPayload('creatine'),
      );
      final handled60 = await handleSupplementBackgroundTap(response60, prefs);
      expect(handled60, isTrue);
    });

    test('ignores non-supplement payloads', () async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();

      final response = const NotificationResponse(
        notificationResponseType:
            NotificationResponseType.selectedNotificationAction,
        actionId: 'some_action',
        payload: 'fasting_schedule:1',
      );

      final handled = await handleSupplementBackgroundTap(response, prefs);
      expect(handled, isFalse);
    });
  });

  group('PendingSupplementActionQueue', () {
    test('enqueues, reads, and replaces pending actions', () async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();

      expect(PendingSupplementActionQueue.read(prefs), isEmpty);

      await PendingSupplementActionQueue.enqueue(prefs, 'creatine');
      await PendingSupplementActionQueue.enqueue(prefs, 'zinc');
      // duplicate should be deduplicated
      await PendingSupplementActionQueue.enqueue(prefs, 'creatine');

      expect(PendingSupplementActionQueue.read(prefs), ['creatine', 'zinc']);

      await PendingSupplementActionQueue.replace(prefs, []);
      expect(PendingSupplementActionQueue.read(prefs), isEmpty);
    });
  });

  group('NotificationSyncService reacts to supplement taken state', () {
    test('triggers supplement reschedule when takenToday changes', () async {
      SharedPreferences.setMockInitialValues({
        'supplements_config_v1': Supplement.listToJson([
          const Supplement(
            id: 'vit_d',
            name: 'Vitamin D',
            schedule: SupplementSchedule.time,
            timeHHMM: '18:00',
          ),
        ]),
      });
      final prefs = await SharedPreferences.getInstance();
      final fakePlugin = _TestFakeNotificationsPlugin();
      final db = AppDatabase.forTesting(NativeDatabase.memory());

      final container = ProviderContainer(
        overrides: [
          appDatabaseProvider.overrideWithValue(db),
          sharedPreferencesProvider.overrideWithValue(prefs),
          localNotificationsPluginProvider.overrideWithValue(fakePlugin),
          notificationSettingsProvider.overrideWith(
            (ref) =>
                NotificationSettingsNotifier(
                  ref.watch(notificationSettingsRepositoryProvider),
                )..update(
                  const NotificationSettings(supplementRemindersEnabled: true),
                ),
          ),
        ],
      );

      // Initialize sync service
      container.read(notificationSyncServiceProvider);
      await container.read(notificationSyncServiceProvider).syncAll();

      expect(fakePlugin.scheduledCalls, isNotEmpty);
      fakePlugin.scheduledCalls.clear();

      // Now toggle taken
      await container
          .read(supplementRepositoryProvider)
          .markTaken('vit_d', true);

      // Allow microtasks and riverpod listener to fire
      await Future<void>.delayed(const Duration(milliseconds: 50));

      // Notification should be rescheduled with tomorrow's date!
      expect(fakePlugin.scheduledCalls, isNotEmpty);
      final lastCall = fakePlugin.scheduledCalls.last;
      final scheduledDate = lastCall['scheduledDate'] as tz.TZDateTime;
      final now = tz.TZDateTime.now(tz.local);
      // Because it's taken today, scheduled date must be tomorrow (> now.day)
      expect(scheduledDate.isAfter(now), isTrue);
      final tomorrow = now.add(const Duration(days: 1));
      expect(scheduledDate.day, tomorrow.day);

      container.dispose();
      await db.close();
    });
  });
}
