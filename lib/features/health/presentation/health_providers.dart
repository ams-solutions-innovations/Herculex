import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:health/health.dart';

import '../../../app/providers.dart';
import '../data/health_service.dart';
import '../../../data/local/database.dart';
import '../domain/activity_adjuster.dart';

final healthServiceProvider = Provider<HealthService>((ref) {
  final db = ref.watch(appDatabaseProvider);
  final clock = ref.watch(clockProvider);
  return HealthService(db, clock);
});

final todayHealthSamplesProvider = StreamProvider<List<HealthSampleData>>((ref) {
  final service = ref.watch(healthServiceProvider);
  return service.watchTodaySamples();
});

final healthPermissionStatusProvider = StateProvider<Map<String, bool>>((ref) {
  return {
    'apple': false,
    'google': false,
    'samsung': true, // Samsung Health integration option enabled by default
  };
});

/// Granular Samsung Health Sync categories toggles
final samsungHealthSyncFoodProvider = StateProvider<bool>((ref) => true);
final samsungHealthSyncWaterProvider = StateProvider<bool>((ref) => true);
final samsungHealthSyncStepsProvider = StateProvider<bool>((ref) => true);
final samsungHealthSyncWorkoutsProvider = StateProvider<bool>((ref) => true);
final samsungHealthSyncSleepProvider = StateProvider<bool>((ref) => true);
final samsungHealthSyncBiometricsProvider = StateProvider<bool>((ref) => true);
final samsungHealthSyncWeightProvider = StateProvider<bool>((ref) => true);

/// Auto sync 3x per day enabled state
final samsungHealthAutoSync3xProvider = StateProvider<bool>((ref) => true);
final samsungHealthBidirectionalProvider = StateProvider<bool>((ref) => true);

/// Granular Apple Health Sync categories toggles
final appleHealthSyncFoodProvider = StateProvider<bool>((ref) => true);
final appleHealthSyncWaterProvider = StateProvider<bool>((ref) => true);
final appleHealthSyncStepsProvider = StateProvider<bool>((ref) => true);
final appleHealthSyncWorkoutsProvider = StateProvider<bool>((ref) => true);
final appleHealthSyncSleepProvider = StateProvider<bool>((ref) => true);
final appleHealthSyncBiometricsProvider = StateProvider<bool>((ref) => true);
final appleHealthSyncWeightProvider = StateProvider<bool>((ref) => true);
final appleHealthSyncMindfulnessProvider = StateProvider<bool>((ref) => false);
final appleHealthAutoSyncProvider = StateProvider<bool>((ref) => true);
final appleHealthBidirectionalProvider = StateProvider<bool>((ref) => true);

/// Granular Google Health Connect Sync categories toggles
final googleHealthSyncFoodProvider = StateProvider<bool>((ref) => true);
final googleHealthSyncWaterProvider = StateProvider<bool>((ref) => true);
final googleHealthSyncStepsProvider = StateProvider<bool>((ref) => true);
final googleHealthSyncWorkoutsProvider = StateProvider<bool>((ref) => true);
final googleHealthSyncSleepProvider = StateProvider<bool>((ref) => true);
final googleHealthSyncBiometricsProvider = StateProvider<bool>((ref) => true);
final googleHealthSyncWeightProvider = StateProvider<bool>((ref) => true);
final googleHealthSyncBloodOxygenProvider = StateProvider<bool>((ref) => false);
final googleHealthAutoSyncProvider = StateProvider<bool>((ref) => true);
final googleHealthBidirectionalProvider = StateProvider<bool>((ref) => true);

/// Last sync timestamp provider
final lastHealthSyncTimestampProvider = StateProvider<DateTime?>((ref) => null);

final externalWorkoutsProvider = FutureProvider<List<HealthDataPoint>>((ref) async {
  final service = ref.watch(healthServiceProvider);
  return service.getWorkouts(14); // 14 days is enough for recovery window
});

final autoAdjustGymVolumeProvider = StateProvider<bool>((ref) {
  return true;
});

final activityBasedAdjustmentProvider = FutureProvider<ActivityAdjustmentResult>((ref) async {
  final samplesAsync = ref.watch(todayHealthSamplesProvider);
  final samples = samplesAsync.asData?.value ?? [];

  final todaySteps = samples.firstWhere((s) => s.kind == 'steps', orElse: () => HealthSampleData(id: 0, dateIso: '', kind: 'steps', value: 0.0)).value;
  final service = ref.watch(healthServiceProvider);
  final baselineSteps = await service.getAverageSteps(30);

  final autoAdjust = ref.watch(autoAdjustGymVolumeProvider);
  if (!autoAdjust) return ActivityAdjustmentResult.normal;

  return ActivityBasedAdjuster.suggest(
    todaySteps: todaySteps,
    baselineSteps: baselineSteps,
  );
});
