import 'dart:math';

import 'package:herculex/features/nutrition/domain/tdee_estimate.dart';

/// Turns recent step data plus logged training into a continuous activity
/// multiplier for TDEE, used when logging adherence is too thin for the
/// observed-expenditure path (TDEE-02).
///
/// The output is a `double`, never an `ActivityLevel`: the four-bucket enum is
/// exactly the coarseness this phase exists to remove.
///
/// The anchor coefficients below are LOW-confidence assumption A7 and are
/// expected to be retuned after real usage; they all live here as constants so
/// that is a one-place change.
///
/// `activeKcalPerDay`, `sleepHoursPerNight` and `restingHr` are deliberately
/// NOT used in the multiplier or the confidence. They are recorded-only inputs
/// (see [ActivityClassification.toInputs]): active calories would double-count
/// with `countBurnedCalories`, and sleep / resting HR have no defensible
/// mapping to expenditure. The UI must not present them as inputs the estimate
/// used.
///
/// The seed multiplier is the manual `ActivityLevel` pick. It is blended in by
/// data sparsity, so a Profile reset (D-14) matters until enough data exists
/// and never after (D-15). Nothing here discards history.
class ActivityClassifier {
  const ActivityClassifier._();

  /// Look-back window the caller uses to collect step days.
  static const int windowDays = 14;

  /// Below this many step days the classifier reports unavailable (D-08).
  static const int minStepDays = 3;

  /// Step days at which the seed stops contributing.
  static const int fullWeightStepDays = 14;

  /// Ordered (steps per day, activity factor) anchors.
  static const List<(double, double)> stepAnchors = [
    (3000, 1.20),
    (7500, 1.375),
    (10000, 1.55),
    (15000, 1.725),
  ];

  static const double trainingBonusPerWorkout = 0.02;
  static const double trainingBonusCap = 0.10;
  static const double minMultiplier = 1.15;
  static const double maxMultiplier = 1.90;

  /// Step days from which confidence is medium rather than low.
  static const int mediumConfidenceStepDays = 10;

  /// [dailySteps] holds one value per day that has a steps sample in the last
  /// [windowDays] days. The caller filters `HealthSamples.kind == 'steps'` and
  /// never passes `food_kcal` / `weight_kg` rows. Non-finite and negative
  /// values are ignored.
  static ActivityClassification classify({
    required List<double> dailySteps,
    required double workoutsPerWeek,
    required double seedMultiplier,
    double? activeKcalPerDay,
    double? sleepHoursPerNight,
    double? restingHr,
  }) {
    final steps = [
      for (final s in dailySteps)
        if (s.isFinite && s >= 0) s,
    ];
    final stepDays = steps.length;
    if (stepDays < minStepDays) return ActivityClassification.unavailable;

    final avgSteps = steps.reduce((a, b) => a + b) / stepDays;
    final workouts = workoutsPerWeek.isFinite ? max(0.0, workoutsPerWeek) : 0.0;

    final base = _baseFactor(avgSteps);
    final bonus = min(trainingBonusCap, trainingBonusPerWorkout * workouts);
    final dataWeight = min(1.0, stepDays / fullWeightStepDays);
    final blended =
        dataWeight * (base + bonus) + (1 - dataWeight) * seedMultiplier;
    final multiplier = blended.clamp(minMultiplier, maxMultiplier).toDouble();

    return ActivityClassification(
      isAvailable: true,
      multiplier: multiplier,
      // Never high (RESEARCH #6): step counts alone cannot justify it.
      confidence: stepDays >= mediumConfidenceStepDays
          ? TdeeConfidence.medium
          : TdeeConfidence.low,
      stepDays: stepDays,
      avgSteps: avgSteps,
      workoutsPerWeek: workouts,
      seedWeight: 1 - dataWeight,
      activeKcalPerDay: activeKcalPerDay,
      sleepHoursPerNight: sleepHoursPerNight,
      restingHr: restingHr,
    );
  }

  /// Linear interpolation between the surrounding anchors, clamped to the
  /// first / last anchor factor outside the range.
  static double _baseFactor(double avgSteps) {
    final first = stepAnchors.first;
    final last = stepAnchors.last;
    if (avgSteps <= first.$1) return first.$2;
    if (avgSteps >= last.$1) return last.$2;
    for (var i = 1; i < stepAnchors.length; i++) {
      final lo = stepAnchors[i - 1];
      final hi = stepAnchors[i];
      if (avgSteps <= hi.$1) {
        final t = (avgSteps - lo.$1) / (hi.$1 - lo.$1);
        return lo.$2 + t * (hi.$2 - lo.$2);
      }
    }
    return last.$2;
  }
}

/// Result of [ActivityClassifier.classify].
class ActivityClassification {
  const ActivityClassification({
    required this.isAvailable,
    required this.multiplier,
    required this.confidence,
    required this.stepDays,
    required this.avgSteps,
    required this.workoutsPerWeek,
    required this.seedWeight,
    this.activeKcalPerDay,
    this.sleepHoursPerNight,
    this.restingHr,
  });

  /// Returned when there are fewer than [ActivityClassifier.minStepDays] days
  /// of step data; the caller falls through to cold start (D-08).
  static const unavailable = ActivityClassification(
    isAvailable: false,
    multiplier: 0,
    confidence: TdeeConfidence.low,
    stepDays: 0,
    avgSteps: 0,
    workoutsPerWeek: 0,
    seedWeight: 0,
  );

  final bool isAvailable;
  final double multiplier;
  final TdeeConfidence confidence;
  final int stepDays;
  final double avgSteps;
  final double workoutsPerWeek;

  /// Share of the multiplier that came from the manual seed (1 - data weight).
  final double seedWeight;

  // Recorded for display only; never enter the multiplier or confidence.
  final double? activeKcalPerDay;
  final double? sleepHoursPerNight;
  final double? restingHr;

  /// Becomes `TdeeEstimateResult.inputs`, which the sheet shows individually
  /// (D-06). `active_kcal`, `sleep_hours` and `resting_hr` are recorded for
  /// display only and appear only when non-null.
  Map<String, Object?> toInputs() => {
    'avg_steps': avgSteps.round(),
    'step_days': stepDays,
    'workouts_per_week': workoutsPerWeek,
    'activity_factor': _round3(multiplier),
    'seed_weight': _round3(seedWeight),
    if (activeKcalPerDay != null) 'active_kcal': activeKcalPerDay,
    if (sleepHoursPerNight != null) 'sleep_hours': sleepHoursPerNight,
    if (restingHr != null) 'resting_hr': restingHr,
  };

  static double _round3(double v) => (v * 1000).round() / 1000;
}
