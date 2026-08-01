import 'package:drift/drift.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/providers.dart';
import '../../../data/local/database.dart';
import '../../health/presentation/health_providers.dart';
import '../../nutrition/domain/macro_targets.dart';
import '../../nutrition/presentation/nutrition_providers.dart';
import '../../workouts/data/scheduled_workout_service.dart';
import '../data/dashboard_config_repository.dart';
import '../domain/dashboard_config.dart';
import '../domain/streaks.dart';

final dashboardConfigRepositoryProvider =
    Provider<DashboardConfigRepository>((ref) {
  return DashboardConfigRepository(ref.watch(sharedPreferencesProvider));
});

/// Editable dashboard layout (§18). Loaded from prefs; mutations persist
/// immediately and re-emit so the dashboard rebuilds live.
class DashboardConfigNotifier extends Notifier<DashboardConfig> {
  @override
  DashboardConfig build() {
    return ref.watch(dashboardConfigRepositoryProvider).load();
  }

  void toggle(DashboardWidgetType type, bool visible) {
    state = state.toggle(type, visible);
    ref.read(dashboardConfigRepositoryProvider).save(state);
  }

  void reorder(int oldIndex, int newIndex) {
    state = state.reorder(oldIndex, newIndex);
    ref.read(dashboardConfigRepositoryProvider).save(state);
  }
}

final dashboardConfigProvider =
    NotifierProvider<DashboardConfigNotifier, DashboardConfig>(
        DashboardConfigNotifier.new);

final scheduledWorkoutServiceProvider =
    Provider<ScheduledWorkoutService>((ref) {
  return ScheduledWorkoutService(
      ref.watch(appDatabaseProvider), ref.watch(clockProvider));
});

/// Today's scheduled workout for the smart launcher (§18). Refreshes when the
/// active workout session changes (so a completed schedule updates).
final todaysScheduledWorkoutProvider =
    FutureProvider<TodaysScheduledWorkout?>((ref) {
  return ref.watch(scheduledWorkoutServiceProvider).todaysWorkout();
});

/// Bodyweight history stream for dashboard visualization.
final bodyweightHistoryProvider =
    StreamProvider<List<BodyMeasurementData>>((ref) {
  return ref.watch(measurementsRepositoryProvider).watchMetric('bodyweight');
});

/// Active energy burned today, read from HealthKit / Health Connect. This is
/// the "+ Exercise" term of the remaining-calories formula; 0 when no health
/// integration is connected.
final todayExerciseKcalProvider = Provider.autoDispose<double>((ref) {
  final samples = ref.watch(todayHealthSamplesProvider).asData?.value;
  if (samples == null) return 0;
  var kcal = 0.0;
  for (final s in samples) {
    if (s.kind == 'active_kcal') kcal += s.value;
  }
  return kcal;
});

/// Calories left today: `Goal - Food + Exercise` (§18).
class RemainingCalories {
  final int goal;
  final int food;
  final int exercise;

  const RemainingCalories({
    required this.goal,
    required this.food,
    required this.exercise,
  });

  int get remaining => goal - food + exercise;

  /// Fraction of the (exercise-adjusted) budget consumed, clamped for gauges.
  double get consumedFraction {
    final budget = goal + exercise;
    if (budget <= 0) return 0;
    return (food / budget).clamp(0.0, 1.0);
  }

  bool get isOver => remaining < 0;
}

final remainingCaloriesProvider =
    Provider.autoDispose<RemainingCalories?>((ref) {
  final now = ref.watch(clockProvider).now();
  final today = DateTime(now.year, now.month, now.day);

  final totals = ref.watch(dailyTotalsProvider(today)).asData?.value;
  final MacroTargets? targets =
      ref.watch(effectiveTargetsProvider(today)).asData?.value ??
          ref.watch(baselineTargetsProvider);
  if (targets == null) return null;

  return RemainingCalories(
    goal: targets.kcal,
    food: (totals?.kcal ?? 0).round(),
    exercise: ref.watch(todayExerciseKcalProvider).round(),
  );
});

