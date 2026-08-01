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
    'samsung': false,
  };
});

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
