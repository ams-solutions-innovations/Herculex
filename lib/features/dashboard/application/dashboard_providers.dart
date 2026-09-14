import 'package:drift/drift.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:herculex/app/providers.dart';
import 'package:herculex/data/local/database.dart';
import 'package:herculex/features/dashboard/data/dashboard_config_repository.dart';
import 'package:herculex/features/dashboard/domain/dashboard_config.dart';
import 'package:herculex/features/dashboard/domain/streaks.dart';
import 'package:herculex/features/health/application/health_providers.dart';
import 'package:herculex/features/nutrition/application/nutrition_providers.dart';
import 'package:herculex/features/nutrition/domain/macro_targets.dart';
import 'package:herculex/features/programs/application/programs_providers.dart';
import 'package:herculex/features/supplements/application/supplement_providers.dart';
import 'package:herculex/features/workouts/application/workouts_providers.dart';
import 'package:herculex/features/workouts/data/scheduled_workout_service.dart';

final dashboardConfigRepositoryProvider = Provider<DashboardConfigRepository>((
  ref,
) {
  return DashboardConfigRepository(ref.watch(sharedPreferencesProvider));
});

/// Editable dashboard layout (§18). Loaded from prefs; mutations persist
/// immediately and re-emit so the dashboard rebuilds live.
class DashboardConfigNotifier extends Notifier<DashboardConfig> {
  @override
  DashboardConfig build() {
    return ref.watch(dashboardConfigRepositoryProvider).load();
  }

  void toggleSlot(int index, bool visible) {
    state = state.toggleSlot(index, visible);
    ref.read(dashboardConfigRepositoryProvider).save(state);
  }

  void resize(int index, DashboardWidgetSize size) {
    state = state.resize(index, size);
    ref.read(dashboardConfigRepositoryProvider).save(state);
  }

  void reorder(int oldIndex, int newIndex) {
    state = state.reorder(oldIndex, newIndex);
    ref.read(dashboardConfigRepositoryProvider).save(state);
  }

  void stackSlots(int sourceIndex, int targetIndex) {
    state = state.stackSlots(sourceIndex, targetIndex);
    ref.read(dashboardConfigRepositoryProvider).save(state);
  }

  void stackWidgets(DashboardWidgetType target, DashboardWidgetType added) {
    state = state.stackWidgets(target, added);
    ref.read(dashboardConfigRepositoryProvider).save(state);
  }

  void unstackWidget(DashboardWidgetType type) {
    state = state.unstackWidget(type);
    ref.read(dashboardConfigRepositoryProvider).save(state);
  }
}

final dashboardConfigProvider =
    NotifierProvider<DashboardConfigNotifier, DashboardConfig>(
      DashboardConfigNotifier.new,
    );

/// User-selected card & pill shape style (squircle, pill, compact).
class DashboardCardShapeNotifier extends Notifier<DashboardCardShape> {
  @override
  DashboardCardShape build() {
    return ref.watch(dashboardConfigRepositoryProvider).loadShape();
  }

  void setShape(DashboardCardShape shape) {
    state = shape;
    ref.read(dashboardConfigRepositoryProvider).saveShape(shape);
  }
}

final dashboardCardShapeProvider =
    NotifierProvider<DashboardCardShapeNotifier, DashboardCardShape>(
      DashboardCardShapeNotifier.new,
    );

/// Whether the dashboard is in in-place edit mode (long-press to enter,
/// "Done" to exit) showing per-tile remove/resize controls.
final dashboardEditModeProvider = StateProvider<bool>((ref) => false);

final scheduledWorkoutServiceProvider = Provider<ScheduledWorkoutService>((
  ref,
) {
  return ScheduledWorkoutService(
    ref.watch(appDatabaseProvider),
    ref.watch(clockProvider),
    ref.watch(programsRepositoryProvider),
    ref.watch(templatesRepositoryProvider),
  );
});

/// Today's scheduled workout for the smart launcher (§18). Refreshes when the
/// active workout session changes (so a completed schedule updates).
final todaysScheduledWorkoutProvider = FutureProvider<TodaysScheduledWorkout?>((
  ref,
) {
  return ref.watch(scheduledWorkoutServiceProvider).todaysWorkout();
});

