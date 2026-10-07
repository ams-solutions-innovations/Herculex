import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:herculex/app/providers.dart';
import 'package:herculex/data/local/database.dart';
import 'package:herculex/features/fasting/data/fasting_notification_scheduler.dart';
import 'package:herculex/features/fasting/data/fasting_repository.dart';
import 'package:herculex/features/fasting/data/fasting_schedule_service.dart';
import 'package:herculex/features/fasting/domain/fasting_plan.dart';
import 'package:herculex/features/fasting/domain/fasting_schedule_occurrence.dart';
import 'package:herculex/features/notifications/application/notification_settings_provider.dart';
import 'package:herculex/services/platform/widget_sync_service.dart';

final fastingNotificationSchedulerProvider =
    Provider<FastingNotificationScheduler>((ref) {
      return FastingNotificationScheduler(
        ref.watch(localNotificationsPluginProvider),
      );
    });

final fastingScheduleServiceProvider = Provider<FastingScheduleService>((ref) {
  return FastingScheduleService(ref.watch(localNotificationsPluginProvider));
});

final fastingRepositoryProvider = Provider<FastingRepository>((ref) {
  final db = ref.watch(appDatabaseProvider);
  final clock = ref.watch(clockProvider);
  return FastingRepository(db, clock);
});

final fastingSchedulesProvider = StreamProvider<List<FastingScheduleData>>((
  ref,
) {
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

class NextScheduledFastInfo {
  final FastingScheduleData schedule;
  final DateTime nextOccurrence;
  final FastingPlan plan;
  final String planLabel;
  final int targetSeconds;
  final Duration timeUntil;

  const NextScheduledFastInfo({
    required this.schedule,
    required this.nextOccurrence,
    required this.plan,
    required this.planLabel,
    required this.targetSeconds,
    required this.timeUntil,
  });
}

final hasActiveFastingScheduleProvider = Provider<bool>((ref) {
  final schedules = ref.watch(fastingSchedulesProvider).valueOrNull ?? [];
  return schedules.any((s) => s.enabled && s.daysOfWeek != 0);
});

final nextScheduledFastProvider = Provider<NextScheduledFastInfo?>((ref) {
  final schedules = ref.watch(fastingSchedulesProvider).valueOrNull ?? [];
  final clock = ref.watch(clockProvider);
  final now = clock.now();

  NextScheduledFastInfo? earliest;
  for (final s in schedules) {
    if (!s.enabled || s.daysOfWeek == 0) continue;
    final next = nextOccurrence(
      daysOfWeek: s.daysOfWeek,
      startTimeMinutes: s.startTimeMinutes,
      from: now,
    );
    if (next == null) continue;

    final plan = resolveSchedulePlan(s.planName);
    final targetSeconds = resolveScheduleTargetSeconds(
      s.planName,
      s.customTargetSeconds,
    );
    final planLabel = plan == FastingPlan.custom
        ? '${targetSeconds ~/ 3600}h Custom'
        : plan.nameString;

    final candidate = NextScheduledFastInfo(
      schedule: s,
      nextOccurrence: next,
      plan: plan,
      planLabel: planLabel,
      targetSeconds: targetSeconds,
      timeUntil: next.difference(now),
    );

    if (earliest == null ||
        candidate.nextOccurrence.isBefore(earliest.nextOccurrence)) {
      earliest = candidate;
    }
  }

  return earliest;
});

final fastingStagesProvider = StreamProvider<List<FastingStageData>>((ref) {
  final repo = ref.watch(fastingRepositoryProvider);
  return repo.watchFastingStages();
});

final currentFastingStageProvider = Provider<FastingStageData?>((ref) {
  final ticker = ref.watch(fastingTimerTickerProvider).valueOrNull;
  final stages = ref.watch(fastingStagesProvider).valueOrNull;
  if (ticker == null || stages == null || stages.isEmpty) return null;

  final elapsedHours = ticker.inHours;
  final targetHour = elapsedHours.clamp(1, 72);

  FastingStageData? match;
  for (final s in stages) {
    if (s.hour <= targetHour) {
      if (match == null || s.hour > match.hour) {
        match = s;
      }
    }
  }
  return match ?? stages.first;
});

/// Pushes the running fast to the Fasting home-screen widget. Only the start
/// and target are sent — the widget keeps its own clock — so this fires on
/// session or schedule changes, not every tick.
final widgetFastingSyncControllerProvider = Provider<void>((ref) {
  final widgetSync = WidgetSyncService();

  Future<void> sync() async {
    final active = ref.read(activeFastingSessionProvider).valueOrNull;
    final schedules =
        ref.read(fastingSchedulesProvider).valueOrNull ?? const [];

    if (active != null) {
      final quick = isQuickFastTarget(active.targetSeconds);
      await widgetSync.syncFasting(
        startedAt: active.startedAt,
        targetSeconds: quick ? null : active.targetSeconds,
        planLabel: _planLabel(active.targetSeconds),
      );
      return;
    }

    // Idle: badge the plan the user has scheduled next, if any.
    final scheduled = schedules
        .where((s) => s.enabled && s.deletedAt == null)
        .map((s) {
          final plan = FastingPlan.values.asNameMap()[s.planName];
          if (plan == null) return null;
          return plan == FastingPlan.custom
              ? _planLabel(s.customTargetSeconds ?? 0)
              : plan.nameString;
        })
        .nonNulls
        .firstOrNull;
    await widgetSync.syncFasting(
      startedAt: null,
      targetSeconds: null,
      planLabel: scheduled,
    );
  }

  ref.listen(activeFastingSessionProvider, (_, next) {
    if (next.hasValue) sync();
  }, fireImmediately: true);
  ref.listen(fastingSchedulesProvider, (_, next) {
    if (next.hasValue) sync();
  });
});

/// The widget badge for a fast of [targetSeconds]: the preset's own name
/// ("16:8", "24h") or whole hours for anything else.
String? _planLabel(int targetSeconds) {
  if (isQuickFastTarget(targetSeconds)) return 'Quick';
  if (targetSeconds <= 0) return null;
  for (final plan in FastingPlan.values) {
    if (plan == FastingPlan.custom || plan == FastingPlan.quickFast) continue;
    if (plan.targetSeconds == targetSeconds) return plan.nameString;
  }
  return '${(targetSeconds / 3600).round()}h';
}
