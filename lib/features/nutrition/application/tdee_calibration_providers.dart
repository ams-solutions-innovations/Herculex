import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:herculex/features/nutrition/application/tdee_providers.dart';
import 'package:herculex/features/nutrition/application/tdee_recalibration_controller.dart';
import 'package:herculex/features/nutrition/data/tdee_inputs_repository.dart';
import 'package:herculex/features/nutrition/domain/tdee_estimate.dart';

/// Newest-first estimate history for the calibration page's trend chart.
final tdeeEstimateHistoryProvider =
    StreamProvider.autoDispose<List<TdeeEstimateResult>>((ref) {
      return ref.watch(tdeeEstimatesRepositoryProvider).watchRecent();
    });

/// Raw logs the estimator reads (60 days). Re-read whenever a new estimate
/// lands, since those logs are what produced it.
final tdeeCalibrationInputsProvider = FutureProvider.autoDispose<TdeeInputs>((
  ref,
) {
  ref.watch(latestTdeeEstimateProvider);
  return ref.watch(tdeeInputsRepositoryProvider).load();
});
