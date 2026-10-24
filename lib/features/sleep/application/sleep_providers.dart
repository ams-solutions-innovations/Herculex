// Riverpod application providers for sleep management, recovery scores, and lifting correlations.

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:herculex/app/providers.dart';
import 'package:herculex/features/analytics/application/analytics_providers.dart';
import 'package:herculex/features/sleep/data/sleep_repository.dart';
import 'package:herculex/features/sleep/domain/sleep_lifting_correlation.dart';
import 'package:herculex/features/sleep/domain/sleep_record.dart';
import 'package:herculex/features/sleep/domain/sleep_score_engine.dart';
import 'package:herculex/features/sleep/domain/sleep_weightlifting_impact.dart';

/// Provides the active [SleepRepository] instance wired with [AppDatabase] and [Clock].
final sleepRepositoryProvider = Provider<SleepRepository>((ref) {
  final db = ref.watch(appDatabaseProvider);
  final clock = ref.watch(clockProvider);
  return SleepRepository(db, clock);
});

/// Watches the current calendar day's sleep record as a reactive stream.
final todaySleepProvider = StreamProvider<SleepRecord?>((ref) {
  final repo = ref.watch(sleepRepositoryProvider);
  return repo.watchTodaySleep();
});

/// Family provider loading past [days] of sleep history.
final sleepHistoryProvider = FutureProvider.family<List<SleepRecord>, int>((
  ref,
  days,
) async {
  final repo = ref.watch(sleepRepositoryProvider);
  return repo.getSleepHistory(days);
});

/// Currently selected calendar date in sleep analysis views.
final selectedSleepDateProvider = StateProvider<DateTime>((ref) {
  final clock = ref.watch(clockProvider);
  return clock.now();
});

/// User's personal nightly sleep goal in hours (defaults to 8.0).
final sleepTargetHoursProvider = StateProvider<double>((ref) => 8.0);

/// Provides the sleep record for the currently selected date.
final selectedSleepRecordProvider = FutureProvider<SleepRecord?>((ref) async {
  final selectedDate = ref.watch(selectedSleepDateProvider);
  final y = selectedDate.year.toString().padLeft(4, '0');
  final m = selectedDate.month.toString().padLeft(2, '0');
  final d = selectedDate.day.toString().padLeft(2, '0');
  final dateIso = '$y-$m-$d';
  final repo = ref.watch(sleepRepositoryProvider);
  return repo.getSleepForDate(dateIso);
});

/// Computes the physiological [SleepRecoveryScore] for today's sleep session.
final todaySleepScoreProvider = Provider<SleepRecoveryScore?>((ref) {
  final sleepAsync = ref.watch(todaySleepProvider);
  final target = ref.watch(sleepTargetHoursProvider);
  final record = sleepAsync.valueOrNull;
  if (record == null) {
    return null;
  }
  final adjusted = record.targetHours == target
      ? record
      : record.copyWith(targetHours: target);
  return SleepScoreEngine.calculate(adjusted);
});

/// Computes the athletic and neuromuscular impact of today's sleep on weightlifting.
final todayWeightliftingImpactProvider = Provider<SleepWeightliftingImpact>((
  ref,
) {
  final sleepAsync = ref.watch(todaySleepProvider);
  final target = ref.watch(sleepTargetHoursProvider);
  final record = sleepAsync.valueOrNull;

  if (record == null) {
    // When no sleep is logged yet today, evaluate baseline at target hours
    return SleepWeightliftingEngine.evaluate(sleepHours: target);
  }

  return SleepWeightliftingEngine.evaluate(
    sleepHours: record.totalHours,
    deepSleepHours: record.stages != null
        ? record.stages!.deepMinutes / 60.0
        : null,
    remSleepHours: record.stages != null
        ? record.stages!.remMinutes / 60.0
        : null,
    sleepDebt: record.sleepDebtHours,
    restingHr: record.restingHr,
  );
});

/// Correlates historical sleep hours with gym session performance (RPE and tonnage).
final sleepLiftingCorrelationProvider = FutureProvider<SleepLiftingCorrelation>(
  (ref) async {
    final db = ref.watch(appDatabaseProvider);
    final healthSamples = await db.select(db.healthSamples).get();
    final snapshot = await ref.watch(trainingSnapshotProvider.future);

    return SleepLiftingCorrelation.compute(
      healthSamples: healthSamples,
      resolvedSets: snapshot.sets,
    );
  },
);
