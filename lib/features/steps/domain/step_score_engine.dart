// Engine classifying step counts into physiological activity zones and computing movement scores.
// Pure Dart: no Flutter or Drift dependencies.

/// Physiological activity tiers based on daily step volume.
enum StepActivityZone {
  sedentary,
  lightlyActive,
  optimal,
  highNeat,
  exhaustive,
  extreme;

  String get displayName {
    switch (this) {
      case StepActivityZone.sedentary:
        return 'Sedentary';
      case StepActivityZone.lightlyActive:
        return 'Lightly Active';
      case StepActivityZone.optimal:
        return 'Optimal Recovery Zone';
      case StepActivityZone.highNeat:
        return 'High NEAT';
      case StepActivityZone.exhaustive:
        return 'Exhaustive Activity';
      case StepActivityZone.extreme:
        return 'Extreme Fatigue';
    }
  }

  String get description {
    switch (this) {
      case StepActivityZone.sedentary:
        return 'Low circulation and stiff pelvic joints. Requires thorough warm-up.';
      case StepActivityZone.lightlyActive:
        return 'Moderate activity maintaining basic baseline circulation.';
      case StepActivityZone.optimal:
        return 'Goldilocks zone: optimal blood flow, lymph drainage, and zero glycogen drain.';
      case StepActivityZone.highNeat:
        return 'Significant caloric expenditure. Great for fat loss, watch lower-body fatigue.';
      case StepActivityZone.exhaustive:
        return 'High axial and leg muscular fatigue. Glycogen reserves depleted.';
      case StepActivityZone.extreme:
        return 'Severe fatigue. Risk of form breakdown on heavy squats and deadlifts.';
    }
  }
}

/// Composite movement and activity rating (0-100).
class StepMovementScore {
  final int score;
  final StepActivityZone zone;
  final String statusLabel;
  final String summary;

  const StepMovementScore({
    required this.score,
    required this.zone,
    required this.statusLabel,
    required this.summary,
  });
}

/// Algorithmic evaluator converting daily step volume and goal into a movement score.
class StepScoreEngine {
  const StepScoreEngine._();

  /// Determines physiological zone based on absolute step count.
  static StepActivityZone determineZone(int steps) {
    if (steps < 5000) return StepActivityZone.sedentary;
    if (steps < 7500) return StepActivityZone.lightlyActive;
    if (steps < 12000) return StepActivityZone.optimal;
    if (steps < 18000) return StepActivityZone.highNeat;
    if (steps < 25000) return StepActivityZone.exhaustive;
    return StepActivityZone.extreme;
  }

  /// Calculates a holistic movement score between 0 and 100.
  static StepMovementScore calculate({required int steps, int goal = 10000}) {
    final zone = determineZone(steps);
    final target = goal > 0 ? goal : 10000;

    // Base score driven by percentage of goal achieved (up to 70 points)
    final goalRatio = (steps / target).clamp(0.0, 1.5);
    final goalComponent = (goalRatio * 70.0).clamp(0.0, 70.0);

    // Zone bonus (up to 30 points) favoring the prime recovery zone (7.5k - 12k)
    double zoneBonus;
    switch (zone) {
      case StepActivityZone.sedentary:
        zoneBonus = (steps / 5000.0) * 10.0;
        break;
      case StepActivityZone.lightlyActive:
        zoneBonus = 18.0;
        break;
      case StepActivityZone.optimal:
        zoneBonus = 30.0; // Peak physiological recovery bonus
        break;
      case StepActivityZone.highNeat:
        zoneBonus = 24.0; // Slight deduction for leg fatigue
        break;
      case StepActivityZone.exhaustive:
        zoneBonus = 15.0; // Noticeable deduction for glycogen depletion
        break;
      case StepActivityZone.extreme:
        zoneBonus = 8.0; // High risk of overtraining
        break;
    }

    final rawScore = (goalComponent + zoneBonus).round().clamp(0, 100);

    String label;
    String summary;

    if (rawScore >= 90) {
      label = 'PRIME MOVEMENT';
      summary =
          'Outstanding activity balance. Stimulates muscle recovery without accumulating leg fatigue.';
    } else if (rawScore >= 75) {
      label = 'HEALTHY ACTIVE';
      summary =
          'Solid daily movement. Promotes good venous return and cardiovascular baseline.';
    } else if (rawScore >= 50) {
      label = 'MODERATE';
      summary =
          'Adequate baseline. A brief 15-minute walk will elevate you into optimal recovery.';
    } else {
      label = 'INSUFFICIENT';
      summary =
          'Movement below recovery baseline. Increased risk of pelvic tightness before heavy lifting.';
    }

    return StepMovementScore(
      score: rawScore,
      zone: zone,
      statusLabel: label,
      summary: summary,
    );
  }
}
