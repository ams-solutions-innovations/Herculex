import 'package:herculex/features/health/domain/sleep_summary.dart';

/// What a night's sleep means for how fast the body clears training fatigue.
class SleepRecoveryAssessment {
  const SleepRecoveryAssessment({
    required this.score,
    required this.rateMultiplier,
  });

  /// 0–100 sleep quality for recovery purposes.
  final int score;

  /// Speed of fatigue clearance relative to a normal night: 1.0 is baseline,
  /// below 1.0 means fatigue decays that much more slowly. Never above 1.0 —
  /// the recovery model's baseline already assumes ordinary sleep, so good
  /// sleep restores the baseline instead of inflating it.
  final double rateMultiplier;

  // Value equality, so a provider holding this does not re-notify (and
  // recompute every muscle's recovery) when a sync rewrites identical rows.
  @override
  bool operator ==(Object other) =>
      other is SleepRecoveryAssessment &&
      other.score == score &&
      other.rateMultiplier == rateMultiplier;

  @override
  int get hashCode => Object.hash(score, rateMultiplier);
}

/// Deterministic sleep → recovery model. The weights are heuristics from the
/// sleep literature, not measurements; they live here as named constants so
/// they can be tuned in one place.
///
/// Score (100): duration 60, deep 10, REM 10, efficiency 14, continuity 6.
/// Duration dominates because it is the one input every source reports and the
/// strongest single driver of recovery. A source that reports no stages gets
/// [unknownCredit] of the stage-derived points rather than a penalty — missing
/// data must not read as bad sleep.
abstract final class SleepRecovery {
  static const targetSleepHours = 8.0;

  /// Healthy-adult shares of sleep spent in deep (~13–23%) and REM (~20–25%).
  static const targetDeepShare = 0.15;
  static const targetRemShare = 0.20;

  /// Efficiency (asleep ÷ in bed): full marks at or above, zero at or below.
  static const fullEfficiency = 0.85;
  static const zeroEfficiency = 0.60;

  /// Awakenings tolerated for full continuity marks, and the count at which
  /// the continuity points reach zero.
  static const freeAwakenings = 2;
  static const zeroAwakenings = 8;

  static const _durationPoints = 60.0;
  static const _deepPoints = 10.0;
  static const _remPoints = 10.0;
  static const _efficiencyPoints = 14.0;
  static const _continuityPoints = 6.0;

  /// Fraction of the stage-derived points granted when they are unknown.
  static const unknownCredit = 0.8;

  /// Scores at or above this leave recovery at baseline; the multiplier falls
  /// linearly to [minRateMultiplier] at [floorScore].
  static const baselineScore = 85;
  static const floorScore = 40;
  static const minRateMultiplier = 0.75;

  /// Null when there is no sleep to judge — callers treat that as "no effect".
  static SleepRecoveryAssessment? assess(SleepSummary? sleep) {
    if (sleep == null || sleep.asleepMinutes <= 0) return null;

    final duration =
        (sleep.asleepHours / targetSleepHours).clamp(0.0, 1.0) *
        _durationPoints;

    final deep = _stagePoints(
      sleep.deepShare,
      (s) => (s / targetDeepShare).clamp(0.0, 1.0),
      _deepPoints,
    );
    final rem = _stagePoints(
      sleep.remShare,
      (s) => (s / targetRemShare).clamp(0.0, 1.0),
      _remPoints,
    );
    final efficiency = _stagePoints(
      sleep.hasStages ? sleep.efficiency : null,
      (e) => ((e - zeroEfficiency) / (fullEfficiency - zeroEfficiency)).clamp(
        0.0,
        1.0,
      ),
      _efficiencyPoints,
    );
    final continuity = _stagePoints(
      sleep.awakenings?.toDouble(),
      (n) => (1 - (n - freeAwakenings) / (zeroAwakenings - freeAwakenings))
          .clamp(0.0, 1.0),
      _continuityPoints,
    );

    final score = (duration + deep + rem + efficiency + continuity)
        .round()
        .clamp(0, 100);
    return SleepRecoveryAssessment(
      score: score,
      rateMultiplier: _multiplierFor(score),
    );
  }

  /// Convenience for the recovery engine: 1.0 when there is nothing to judge.
  static double rateMultiplierFor(SleepSummary? sleep) =>
      assess(sleep)?.rateMultiplier ?? 1.0;

  static double _stagePoints(
    double? measured,
    double Function(double) fraction,
    double points,
  ) => measured == null ? unknownCredit * points : fraction(measured) * points;

  static double _multiplierFor(int score) {
    if (score >= baselineScore) return 1.0;
    if (score <= floorScore) return minRateMultiplier;
    final t = (score - floorScore) / (baselineScore - floorScore);
    return minRateMultiplier + (1.0 - minRateMultiplier) * t;
  }
}