/// Bodyweight history stream for dashboard visualization.
final bodyweightHistoryProvider = StreamProvider<List<BodyMeasurementData>>((
  ref,
) {
  return ref.watch(measurementsRepositoryProvider).watchMetric('bodyweight');
});

/// Active energy burned today, read from HealthKit / Health Connect. This is
/// the "+ Exercise" term of the remaining-calories formula. `null` means the
/// app does not currently have a trusted health read for exercise calories.
final todayExerciseKcalProvider = Provider.autoDispose<double?>((ref) {
  final lastRead = ref.watch(lastDailyHealthReadProvider);
  final activeRead = lastRead?.activeKcal;
  if (activeRead != null && !activeRead.isAvailable) return null;

  final samples = ref.watch(todayHealthSamplesProvider).asData?.value;
  if (samples == null) return null;
  var kcal = 0.0;
  for (final s in samples) {
    if (s.kind == 'active_kcal') kcal += s.value;
  }
  return kcal == 0 ? null : kcal;
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

final remainingCaloriesProvider = Provider.autoDispose<RemainingCalories?>((
  ref,
) {
  final now = ref.watch(clockProvider).now();
  final today = DateTime(now.year, now.month, now.day);

  final totals = ref.watch(dailyTotalsProvider(today)).asData?.value;
  final MacroTargets? targets =
      ref.watch(effectiveTargetsProvider(today)).asData?.value ??
      ref.watch(baselineTargetsProvider);
  if (targets == null) return null;

  final exerciseKcal = ref.watch(todayExerciseKcalProvider)?.round() ?? 0;
  final profile = ref.watch(profileProvider).asData?.value;
  final countBurned = profile?.countBurnedCalories ?? false;
  final baseGoal = countBurned ? (targets.kcal - exerciseKcal) : targets.kcal;

  return RemainingCalories(
    goal: baseGoal,
    food: (totals?.kcal ?? 0).round(),
    exercise: countBurned ? exerciseKcal : 0,
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
      final from = ref
          .watch(clockProvider)
          .now()
          .subtract(const Duration(days: 366));
      return (db.select(db.workoutSessions)..where(
            (t) =>
                t.endedAt.isNotNull() & t.startedAt.isBiggerOrEqualValue(from),
          ))
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
final calendarViewModeProvider = StateProvider<CalendarViewMode>(
  (_) => CalendarViewMode.week,
);

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
final _weekScheduledWorkoutsProvider =
    StreamProvider.family<List<ScheduledWorkoutData>, DateTime>((
      ref,
      anchorDate,
    ) {
      final db = ref.watch(appDatabaseProvider);
      final monday = anchorDate.subtract(
        Duration(days: anchorDate.weekday - 1),
      );
      final startOfWeek = DateTime(monday.year, monday.month, monday.day);

      final dateIsos = List.generate(7, (i) {
        final d = startOfWeek.add(Duration(days: i));
        return '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
      });

      return (db.select(
        db.scheduledWorkouts,
      )..where((t) => t.dateIso.isIn(dateIsos))).watch();
    });

final _weekCompletedSessionsProvider =
    StreamProvider.family<List<WorkoutSessionData>, DateTime>((
      ref,
      anchorDate,
    ) {
      final db = ref.watch(appDatabaseProvider);
      final monday = anchorDate.subtract(
        Duration(days: anchorDate.weekday - 1),
      );
      final startOfWeek = DateTime(monday.year, monday.month, monday.day);
      final endOfWeek = startOfWeek.add(const Duration(days: 7));

      return (db.select(db.workoutSessions)..where(
            (t) =>
                t.startedAt.isBiggerOrEqualValue(startOfWeek) &
                t.startedAt.isSmallerThanValue(endOfWeek),
          ))
          .watch();
    });

/// Stream of calendar day summaries for the 7 days of the week containing [anchorDate].
final weekCalendarSummaryProvider =
    Provider.family<AsyncValue<List<CalendarDaySummary>>, DateTime>((
      ref,
      anchorDate,
    ) {
      final schedulesAsync = ref.watch(
        _weekScheduledWorkoutsProvider(anchorDate),
      );
      final sessionsAsync = ref.watch(
        _weekCompletedSessionsProvider(anchorDate),
      );

      if (schedulesAsync.isLoading || sessionsAsync.isLoading) {
        return const AsyncLoading();
      }
      if (schedulesAsync.hasError) {
        return AsyncError(schedulesAsync.error!, schedulesAsync.stackTrace!);
      }
      if (sessionsAsync.hasError) {
        return AsyncError(sessionsAsync.error!, sessionsAsync.stackTrace!);
      }

      final schedules = schedulesAsync.requireValue;
      final sessions = sessionsAsync.requireValue;

      final monday = anchorDate.subtract(
        Duration(days: anchorDate.weekday - 1),
      );
      final startOfWeek = DateTime(monday.year, monday.month, monday.day);
      final now = DateTime.now();
      final todayIso =
          '${now.year.toString().padLeft(4, '0')}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';

      final dateIsos = List.generate(7, (i) {
        final d = startOfWeek.add(Duration(days: i));
        return '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
      });

      final result = List.generate(7, (i) {
        final date = startOfWeek.add(Duration(days: i));
        final iso = dateIsos[i];
        final daySchedules = schedules.where((s) => s.dateIso == iso).toList();
        final daySessions = sessions
            .where(
              (s) =>
                  s.startedAt.year == date.year &&
                  s.startedAt.month == date.month &&
                  s.startedAt.day == date.day,
            )
            .toList();

        return CalendarDaySummary(
          date: date,
          dateIso: iso,
          isToday: iso == todayIso,
          scheduledWorkouts: daySchedules,
          completedSessions: daySessions,
        );
      });

      return AsyncData(result);
    });

/// The program week number for [schedule]'s program day, or null when the
/// day isn't part of a program (e.g. an inline one-off schedule).
final _scheduleWeekNumberProvider = FutureProvider.family<int?, int>((
  ref,
  programWeekId,
) async {
  final db = ref.watch(appDatabaseProvider);
  final week = await (db.select(
    db.programWeeks,
  )..where((t) => t.id.equals(programWeekId))).getSingleOrNull();
  return week?.weekIndex;
});

/// Pushes today's planned workout + up to 4 supplements to the Training
/// home-screen widget whenever [todaysScheduledWorkoutProvider] or
/// [supplementDayStateProvider] emits new data.
///
/// Only the fields the Training card actually renders are reused here
/// ([TodaysScheduledWorkout.title], [TodaysScheduledWorkout.exerciseCount],
/// and the program week number) — no scheduling/domain logic is
/// re-derived. An exercise-name list ("Bench · OHP · Dips" in the mockup)
/// and duration/volume estimates are not exposed by any existing provider,
/// so the widget shows an exercise count instead of fabricating that data.
final widgetTrainingSyncControllerProvider = Provider<void>((ref) {
  final widgetSync = ref.watch(widgetSyncServiceProvider);

  Future<void> doSync() async {
    final workout = ref.read(todaysScheduledWorkoutProvider).valueOrNull;
    final supplementState = ref
        .read(supplementDayStateProvider)
        .asData
        ?.value;
    final supplements =
        supplementState?.supplements.take(4).toList() ?? const [];
    final takenIds = supplementState?.takenIds ?? const <String>{};

    int? week;
    if (workout != null) {
      week = await ref.read(
        _scheduleWeekNumberProvider(workout.programDay.programWeekId).future,
      );
    }

    await widgetSync.syncTraining(
      title: workout?.title,
      week: week,
      exerciseCount: workout?.exerciseCount ?? 0,
      supplementNames: [for (final s in supplements) s.name],
      supplementDoses: [for (final s in supplements) s.doseLabel ?? ''],
      supplementTimes: [for (final s in supplements) s.timeHHMM ?? ''],
      supplementTaken: [
        for (final s in supplements) takenIds.contains(s.id),
      ],
      supplementTakenCount: supplementState?.takenCount ?? 0,
      supplementTotalCount: supplementState?.totalCount ?? 0,
    );
  }

  ref.listen<AsyncValue<TodaysScheduledWorkout?>>(
    todaysScheduledWorkoutProvider,
    (_, next) {
      if (next.hasValue) doSync();
    },
    fireImmediately: true,
  );

  ref.listen<AsyncValue<SupplementDayState>>(supplementDayStateProvider, (
    _,
    next,
  ) {
    if (next.hasValue) doSync();
  });
});
