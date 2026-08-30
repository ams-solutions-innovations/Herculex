import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/providers.dart';
import '../domain/muscle_volume_details.dart';
import 'analytics_providers.dart';

enum MuscleVolumeSort {
  volumeDesc('Highest Volume'),
  setsDesc('Most Sets'),
  nameAsc('A to Z');

  final String label;
  const MuscleVolumeSort(this.label);
}

enum MuscleRegionFilter {
  all('All Muscles'),
  upper('Upper Body'),
  lower('Lower Body'),
  core('Core');

  final String label;
  const MuscleRegionFilter(this.label);
}

enum VolumeMetricDisplayMode {
  total('Total'),
  weeklyAvg('Avg / Week');

  final String label;
  const VolumeMetricDisplayMode(this.label);
}

/// Display metric mode: Total Volume / Sets vs Average Weekly Volume / Sets.
final volumeMetricDisplayModeProvider =
    StateProvider<VolumeMetricDisplayMode>((ref) => VolumeMetricDisplayMode.total);

/// Active timeframe for both overview and detail volume views.
final selectedVolumeTimeframeProvider =
    StateProvider<VolumeTimeframe>((ref) => VolumeTimeframe.thisWeek);

/// Sort option on overview screen.
final volumeSortByProvider =
    StateProvider<MuscleVolumeSort>((ref) => MuscleVolumeSort.volumeDesc);

/// Region filter on overview screen.
final volumeRegionFilterProvider =
    StateProvider<MuscleRegionFilter>((ref) => MuscleRegionFilter.all);

/// Overview data for all 19 muscle groups.
final muscleVolumeOverviewProvider =
    FutureProvider<MuscleVolumeOverviewData>((ref) async {
  final snapshot = await ref.watch(trainingSnapshotProvider.future);
  final timeframe = ref.watch(selectedVolumeTimeframeProvider);
  final asOf = ref.watch(clockProvider).now();

  return MuscleVolumeAnalyticsEngine.computeOverview(
    snapshot: snapshot,
    asOf: asOf,
    timeframe: timeframe,
  );
});

/// Detailed session-by-session workout & exercise logs for a specific muscle.
final muscleVolumeDetailProvider =
    FutureProvider.family<MuscleGroupDetailData, String>((ref, muscle) async {
  final snapshot = await ref.watch(trainingSnapshotProvider.future);
  final timeframe = ref.watch(selectedVolumeTimeframeProvider);
  final asOf = ref.watch(clockProvider).now();

  return MuscleVolumeAnalyticsEngine.computeMuscleDetail(
    snapshot: snapshot,
    muscle: muscle,
    asOf: asOf,
    timeframe: timeframe,
  );
});
