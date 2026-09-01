import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:herculex/features/fasting/presentation/fasting_providers.dart';
import 'package:herculex/features/notifications/presentation/notification_settings_provider.dart';
import 'package:herculex/features/nutrition/presentation/meal_slots_provider.dart';
import 'package:herculex/features/supplements/presentation/supplement_providers.dart';

/// Coordinates and synchronizes all local notifications (meals, supplements,
/// fasting, daily check-in) whenever user data or notification settings change.
class NotificationSyncService {
  final Ref _ref;

  NotificationSyncService(this._ref) {
    _initListeners();
  }

  void _initListeners() {
    // ── Meal notifications sync ──────────────────────────────────────────────
    _ref.listen(notificationSettingsProvider, (prev, next) {
      if (prev?.mealRemindersEnabled != next.mealRemindersEnabled ||
          prev?.mealEnabled != next.mealEnabled ||
          prev?.mealTimes != next.mealTimes) {
        _syncMeals();
      }
      if (prev?.supplementRemindersEnabled != next.supplementRemindersEnabled) {
        _syncSupplements();
      }
      if (prev?.fastingScheduleRemindersEnabled !=
          next.fastingScheduleRemindersEnabled) {
        _syncFastingSchedules();
      }
      if (prev?.dailyLogReminderEnabled != next.dailyLogReminderEnabled ||
          prev?.dailyLogTimeHHMM != next.dailyLogTimeHHMM) {
        _syncDailyLog();
      }
    });

    _ref.listen(mealSlotsProvider, (_, _) => _syncMeals());

    _ref.listen(supplementsProvider, (_, _) => _syncSupplements());

    _ref.listen(fastingSchedulesProvider, (_, _) => _syncFastingSchedules());
  }

  Future<void> syncAll() async {
    await Future.wait([
      _syncMeals(),
      _syncSupplements(),
      _syncFastingSchedules(),
      _syncDailyLog(),
    ]);
  }

  Future<void> _syncMeals() async {
    try {
      final settings = _ref.read(notificationSettingsProvider);
      final slots = _ref.read(mealSlotsProvider);
      final scheduler = _ref.read(mealNotificationSchedulerProvider);
      await scheduler.rescheduleAll(settings: settings, mealSlots: slots);
    } catch (_) {}
  }

  Future<void> _syncSupplements() async {
    try {
      final settings = _ref.read(notificationSettingsProvider);
      final supplements =
          _ref.read(supplementsProvider).asData?.value ??
          _ref.read(supplementRepositoryProvider).loadSupplements();
      final scheduler = _ref.read(supplementNotificationSchedulerProvider);
      await scheduler.reschedule(
        supplements,
        enabled: settings.supplementRemindersEnabled,
      );
    } catch (_) {}
  }

  Future<void> _syncFastingSchedules() async {
    try {
      final settings = _ref.read(notificationSettingsProvider);
      final repo = _ref.read(fastingRepositoryProvider);
      final scheduler = _ref.read(fastingScheduleServiceProvider);
      final schedules =
          _ref.read(fastingSchedulesProvider).asData?.value ??
          await repo.watchSchedules().first.timeout(
            const Duration(seconds: 2),
            onTimeout: () => const [],
          );
      await scheduler.rescheduleAll(
        schedules,
        enabled: settings.fastingScheduleRemindersEnabled,
      );
    } catch (_) {}
  }

  Future<void> _syncDailyLog() async {
    try {
      final settings = _ref.read(notificationSettingsProvider);
      final scheduler = _ref.read(dailyLogNotificationSchedulerProvider);
      await scheduler.reschedule(settings);
    } catch (_) {}
  }
}

final notificationSyncServiceProvider = Provider<NotificationSyncService>((
  ref,
) {
  return NotificationSyncService(ref);
});
