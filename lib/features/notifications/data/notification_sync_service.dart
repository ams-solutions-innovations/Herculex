import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:herculex/features/fasting/application/fasting_providers.dart';
import 'package:herculex/features/notifications/application/notification_settings_provider.dart';
import 'package:herculex/features/nutrition/application/meal_slots_provider.dart';
import 'package:herculex/features/supplements/application/supplement_providers.dart';

/// Coordinates and synchronizes all local notifications (meals, supplements,
/// fasting, daily check-in) whenever user data or notification settings change.
class NotificationSyncService with WidgetsBindingObserver {
  final Ref _ref;

  NotificationSyncService(this._ref) {
    _initListeners();
    WidgetsBinding.instance.addObserver(this);
  }

  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      // A taken supplement uses a one-shot reminder for tomorrow because a
      // repeating time notification cannot skip just today's occurrence.
      // Re-arm daily notifications whenever the app returns to the foreground.
      unawaited(_syncSupplements());
    }
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
      if (prev?.weeklyReportEnabled != next.weeklyReportEnabled ||
          prev?.weeklyReportTimeHHMM != next.weeklyReportTimeHHMM) {
        _syncWeeklyReport();
      }
    });

    _ref.listen(mealSlotsProvider, (_, _) => _syncMeals());

    _ref.listen(supplementsProvider, (_, _) => _syncSupplements());

    _ref.listen(takenTodayProvider, (_, _) => _syncSupplements());

    _ref.listen(fastingSchedulesProvider, (_, _) => _syncFastingSchedules());
  }

  Future<void> syncAll() async {
    await Future.wait([
      _syncMeals(),
      _syncSupplements(),
      _syncFastingSchedules(),
      _syncDailyLog(),
      _syncWeeklyReport(),
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
      final repository = _ref.read(supplementRepositoryProvider);
      // Read the persisted date-keyed set directly. StreamProvider can still
      // hold yesterday's value when the app crosses midnight in the background.
      final supplements = repository.loadSupplements();
      final takenToday = repository.loadTakenToday();
      final scheduler = _ref.read(supplementNotificationSchedulerProvider);
      await scheduler.reschedule(
        supplements,
        takenTodayIds: takenToday,
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

  Future<void> _syncWeeklyReport() async {
    try {
      final settings = _ref.read(notificationSettingsProvider);
      final scheduler = _ref.read(weeklyReportNotificationSchedulerProvider);
      await scheduler.reschedule(settings);
    } catch (_) {}
  }
}

final notificationSyncServiceProvider = Provider<NotificationSyncService>((
  ref,
) {
  final service = NotificationSyncService(ref);
  ref.onDispose(service.dispose);
  return service;
});