/// Days of food logging in a row (§18).
final nutritionStreakProvider = Provider.autoDispose<Streak>((ref) {
  final history = ref.watch(nutritionHistoryProvider).asData?.value;
  if (history == null) return Streak.zero;
  final dates = <DateTime>[];
  for (final entry in history.entries) {
    // Days present but empty (0 kcal) don't count as "logged".
    if (entry.value.kcal <= 0) continue;
    final d = DateTime.tryParse(entry.key);
    if (d != null) dates.add(d);
  }
  return StreakCalculator.daily(dates, ref.watch(clockProvider).now());
});

/// Completed workout sessions in the trailing 12 months, for the streak
/// counter. Kept separate from [recentSessionsProvider], which is capped at 25.
final completedSessionDatesProvider =
    StreamProvider.autoDispose<List<DateTime>>((ref) {
  final db = ref.watch(appDatabaseProvider);
  final from = ref.watch(clockProvider).now().subtract(const Duration(days: 366));
  return (db.select(db.workoutSessions)
        ..where((t) =>
            t.endedAt.isNotNull() & t.startedAt.isBiggerOrEqualValue(from)))
      .watch()
      .map((rows) => [for (final r in rows) r.startedAt]);
});

/// Consecutive training weeks (§18). Weeks rather than days, so a planned rest
/// day doesn't wipe the streak.
final workoutStreakProvider = Provider.autoDispose<Streak>((ref) {
  final dates = ref.watch(completedSessionDatesProvider).asData?.value;
  if (dates == null) return Streak.zero;
  return StreakCalculator.weekly(dates, ref.watch(clockProvider).now());
});

/// Selected date in the dashboard workout calendar view (defaults to today).
final calendarSelectedDateProvider = StateProvider<DateTime>((ref) {
  final now = DateTime.now();
  return DateTime(now.year, now.month, now.day);
});

enum CalendarViewMode { day, week }

/// Dashboard workout calendar view mode (Day vs Week).
final calendarViewModeProvider =
    StateProvider<CalendarViewMode>((_) => CalendarViewMode.week);

class CalendarDaySummary {
  final DateTime date;
  final String dateIso;
  final bool isToday;
  final List<ScheduledWorkoutData> scheduledWorkouts;
  final List<WorkoutSessionData> completedSessions;

  CalendarDaySummary({
    required this.date,
    required this.dateIso,
    required this.isToday,
    required this.scheduledWorkouts,
    required this.completedSessions,
  });

  bool get hasScheduled => scheduledWorkouts.isNotEmpty;
  bool get hasCompleted => completedSessions.isNotEmpty;
}

/// Stream of calendar day summaries for the 7 days of the week containing [anchorDate].
final weekCalendarSummaryProvider =
    StreamProvider.family<List<CalendarDaySummary>, DateTime>((ref, anchorDate) {
  final db = ref.watch(appDatabaseProvider);
  final monday = anchorDate.subtract(Duration(days: anchorDate.weekday - 1));
  final startOfWeek = DateTime(monday.year, monday.month, monday.day);
  final endOfWeek = startOfWeek.add(const Duration(days: 7));

  final dateIsos = List.generate(7, (i) {
    final d = startOfWeek.add(Duration(days: i));
    return '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
  });

  final scheduledStream = (db.select(db.scheduledWorkouts)
        ..where((t) => t.dateIso.isIn(dateIsos)))
      .watch();

  final sessionsStream = (db.select(db.workoutSessions)
        ..where((t) => t.startedAt.isBiggerOrEqualValue(startOfWeek) &
            t.startedAt.isSmallerThanValue(endOfWeek)))
      .watch();

  final now = DateTime.now();
  final todayIso =
      '${now.year.toString().padLeft(4, '0')}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';

  return scheduledStream.asyncMap((schedules) async {
    final sessions = await sessionsStream.first;
    return List.generate(7, (i) {
      final date = startOfWeek.add(Duration(days: i));
      final iso = dateIsos[i];
      final daySchedules = schedules.where((s) => s.dateIso == iso).toList();
      final daySessions = sessions
          .where((s) =>
              s.startedAt.year == date.year &&
              s.startedAt.month == date.month &&
              s.startedAt.day == date.day)
          .toList();

      return CalendarDaySummary(
        date: date,
        dateIso: iso,
        isToday: iso == todayIso,
        scheduledWorkouts: daySchedules,
        completedSessions: daySessions,
      );
    });
  });
});
