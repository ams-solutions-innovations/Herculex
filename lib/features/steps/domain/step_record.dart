// Domain model representing step telemetry for a single calendar day.
// Pure Dart: no Flutter or Drift dependencies.

/// Encapsulates all step-related telemetry for a given calendar date.
class StepRecord {
  final String dateIso;
  final int stepCount;
  final int goal;
  final double distanceKm;
  final double activeKcal;
  final int activeMinutes;
  final Map<int, int> hourlySteps;

  const StepRecord({
    required this.dateIso,
    required this.stepCount,
    this.goal = 10000,
    required this.distanceKm,
    required this.activeKcal,
    required this.activeMinutes,
    this.hourlySteps = const {},
  });

  /// Factory creating default metrics with estimated distance and calories
  /// if only raw step count is available.
  factory StepRecord.fromStepCount({
    required String dateIso,
    required int stepCount,
    int goal = 10000,
    double? distanceKm,
    double? activeKcal,
    int? activeMinutes,
    Map<int, int>? hourlySteps,
  }) {
    // Standard biomechanical estimates: ~0.762m per stride, ~0.04 kcal per step
    final estimatedKm = distanceKm ?? (stepCount * 0.000762);
    final estimatedKcal = activeKcal ?? (stepCount * 0.04);
    final estimatedMin = activeMinutes ?? ((stepCount / 110).round());

    return StepRecord(
      dateIso: dateIso,
      stepCount: stepCount,
      goal: goal > 0 ? goal : 10000,
      distanceKm: double.parse(estimatedKm.toStringAsFixed(2)),
      activeKcal: double.parse(estimatedKcal.toStringAsFixed(1)),
      activeMinutes: estimatedMin,
      hourlySteps: hourlySteps ?? const {},
    );
  }

  /// Ratio of achieved steps against the daily goal (0.0 to 1.0+).
  double get progressRatio => goal > 0 ? stepCount / goal : 0.0;

  /// Clamped progress percentage (0.0 to 100.0) for UI progress bars.
  double get progressPercentage => (progressRatio * 100).clamp(0.0, 100.0);

  /// True if daily step target has been reached or exceeded.
  bool get isGoalReached => stepCount >= goal;

  /// Remaining steps needed to reach daily target.
  int get remainingSteps => (goal - stepCount).clamp(0, goal);

  StepRecord copyWith({
    String? dateIso,
    int? stepCount,
    int? goal,
    double? distanceKm,
    double? activeKcal,
    int? activeMinutes,
    Map<int, int>? hourlySteps,
  }) {
    return StepRecord(
      dateIso: dateIso ?? this.dateIso,
      stepCount: stepCount ?? this.stepCount,
      goal: goal ?? this.goal,
      distanceKm: distanceKm ?? this.distanceKm,
      activeKcal: activeKcal ?? this.activeKcal,
      activeMinutes: activeMinutes ?? this.activeMinutes,
      hourlySteps: hourlySteps ?? this.hourlySteps,
    );
  }
}
