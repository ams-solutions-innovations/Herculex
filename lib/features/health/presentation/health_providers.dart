import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:health/health.dart';
import 'package:collection/collection.dart';

import '../../../app/providers.dart';
import '../data/health_service.dart';
import '../../../data/local/database.dart';
import '../domain/activity_adjuster.dart';
import '../domain/health_read_state.dart';

final healthServiceProvider = Provider<HealthService>((ref) {
  final db = ref.watch(appDatabaseProvider);
  final clock = ref.watch(clockProvider);
  return HealthService(db, clock);
});

final todayHealthSamplesProvider = StreamProvider<List<HealthSampleData>>((
  ref,
) {
  final service = ref.watch(healthServiceProvider);
  return service.watchTodaySamples();
});

final lastDailyHealthReadProvider = StateProvider<DailyHealthRead?>((ref) {
  return null;
});

/// Reflects real OS-granted health permission status, keyed by platform
/// ('apple', 'google', 'samsung'). Starts false for all and is reconciled
/// against the actual grant via [HealthService.checkHasPermissions] when the
/// health screens load, since Health Connect / HealthKit authorization state
/// isn't otherwise persisted locally.
final healthPermissionStatusProvider = StateProvider<Map<String, bool>>((ref) {
  return {'apple': false, 'google': false, 'samsung': false};
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

final externalWorkoutReadProvider =
    FutureProvider<HealthRead<List<HealthDataPoint>>>((ref) async {
      final service = ref.watch(healthServiceProvider);
      return service.readWorkouts(14); // 14 days is enough for recovery window
    });

final externalWorkoutsProvider = FutureProvider<List<HealthDataPoint>>((
  ref,
) async {
  final read = await ref.watch(externalWorkoutReadProvider.future);
  return read.value ?? const [];
});

final autoAdjustGymVolumeProvider = StateProvider<bool>((ref) {
  return true;
});

final activityBasedAdjustmentProvider =
    FutureProvider<ActivityAdjustmentResult>((ref) async {
      final samplesAsync = ref.watch(todayHealthSamplesProvider);
      final samples = samplesAsync.asData?.value ?? [];

      final lastRead = ref.watch(lastDailyHealthReadProvider);
      final stepsRead = lastRead?.steps;
      final todaySteps = stepsRead?.isAvailable == true
          ? stepsRead?.value
          : samples.where((s) => s.kind == 'steps').firstOrNull?.value;
      if (todaySteps == null) return ActivityAdjustmentResult.unavailable;

      final service = ref.watch(healthServiceProvider);
      final baselineSteps = await service.getAverageSteps(30);
      if (!baselineSteps.isAvailable || baselineSteps.value == null) {
        return ActivityAdjustmentResult.unavailable;
      }

      final autoAdjust = ref.watch(autoAdjustGymVolumeProvider);
      if (!autoAdjust) return ActivityAdjustmentResult.normal;

      final sleepHours = lastRead?.sleepHours.isAvailable == true
          ? lastRead?.sleepHours.value
          : samples.where((s) => s.kind == 'sleep_hours').firstOrNull?.value;

      final restingHr = lastRead?.restingHr.isAvailable == true
          ? lastRead?.restingHr.value
          : samples.where((s) => s.kind == 'resting_hr').firstOrNull?.value;

      return ActivityBasedAdjuster.suggest(
        todaySteps: todaySteps,
        baselineSteps: baselineSteps.value!,
        sleepHours: sleepHours,
        restingHr: restingHr,
      );
    });
