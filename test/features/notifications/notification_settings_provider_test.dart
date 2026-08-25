import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:herculex/app/providers.dart';
import 'package:herculex/features/notifications/presentation/notification_settings_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('NotificationSettingsNotifier', () {
    late ProviderContainer container;
    late SharedPreferences prefs;

    setUp(() async {
      SharedPreferences.setMockInitialValues({});
      prefs = await SharedPreferences.getInstance();
      container = ProviderContainer(
        overrides: [
          sharedPreferencesProvider.overrideWithValue(prefs),
        ],
      );
    });

    tearDown(() {
      container.dispose();
    });

    test('toggles mealRemindersEnabled and updates state', () async {
      final notifier = container.read(notificationSettingsProvider.notifier);
      expect(container.read(notificationSettingsProvider).mealRemindersEnabled, isTrue);

      await notifier.setMealRemindersEnabled(false);
      expect(container.read(notificationSettingsProvider).mealRemindersEnabled, isFalse);

      await notifier.setMealRemindersEnabled(true);
      expect(container.read(notificationSettingsProvider).mealRemindersEnabled, isTrue);
    });

    test('updates specific meal time and slot enabled status', () async {
      final notifier = container.read(notificationSettingsProvider.notifier);
      await notifier.setMealTime('breakfast', '07:15');
      expect(container.read(notificationSettingsProvider).mealTimeFor('breakfast'), '07:15');

      await notifier.setMealSlotEnabled('breakfast', false);
      expect(container.read(notificationSettingsProvider).isMealEnabled('breakfast'), isFalse);
    });

    test('toggles fasting and supplement notification options', () async {
      final notifier = container.read(notificationSettingsProvider.notifier);
      
      await notifier.setFastingGoalReachedEnabled(false);
      expect(container.read(notificationSettingsProvider).fastingGoalReachedEnabled, isFalse);

      await notifier.setFastingScheduleRemindersEnabled(false);
      expect(container.read(notificationSettingsProvider).fastingScheduleRemindersEnabled, isFalse);

      await notifier.setSupplementRemindersEnabled(false);
      expect(container.read(notificationSettingsProvider).supplementRemindersEnabled, isFalse);

      await notifier.setPostWorkoutSupplementEnabled(false);
      expect(container.read(notificationSettingsProvider).postWorkoutSupplementEnabled, isFalse);
    });

    test('toggles workout and daily habit options', () async {
      final notifier = container.read(notificationSettingsProvider.notifier);

      await notifier.setActiveWorkoutBannerEnabled(false);
      expect(container.read(notificationSettingsProvider).activeWorkoutBannerEnabled, isFalse);

      await notifier.setRestTimerAlertsEnabled(false);
      expect(container.read(notificationSettingsProvider).restTimerAlertsEnabled, isFalse);

      await notifier.setDailyLogReminderEnabled(true);
      expect(container.read(notificationSettingsProvider).dailyLogReminderEnabled, isTrue);

      await notifier.setDailyLogTime('20:45');
      expect(container.read(notificationSettingsProvider).dailyLogTimeHHMM, '20:45');
    });
  });
}
