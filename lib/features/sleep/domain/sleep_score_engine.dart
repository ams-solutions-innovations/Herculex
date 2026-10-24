// Engine for calculating physiological sleep recovery scores.
// Pure Dart: no Flutter or Drift dependencies.

import 'package:herculex/features/sleep/domain/sleep_record.dart';

/// Qualitative recovery tier derived from the composite sleep score.
enum SleepRecoveryCategory { optimal, prime, fair, deficit, critical }

/// Evaluated sleep score with clinical/physiological tier and actionable guidance.
class SleepRecoveryScore {
  final int score;
  final SleepRecoveryCategory category;
  final String title;
  final String description;

  const SleepRecoveryScore({
    required this.score,
    required this.category,
    required this.title,
    required this.description,
  });

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is SleepRecoveryScore &&
          runtimeType == other.runtimeType &&
          score == other.score &&
          category == other.category &&
          title == other.title &&
          description == other.description;

  @override
  int get hashCode => Object.hash(score, category, title, description);

  @override
  String toString() =>
      'SleepRecoveryScore(score: $score, category: ${category.name}, title: "$title")';
}

/// Pure calculation engine for determining athletic sleep recovery.
///
/// Weighting criteria:
/// - Duration vs target hours: up to 50 points
/// - Deep sleep percentage (optimal 15-25%): up to 25 points
/// - REM sleep percentage (optimal 20-25%): up to 15 points
/// - Sleep debt penalty: up to -15 points
/// - Efficiency / excessive awake penalty: up to -15 points
class SleepScoreEngine {
  const SleepScoreEngine._();

  /// Calculates a [SleepRecoveryScore] (0 to 100) from a [SleepRecord].
  static SleepRecoveryScore calculate(SleepRecord record) {
    if (record.totalHours <= 0.0) {
      return const SleepRecoveryScore(
        score: 0,
        category: SleepRecoveryCategory.critical,
        title: 'Critical Deprivation',
        description:
            'Zero or negligible sleep recorded. Central nervous system drive and motor control are severely impaired.',
      );
    }

    final target = record.targetHours > 0 ? record.targetHours : 8.0;
    final durationRatio = (record.totalHours / target).clamp(0.0, 1.5);

    // 1. Duration Points (up to 50 pts)
    final double durationPts;
    if (durationRatio >= 1.0) {
      durationPts = 50.0;
    } else {
      durationPts = (durationRatio * 50.0).clamp(0.0, 50.0);
    }

    // 2. Deep Sleep Points (optimal ~15-25% = up to 25 pts)
    final double deepPts;
    if (record.stages != null && record.stages!.totalSleepMinutes > 0) {
      final deepPct = record.stages!.deepPercentage;
      if (deepPct >= 15.0 && deepPct <= 25.0) {
        deepPts = 25.0;
      } else if (deepPct < 15.0) {
        deepPts = (deepPct / 15.0 * 25.0).clamp(0.0, 25.0);
      } else {
        // Above 25% is still restorative, apply very mild taper
        deepPts = (25.0 - (deepPct - 25.0) * 0.4).clamp(18.0, 25.0);
      }
    } else {
      // Without stage telemetry, prorate based on overall duration
      deepPts = (durationRatio.clamp(0.0, 1.0) * 22.0);
    }

    // 3. REM Sleep Points (optimal ~20-25% = up to 15 pts)
    final double remPts;
    if (record.stages != null && record.stages!.totalSleepMinutes > 0) {
      final remPct = record.stages!.remPercentage;
      if (remPct >= 20.0 && remPct <= 25.0) {
        remPts = 15.0;
      } else if (remPct < 20.0) {
        remPts = (remPct / 20.0 * 15.0).clamp(0.0, 15.0);
      } else {
        remPts = (15.0 - (remPct - 25.0) * 0.3).clamp(11.0, 15.0);
      }
    } else {
      remPts = (durationRatio.clamp(0.0, 1.0) * 13.0);
    }

    // 4. Sleep Debt Penalty (up to -15 pts)
    final debt = record.sleepDebtHours;
    final double debtPenalty;
    if (debt > 0) {
      debtPenalty = (debt / 2.5 * 15.0).clamp(0.0, 15.0);
    } else {
      debtPenalty = 0.0;
    }

    // 5. Sleep Efficiency / Awake Penalty (up to -15 pts)
    double efficiencyPenalty = 0.0;
    final efficiency = record.sleepEfficiency;
    if (efficiency < 0.85) {
      efficiencyPenalty += ((0.85 - efficiency) / 0.35 * 12.0).clamp(0.0, 12.0);
    }
    if (record.stages != null && record.stages!.awakeMinutes > 45.0) {
      efficiencyPenalty += ((record.stages!.awakeMinutes - 45.0) / 45.0 * 5.0)
          .clamp(0.0, 5.0);
    }
    efficiencyPenalty = efficiencyPenalty.clamp(0.0, 15.0);

    // Composite Calculation
    final rawScore =
        durationPts + deepPts + remPts - debtPenalty - efficiencyPenalty;
    final score = rawScore.round().clamp(0, 100);

    return _scoreToCategory(score);
  }

  static SleepRecoveryScore _scoreToCategory(int score) {
    if (score >= 90) {
      return SleepRecoveryScore(
        score: score,
        category: SleepRecoveryCategory.optimal,
        title: 'Optimal Recovery',
        description:
            'Peak neuromuscular recovery; prime central nervous system state for maximum intensity, volume, and PR attempts.',
      );
    } else if (score >= 75) {
      return SleepRecoveryScore(
        score: score,
        category: SleepRecoveryCategory.prime,
        title: 'Prime Recovery',
        description:
            'Solid physiological and cognitive restoration. Full training capacity available with dependable motor unit recruitment.',
      );
    } else if (score >= 60) {
      return SleepRecoveryScore(
        score: score,
        category: SleepRecoveryCategory.fair,
        title: 'Fair Recovery',
        description:
            'Moderate recovery deficit. Complete programmed working sets, but avoid grinding sets to absolute muscular failure.',
      );
    } else if (score >= 40) {
      return SleepRecoveryScore(
        score: score,
        category: SleepRecoveryCategory.deficit,
        title: 'Recovery Deficit',
        description:
            'Substantial sleep debt detected. Neural drive is blunted; recommend trimming session volume by 15-20%.',
      );
    } else {
      return SleepRecoveryScore(
        score: score,
        category: SleepRecoveryCategory.critical,
        title: 'Critical Deprivation',
        description:
            'Severe sleep debt and central fatigue. Elevated injury risk; prioritize active recovery, a deload session, or rest.',
      );
    }
  }
}
