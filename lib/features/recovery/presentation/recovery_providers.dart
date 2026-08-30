import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/providers.dart';
import '../../analytics/domain/muscle_recovery_v3.dart';
import '../../analytics/domain/muscle_volume_trend.dart';
import '../../analytics/presentation/analytics_providers.dart';
import '../../health/presentation/health_providers.dart';
import '../data/joint_pain_repository.dart';
import '../domain/joint_model.dart';
import '../domain/joint_stress_advisor.dart';
import '../domain/muscle_deload_advisor.dart';
import '../domain/training_suggestion.dart';

final jointPainRepositoryProvider = Provider<JointPainRepository>((ref) {
  return JointPainRepository(ref.watch(appDatabaseProvider));
});

final jointPainStatusesProvider =
    StreamProvider<Map<String, JointPainStatus>>((ref) {
  return ref.watch(jointPainRepositoryProvider).watchCurrentStatuses();
});

/// Hours until each muscle decays to [MuscleRecoveryV3.recoveredScoreThreshold].
final recoveryEtaProvider = FutureProvider<Map<String, double?>>((ref) async {
  final snapshot = await ref.watch(trainingSnapshotProvider.future);
  final workouts = await ref.watch(externalWorkoutsProvider.future);
  final historyDays = await ref.watch(daysOfStepHistoryProvider.future);
  return MuscleRecoveryV3.recoveryEtaHours(
    snapshot: snapshot,
    externalWorkouts: workouts,
    asOf: ref.watch(clockProvider).now(),
    daysOfHealthHistory: historyDays,
  );
});

/// Trailing 8-week per-muscle volume trend — "the last month or two" view
/// the deload and joint-stress advisors are built on.
final muscleVolumeTrendsProvider =
    FutureProvider<Map<String, MuscleVolumeTrend>>((ref) async {
  final snapshot = await ref.watch(trainingSnapshotProvider.future);
  return MuscleVolumeTrends.compute(
    snapshot: snapshot,
    asOf: ref.watch(clockProvider).now(),
  );
});

final muscleDeloadSignalsProvider =
    FutureProvider<List<MuscleDeloadSignal>>((ref) async {
  final snapshot = await ref.watch(trainingSnapshotProvider.future);
  final workouts = await ref.watch(externalWorkoutsProvider.future);
  final cns = await ref.watch(cnsTrendsProvider.future);
  return MuscleDeloadAdvisor.compute(
    snapshot: snapshot,
    externalWorkouts: workouts,
    asOf: ref.watch(clockProvider).now(),
    cnsTrends: cns,
  );
});

final jointStressResultsProvider =
    FutureProvider<List<JointStressResult>>((ref) async {
  final snapshot = await ref.watch(trainingSnapshotProvider.future);
  final wideWorkouts = await ref.watch(wideExternalWorkoutsProvider.future);
  final statuses = await ref.watch(jointPainStatusesProvider.future);
  final asOf = ref.watch(clockProvider).now();

  return [
    for (final joint in JointModel.joints)
      JointStressAdvisor.evaluate(
        joint: joint,
        flaggedSince: statuses[joint]?.flaggedSince,
        snapshot: snapshot,
        wideExternalWorkouts: wideWorkouts,
        asOf: asOf,
      ),
  ];
});

final nextWorkoutTrainingSuggestionProvider =
    FutureProvider<TrainingSuggestion>((ref) async {
  final recovery = await ref.watch(recoveryV3Provider.future);
  final deload = await ref.watch(muscleDeloadSignalsProvider.future);
  final joints = await ref.watch(jointStressResultsProvider.future);
  final volumeTrends = await ref.watch(muscleVolumeTrendsProvider.future);
  return TrainingSuggestionEngine.suggest(
    recovery: recovery,
    deloadSignals: deload,
    jointStress: joints,
    volumeTrends: volumeTrends,
  );
});
