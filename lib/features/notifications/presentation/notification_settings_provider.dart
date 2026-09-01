import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/providers.dart';
import '../../supplements/data/supplement_notification_scheduler.dart';
import '../data/daily_log_notification_scheduler.dart';
import '../data/meal_notification_scheduler.dart';
import '../data/notification_settings_repository.dart';
import '../domain/notification_settings.dart';

final notificationSettingsRepositoryProvider =
    Provider<NotificationSettingsRepository>((ref) {
      final repo = NotificationSettingsRepository(
        ref.watch(sharedPreferencesProvider),
      );
      ref.onDispose(repo.dispose);
      return repo;
    });

class NotificationSettingsNotifier extends StateNotifier<NotificationSettings> {
  final NotificationSettingsRepository _repo;

  NotificationSettingsNotifier(this._repo) : super(_repo.load());

  Future<void> update(NotificationSettings settings) async {
    state = settings;
    await _repo.save(settings);
  }

  Future<void> setMealRemindersEnabled(bool enabled) async {
    await update(state.copyWith(mealRemindersEnabled: enabled));
  }

  Future<void> setMealSlotEnabled(String slotKey, bool enabled) async {
    final map = {...state.mealEnabled, slotKey: enabled};
    await update(state.copyWith(mealEnabled: map));
  }

  Future<void> setMealTime(String slotKey, String timeHHMM) async {
    final map = {...state.mealTimes, slotKey: timeHHMM};
    await update(state.copyWith(mealTimes: map));
  }

  Future<void> setFastingGoalReachedEnabled(bool enabled) async {
    await update(state.copyWith(fastingGoalReachedEnabled: enabled));
  }

  Future<void> setFastingScheduleRemindersEnabled(bool enabled) async {
    await update(state.copyWith(fastingScheduleRemindersEnabled: enabled));
  }

  Future<void> setSupplementRemindersEnabled(bool enabled) async {
    await update(state.copyWith(supplementRemindersEnabled: enabled));
  }

  Future<void> setPostWorkoutSupplementEnabled(bool enabled) async {
    await update(state.copyWith(postWorkoutSupplementEnabled: enabled));
  }

  Future<void> setActiveWorkoutBannerEnabled(bool enabled) async {
    await update(state.copyWith(activeWorkoutBannerEnabled: enabled));
  }

  Future<void> setRestTimerAlertsEnabled(bool enabled) async {
    await update(state.copyWith(restTimerAlertsEnabled: enabled));
  }

  Future<void> setDailyLogReminderEnabled(bool enabled) async {
    await update(state.copyWith(dailyLogReminderEnabled: enabled));
  }

  Future<void> setDailyLogTime(String timeHHMM) async {
    await update(state.copyWith(dailyLogTimeHHMM: timeHHMM));
  }
}

final notificationSettingsProvider =
    StateNotifierProvider<NotificationSettingsNotifier, NotificationSettings>((
      ref,
    ) {
      return NotificationSettingsNotifier(
        ref.watch(notificationSettingsRepositoryProvider),
      );
    });

final localNotificationsPluginProvider =
    Provider<FlutterLocalNotificationsPlugin>((ref) {
      return FlutterLocalNotificationsPlugin();
    });

final mealNotificationSchedulerProvider = Provider<MealNotificationScheduler>((
  ref,
) {
  return MealNotificationScheduler(ref.watch(localNotificationsPluginProvider));
});

final dailyLogNotificationSchedulerProvider =
    Provider<DailyLogNotificationScheduler>((ref) {
      return DailyLogNotificationScheduler(
        ref.watch(localNotificationsPluginProvider),
      );
    });

final supplementNotificationSchedulerProvider =
    Provider<SupplementNotificationScheduler>((ref) {
      return SupplementNotificationScheduler(
        ref.watch(localNotificationsPluginProvider),
      );
    });
