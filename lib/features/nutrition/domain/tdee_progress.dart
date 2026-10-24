import 'package:herculex/features/nutrition/domain/tdee_estimator.dart';

/// One requirement the observed (measured) estimate needs before it can run.
class CalibrationGate {
  const CalibrationGate({
    required this.label,
    required this.have,
    required this.need,
  });

  final String label;
  final int have;
  final int need;

  bool get met => have >= need;

  /// 0..1 for a progress bar.
  double get fraction => need <= 0 ? 1 : (have / need).clamp(0.0, 1.0);
}

/// What is still missing before the app can measure maintenance from logs.
///
/// Mirrors the gates in [TdeeEstimator.estimateObserved] for its shortest
/// window ([TdeeTuning.minWindowDays]), the easiest one to reach. Plain Dart:
/// callers pass the clock in. The estimator stays the single source of truth;
/// this only explains it, and the page words it as a guide, not a promise.
class CalibrationProgress {
  const CalibrationProgress(this.gates);

  final List<CalibrationGate> gates;

  bool get allMet => gates.every((g) => g.met);

  factory CalibrationProgress.evaluate({
    required DateTime asOf,
    required Set<String> foodLoggedDays,
    required List<WeightLog> weightLogs,
  }) {
    const w = TdeeTuning.minWindowDays;
    final asOfDay = TrendSeries.dayNumber(asOf);
    final windowStart = asOfDay - (w - 1);
    final half = windowStart + (w ~/ 2);

    var foodInWindow = 0;
    var foodRecent = false;
    for (var age = 0; age < w; age++) {
      final day = DateTime(asOf.year, asOf.month, asOf.day - age);
      if (!foodLoggedDays.contains(_iso(day))) continue;
      foodInWindow++;
      if (age <= TdeeTuning.observedRecencyDays) foodRecent = true;
    }

    final weighDays = <int>{
      for (final l in weightLogs)
        if (TrendSeries.dayNumber(l.date) <= asOfDay &&
            TrendSeries.dayNumber(l.date) >= windowStart)
          TrendSeries.dayNumber(l.date),
    };
    final weightRecent = weighDays.any(
      (d) => asOfDay - d <= TdeeTuning.observedRecencyDays,
    );
    final firstHalf = weighDays.any((d) => d < half);
    final secondHalf = weighDays.any((d) => d >= half);

    final weeks = (w + 6) ~/ 7;
    final perWeek = TdeeTuning.weighInsPerWeek * weeks;
    final needWeighIns = perWeek > TdeeTuning.minWeighIns
        ? perWeek
        : TdeeTuning.minWeighIns;

    return CalibrationProgress([
      CalibrationGate(
        label: 'Days with food logged (last $w days)',
        have: foodInWindow,
        need: (TdeeTuning.foodAdherenceBar * w - 1e-9).ceil(),
      ),
      CalibrationGate(
        label: 'Weigh-ins (last $w days)',
        have: weighDays.length,
        need: needWeighIns,
      ),
      CalibrationGate(
        label: 'Weigh-ins in both halves of the period',
        have: (firstHalf ? 1 : 0) + (secondHalf ? 1 : 0),
        need: 2,
      ),
      CalibrationGate(
        label:
            'Food and weight logged in the last '
            '${TdeeTuning.observedRecencyDays} days',
        have: (foodRecent ? 1 : 0) + (weightRecent ? 1 : 0),
        need: 2,
      ),
    ]);
  }

  static String _iso(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}-'
      '${d.month.toString().padLeft(2, '0')}-'
      '${d.day.toString().padLeft(2, '0')}';
}
