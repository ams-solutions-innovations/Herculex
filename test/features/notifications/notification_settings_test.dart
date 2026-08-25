import 'package:flutter_test/flutter_test.dart';
import 'package:herculex/features/notifications/data/notification_settings_repository.dart';
import 'package:herculex/features/notifications/domain/notification_settings.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('NotificationSettings', () {
    test('default constructor provides expected sensible defaults', () {
      const settings = NotificationSettings();
      expect(settings.mealRemindersEnabled, isTrue);
      expect(settings.fastingGoalReachedEnabled, isTrue);
      expect(settings.fastingScheduleRemindersEnabled, isTrue);
      expect(settings.supplementRemindersEnabled, isTrue);
      expect(settings.postWorkoutSupplementEnabled, isTrue);
      expect(settings.activeWorkoutBannerEnabled, isTrue);
      expect(settings.restTimerAlertsEnabled, isTrue);
      expect(settings.dailyLogReminderEnabled, isFalse);
      expect(settings.dailyLogTimeHHMM, '21:00');
      expect(settings.mealTimeFor('breakfast'), '08:00');
      expect(settings.mealTimeFor('lunch'), '13:00');
      expect(settings.mealTimeFor('dinner'), '19:00');
      expect(settings.mealTimeFor('snack'), '16:00');
      expect(settings.isMealEnabled('breakfast'), isTrue);
    });

    test('isMealEnabled returns false when mealRemindersEnabled is false', () {
      const settings = NotificationSettings(mealRemindersEnabled: false);
      expect(settings.isMealEnabled('breakfast'), isFalse);
      expect(settings.isMealEnabled('lunch'), isFalse);
    });

    test('serializes to JSON and deserializes correctly', () {
      const original = NotificationSettings(
        mealRemindersEnabled: false,
        mealTimes: {'breakfast': '07:30', 'lunch': '12:00'},
        mealEnabled: {'breakfast': true, 'lunch': false},
        fastingGoalReachedEnabled: false,
        fastingScheduleRemindersEnabled: true,
        supplementRemindersEnabled: false,
        postWorkoutSupplementEnabled: false,
        activeWorkoutBannerEnabled: false,
        restTimerAlertsEnabled: false,
        dailyLogReminderEnabled: true,
        dailyLogTimeHHMM: '20:15',
      );

      final json = original.toJson();
      final restored = NotificationSettings.fromJson(json);

      expect(restored.mealRemindersEnabled, isFalse);
      expect(restored.mealTimes['breakfast'], '07:30');
      expect(restored.mealTimes['lunch'], '12:00');
      expect(restored.mealEnabled['lunch'], isFalse);
      expect(restored.fastingGoalReachedEnabled, isFalse);
      expect(restored.supplementRemindersEnabled, isFalse);
      expect(restored.postWorkoutSupplementEnabled, isFalse);
      expect(restored.activeWorkoutBannerEnabled, isFalse);
      expect(restored.restTimerAlertsEnabled, isFalse);
      expect(restored.dailyLogReminderEnabled, isTrue);
      expect(restored.dailyLogTimeHHMM, '20:15');
    });

    test('fromRawJson handles null or invalid JSON gracefully', () {
      final empty = NotificationSettings.fromRawJson(null);
      expect(empty.mealRemindersEnabled, isTrue);

      final invalid = NotificationSettings.fromRawJson('{invalid_json');
      expect(invalid.mealRemindersEnabled, isTrue);
    });

    test('copyWith updates specific properties correctly', () {
      const initial = NotificationSettings();
      final updated = initial.copyWith(
        mealRemindersEnabled: false,
        dailyLogReminderEnabled: true,
        dailyLogTimeHHMM: '22:00',
      );

      expect(updated.mealRemindersEnabled, isFalse);
      expect(updated.dailyLogReminderEnabled, isTrue);
      expect(updated.dailyLogTimeHHMM, '22:00');
      expect(updated.fastingGoalReachedEnabled, isTrue);
    });
  });

  group('NotificationSettingsRepository', () {
    test('loads default settings when prefs are empty and persists changes', () async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final repo = NotificationSettingsRepository(prefs);

      final initial = repo.load();
      expect(initial.mealRemindersEnabled, isTrue);

      final modified = initial.copyWith(
        mealRemindersEnabled: false,
        restTimerAlertsEnabled: false,
      );
      await repo.save(modified);

      final reloaded = repo.load();
      expect(reloaded.mealRemindersEnabled, isFalse);
      expect(reloaded.restTimerAlertsEnabled, isFalse);

      repo.dispose();
    });
  });
}
