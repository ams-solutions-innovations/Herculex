import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/providers.dart';
import '../data/fasting_notification_scheduler.dart';
import '../data/fasting_repository.dart';
import '../data/fasting_schedule_service.dart';
import '../../../data/local/database.dart';

final fastingNotificationSchedulerProvider =
    Provider<FastingNotificationScheduler>((ref) {
  return FastingNotificationScheduler(FlutterLocalNotificationsPlugin());
});

final fastingScheduleServiceProvider = Provider<FastingScheduleService>((ref) {
  return FastingScheduleService(FlutterLocalNotificationsPlugin());
});

final fastingRepositoryProvider = Provider<FastingRepository>((ref) {
  final db = ref.watch(appDatabaseProvider);
  final clock = ref.watch(clockProvider);
  return FastingRepository(db, clock);
});

final fastingSchedulesProvider = StreamProvider<List<FastingScheduleData>>((ref) {
  final repo = ref.watch(fastingRepositoryProvider);
  return repo.watchSchedules();
});

final activeFastingSessionProvider = StreamProvider<FastingSessionData?>((ref) {
  final repo = ref.watch(fastingRepositoryProvider);
  return repo.watchActiveSession();
});

final fastingHistoryProvider = StreamProvider<List<FastingSessionData>>((ref) {
  final repo = ref.watch(fastingRepositoryProvider);
  return repo.watchHistory();
});

final fastingStreakProvider = FutureProvider<int>((ref) {
  final repo = ref.watch(fastingRepositoryProvider);
  // Watch active session and history so streak updates when sessions change
  ref.watch(activeFastingSessionProvider);
  ref.watch(fastingHistoryProvider);
  return repo.currentStreak();
});

final fastingAverageEatingWindowProvider = FutureProvider<double>((ref) {
  final repo = ref.watch(fastingRepositoryProvider);
  // Watch active session and history so stats update when sessions change
  ref.watch(activeFastingSessionProvider);
  ref.watch(fastingHistoryProvider);
  return repo.averageEatingWindow(30);
});

/// A timer ticker stream that emits the elapsed duration since the active fast started,
/// updated every second. Emits null if no active fast is running.
final fastingTimerTickerProvider = StreamProvider<Duration?>((ref) {
  final activeAsync = ref.watch(activeFastingSessionProvider);
  final active = activeAsync.asData?.value;
  if (active == null) {
    return Stream.value(null);
  }

  final clock = ref.watch(clockProvider);

  Stream<Duration?> ticker() async* {
    yield clock.now().difference(active.startedAt);
    yield* Stream.periodic(const Duration(seconds: 1), (_) {
      return clock.now().difference(active.startedAt);
    });
  }

  return ticker();
});
