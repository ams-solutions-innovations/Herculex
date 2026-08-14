import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/providers.dart';
import '../../../services/widget_sync_service.dart';
import '../data/analytics_repository.dart';
import '../domain/cns_trends.dart';
import '../domain/muscle_recovery_v3.dart';
import '../domain/balance_analyzer.dart';
import '../domain/biometric_correlations.dart';
import '../domain/training_snapshot.dart';
import '../domain/variant_performance.dart';
import '../domain/weekly_muscle_volume.dart';
import '../../health/presentation/health_providers.dart';
import '../../workouts/presentation/workouts_providers.dart';



final analyticsRepositoryProvider = Provider<AnalyticsRepository>((ref) {
  return AnalyticsRepository(ref.watch(appDatabaseProvider));
});

final weeklyTonnageProvider = FutureProvider<List<WeeklyTonnage>>((ref) {
  return ref.watch(analyticsRepositoryProvider).weeklyTonnage();
});

final topOneRmsProvider = FutureProvider<List<OneRmProjection>>((ref) {
  return ref.watch(analyticsRepositoryProvider).topOneRms();
});

/// This week's total tonnage plus the per-muscle-group breakdown behind the
/// "Total Volume This Week" dashboard drop-down.
final weeklyMuscleVolumeProvider =
    FutureProvider<WeeklyMuscleVolume>((ref) async {
  final snapshot = await ref.watch(trainingSnapshotProvider.future);
  return WeeklyMuscleVolume.compute(
    snapshot: snapshot,
    asOf: ref.watch(clockProvider).now(),
  );
});

final pushPullBalanceProvider = FutureProvider<BalanceResult>((ref) async {
  final snapshot = await ref.watch(trainingSnapshotProvider.future);
  return BalanceAnalyzer.summary(sets: snapshot.sets);
});

final sleepVsRpeProvider = FutureProvider<BiometricCorrelationResult>((ref) async {
  final db = ref.watch(appDatabaseProvider);
  final healthSamples = await db.select(db.healthSamples).get();
  final snapshot = await ref.watch(trainingSnapshotProvider.future);

  return BiometricCorrelations.sleepVsRpe(
    healthSamples: healthSamples,
    resolvedSets: snapshot.sets,
  );
});

// ── V2 Phase 3: effective-load engines ──────────────────────────────────────

/// Shared resolved-set snapshot feeding recovery v3, CNS trends, and PR
/// breakdowns, so all engines read identical effective-load numbers (§23).
final trainingSnapshotProvider = FutureProvider<TrainingSnapshot>((ref) async {
  // Watch recent sessions so the snapshot invalidates and reloads when 
  // workouts are completed or modified (fixes cache invalidation issue).
  ref.watch(recentSessionsProvider);
  return TrainingSnapshot.load(ref.watch(appDatabaseProvider));
});

/// Granular 19-muscle-group recovery (§2).
final recoveryV3Provider =
    FutureProvider<List<MuscleGroupRecovery>>((ref) async {
  final snapshot = await ref.watch(trainingSnapshotProvider.future);
  final externalWorkouts = await ref.watch(externalWorkoutsProvider.future);
  
  return MuscleRecoveryV3.compute(
    snapshot: snapshot, 
    externalWorkouts: externalWorkouts,
    asOf: DateTime.now()
  );
});

final recoveryWarningsProvider =
    FutureProvider<List<RecoveryWarning>>((ref) async {
  final results = await ref.watch(recoveryV3Provider.future);
  return MuscleRecoveryV3.warnings(results);
});

/// CNS dashboard data: daily series, current gauge, deload trigger (§3).
final cnsTrendsProvider = FutureProvider<CnsTrendsResult>((ref) async {
  final snapshot = await ref.watch(trainingSnapshotProvider.future);
  return CnsTrends.compute(snapshot: snapshot, asOf: DateTime.now());
});

/// (exerciseId) → PRs per equipment variant (§1).
final equipmentPerformanceProvider =
    FutureProvider.family<List<PerformanceRecord>, int>((ref, exerciseId) async {
  final snapshot = await ref.watch(trainingSnapshotProvider.future);
  return VariantPerformance.byEquipment(snapshot, exerciseId);
});

/// (exerciseId) → PRs per accessory combination (§5).
final accessoryPerformanceProvider =
    FutureProvider.family<List<PerformanceRecord>, int>((ref, exerciseId) async {
  final snapshot = await ref.watch(trainingSnapshotProvider.future);
  return VariantPerformance.byAccessoryCombo(snapshot, exerciseId);
});

final hrVsTonnageProvider = FutureProvider<BiometricCorrelationResult>((ref) async {
  final db = ref.watch(appDatabaseProvider);
  final healthSamples = await db.select(db.healthSamples).get();
  final snapshot = await ref.watch(trainingSnapshotProvider.future);

  return BiometricCorrelations.restingHrVsTonnage(
    healthSamples: healthSamples,
    resolvedSets: snapshot.sets,
  );
});

/// Reference to the shared [WidgetSyncService] singleton (declared in
/// nutrition_providers.dart; accessed here to avoid a duplicate).
/// If nutrition_providers hasn't initialised it yet, this lazily creates one.
final _analyticsWidgetSyncProvider = Provider<WidgetSyncService>((ref) {
  return WidgetSyncService();
});

/// Pushes CNS readiness data to the CNS Load home-screen widget whenever
/// [cnsTrendsProvider] emits new data.
final widgetCnsSyncControllerProvider = Provider<void>((ref) {
  final widgetSync = ref.watch(_analyticsWidgetSyncProvider);
  ref.listen<AsyncValue<CnsTrendsResult>>(
    cnsTrendsProvider,
    (_, next) async {
      if (!next.hasValue) return;
      final t = next.value!;
      await widgetSync.syncCns(
        readinessPct: (t.readiness * 100).round(),
        status: t.status,
      );
    },
    fireImmediately: true,
  );
});

/// Pushes average recovery score to the Recovery Score home-screen widget
/// whenever [recoveryV3Provider] emits new data.
final widgetRecoverySyncControllerProvider = Provider<void>((ref) {
  final widgetSync = ref.watch(_analyticsWidgetSyncProvider);
  ref.listen<AsyncValue<List<MuscleGroupRecovery>>>(
    recoveryV3Provider,
    (_, next) async {
      if (!next.hasValue || next.value!.isEmpty) return;
      final groups = next.value!;
      final avg = groups.fold(0.0, (sum, g) => sum + g.recoveryScore) /
          groups.length;
      await widgetSync.syncRecovery(scorePct: avg.round());
    },
    fireImmediately: true,
  );
});
