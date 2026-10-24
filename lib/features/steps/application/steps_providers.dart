// Riverpod application providers for step management, activity scoring, and gym performance correlations.

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:herculex/app/providers.dart';
import 'package:herculex/features/analytics/application/analytics_providers.dart';
import 'package:herculex/features/steps/data/step_repository.dart';
import 'package:herculex/features/steps/domain/step_lifting_correlation.dart';
import 'package:herculex/features/steps/domain/step_record.dart';
import 'package:herculex/features/steps/domain/step_score_engine.dart';
import 'package:herculex/features/steps/domain/step_weightlifting_impact.dart';

/// Provides the active [StepRepository] instance wired with [AppDatabase] and [Clock].
final stepRepositoryProvider = Provider<StepRepository>((ref) {
  final db = ref.watch(appDatabaseProvider);
  final clock = ref.watch(clockProvider);
  return StepRepository(db, clock);
});

/// Watches the current calendar day's step record as a reactive stream.
final todayStepsProvider = StreamProvider<StepRecord?>((ref) {
  final repo = ref.watch(stepRepositoryProvider);
  return repo.watchTodaySteps();
});

/// Family provider loading past [days] of step history.
final stepHistoryProvider = FutureProvider.family<List<StepRecord>, int>((
  ref,
  days,
) async {
  final repo = ref.watch(stepRepositoryProvider);
  return repo.getStepHistory(days);
});

/// Currently selected calendar date in step tracking views.
final selectedStepDateProvider = StateProvider<DateTime>((ref) {
  final clock = ref.watch(clockProvider);
  return clock.now();
});

/// User's daily step target (defaults to 10000).
final stepGoalProvider = StateProvider<int>((ref) => 10000);

/// Provides the step record for the currently selected date.
final selectedStepRecordProvider = FutureProvider<StepRecord?>((ref) async {
  final selectedDate = ref.watch(selectedStepDateProvider);
  final y = selectedDate.year.toString().padLeft(4, '0');
  final m = selectedDate.month.toString().padLeft(2, '0');
  final d = selectedDate.day.toString().padLeft(2, '0');
  final dateIso = '$y-$m-$d';
  final repo = ref.watch(stepRepositoryProvider);
  return repo.getStepsForDate(dateIso);
});

/// Computes the [StepMovementScore] for today's steps.
final todayStepScoreProvider = Provider<StepMovementScore>((ref) {
  final stepAsync = ref.watch(todayStepsProvider);
  final goal = ref.watch(stepGoalProvider);
  final record = stepAsync.valueOrNull;

  final steps = record?.stepCount ?? 0;
  return StepScoreEngine.calculate(steps: steps, goal: goal);
});

/// Computes the weightlifting impact report for today's step volume.
final todayStepWeightliftingImpactProvider = Provider<StepWeightliftingImpact>((
  ref,
) {
  final stepAsync = ref.watch(todayStepsProvider);
  final record = stepAsync.valueOrNull;
  final steps = record?.stepCount ?? 0;

  return StepWeightliftingEngine.calculate(steps: steps);
});

/// Correlates historical step counts with gym session performance (RPE and tonnage).
final stepLiftingCorrelationProvider = FutureProvider<StepLiftingCorrelation>((
  ref,
) async {
  final db = ref.watch(appDatabaseProvider);
  final healthSamples = await db.select(db.healthSamples).get();
  final snapshot = await ref.watch(trainingSnapshotProvider.future);

  return StepLiftingCorrelation.compute(
    healthSamples: healthSamples,
    resolvedSets: snapshot.sets,
  );
});
