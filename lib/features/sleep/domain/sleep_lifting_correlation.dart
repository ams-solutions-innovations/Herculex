// Correlates historical sleep telemetry with gym performance metrics (RPE and tonnage).
// Pure Dart: no Flutter or Drift dependencies.

import 'dart:math';

import 'package:herculex/data/local/database.dart';
import 'package:herculex/features/analytics/domain/biometric_correlations.dart';
import 'package:herculex/features/analytics/domain/training_snapshot.dart';

export 'package:herculex/features/analytics/domain/biometric_correlations.dart'
    show CorrelationPoint;

/// Correlation analysis linking sleep duration to lifting performance.
class SleepLiftingCorrelation {
  final List<CorrelationPoint> sleepVsRpePoints;
  final double r2Rpe;
  final List<CorrelationPoint> sleepVsTonnagePoints;
  final double r2Tonnage;
  final String rpeInsight;
  final String tonnageInsight;

  const SleepLiftingCorrelation({
    required this.sleepVsRpePoints,
    required this.r2Rpe,
    required this.sleepVsTonnagePoints,
    required this.r2Tonnage,
    required this.rpeInsight,
    required this.tonnageInsight,
  });

  /// Factory for empty/uninitialized correlation states.
  factory SleepLiftingCorrelation.empty() {
    return const SleepLiftingCorrelation(
      sleepVsRpePoints: [],
      r2Rpe: 0.0,
      sleepVsTonnagePoints: [],
      r2Tonnage: 0.0,
      rpeInsight:
          'Insufficient data. Log at least 3 workouts with sleep to generate RPE insights.',
      tonnageInsight:
          'Insufficient data. Log at least 3 workouts with sleep to generate tonnage insights.',
    );
  }

  /// Calculates correlations and insights from raw health samples and resolved sets.
  static SleepLiftingCorrelation compute({
    required List<HealthSampleData> healthSamples,
    required List<ResolvedSet> resolvedSets,
  }) {
    if (healthSamples.isEmpty || resolvedSets.isEmpty) {
      return SleepLiftingCorrelation.empty();
    }

    // Map sleep hours by calendar date
    final sleepByDate = <String, double>{};
    for (final sample in healthSamples) {
      if (sample.kind == 'sleep_hours') {
        sleepByDate[sample.dateIso] = sample.value;
      }
    }

    if (sleepByDate.isEmpty) {
      return SleepLiftingCorrelation.empty();
    }

    // Group resolved sets by workout session
    final setsBySession = <int, List<ResolvedSet>>{};
    final sessionMap = <int, WorkoutSessionData>{};
    for (final resolved in resolvedSets) {
      setsBySession.putIfAbsent(resolved.session.id, () => []).add(resolved);
      sessionMap[resolved.session.id] = resolved.session;
    }

    final sleepVsRpePoints = <CorrelationPoint>[];
    final sleepVsTonnagePoints = <CorrelationPoint>[];

    for (final entry in setsBySession.entries) {
      final sessionId = entry.key;
      final sessionSets = entry.value;
      final session = sessionMap[sessionId];
      if (session == null) {
        continue;
      }

      final dateStr = _formatDateIso(session.startedAt);
      final sleepHrs = sleepByDate[dateStr];
      if (sleepHrs == null || sleepHrs <= 0.0) {
        continue;
      }

      // Calculate average session RPE across logged working sets
      double rpeSum = 0.0;
      int rpeCount = 0;
      double sessionTonnage = 0.0;

      for (final s in sessionSets) {
        if (s.set.rpeX10 != null) {
          rpeSum += s.set.rpeX10! / 10.0;
          rpeCount++;
        }
        sessionTonnage += s.tonnageKg;
      }

      if (rpeCount > 0) {
        final avgRpe = rpeSum / rpeCount;
        sleepVsRpePoints.add(CorrelationPoint(sleepHrs, avgRpe));
      }

      if (sessionTonnage > 0.0) {
        sleepVsTonnagePoints.add(CorrelationPoint(sleepHrs, sessionTonnage));
      }
    }

    final rpeStats = _computeStats(sleepVsRpePoints);
    final tonnageStats = _computeStats(sleepVsTonnagePoints);

    final rpeInsight = _generateRpeInsight(
      count: sleepVsRpePoints.length,
      r2: rpeStats.r2,
      slope: rpeStats.slope,
    );

    final tonnageInsight = _generateTonnageInsight(
      count: sleepVsTonnagePoints.length,
      r2: tonnageStats.r2,
      slope: tonnageStats.slope,
    );

    return SleepLiftingCorrelation(
      sleepVsRpePoints: sleepVsRpePoints,
      r2Rpe: rpeStats.r2,
      sleepVsTonnagePoints: sleepVsTonnagePoints,
      r2Tonnage: tonnageStats.r2,
      rpeInsight: rpeInsight,
      tonnageInsight: tonnageInsight,
    );
  }

  static ({double r2, double slope}) _computeStats(
    List<CorrelationPoint> points,
  ) {
    final n = points.length;
    if (n < 2) {
      return (r2: 0.0, slope: 0.0);
    }

    double sumX = 0.0;
    double sumY = 0.0;
    double sumXY = 0.0;
    double sumX2 = 0.0;
    double sumY2 = 0.0;

    for (final p in points) {
      sumX += p.x;
      sumY += p.y;
      sumXY += p.x * p.y;
      sumX2 += p.x * p.x;
      sumY2 += p.y * p.y;
    }

    final numerator = n * sumXY - sumX * sumY;
    final denominatorX = n * sumX2 - sumX * sumX;
    final denominatorY = n * sumY2 - sumY * sumY;

    final slope = denominatorX != 0.0 ? numerator / denominatorX : 0.0;

    final den = sqrt(denominatorX * denominatorY);
    if (den == 0.0) {
      return (r2: 0.0, slope: slope);
    }

    final r = numerator / den;
    final r2 = (r * r).clamp(0.0, 1.0);

    return (r2: r2, slope: slope);
  }

  static String _generateRpeInsight({
    required int count,
    required double r2,
    required double slope,
  }) {
    if (count < 3) {
      return 'Insufficient data ($count sessions recorded with sleep). Log at least 3 sessions to reveal exertion trends.';
    }

    final r2Str = r2.toStringAsFixed(2);
    if (r2 >= 0.5) {
      if (slope < 0) {
        return 'Strong inverse correlation (R² = $r2Str): Each additional hour of sleep is strongly associated with lower perceived effort (RPE) on working sets.';
      } else {
        return 'Strong correlation detected between sleep duration and perceived exertion (R² = $r2Str).';
      }
    } else if (r2 >= 0.25) {
      if (slope < 0) {
        return 'Moderate correlation (R² = $r2Str): Longer sleep consistently corresponds with reduced perceived effort during top sets.';
      } else {
        return 'Moderate correlation detected between sleep and session RPE (R² = $r2Str).';
      }
    } else {
      return 'Weak correlation (R² = $r2Str): Session RPE is currently influenced more by exercise selection and programming than sleep duration alone.';
    }
  }

  static String _generateTonnageInsight({
    required int count,
    required double r2,
    required double slope,
  }) {
    if (count < 3) {
      return 'Insufficient data ($count sessions recorded with sleep). Log more sessions to correlate sleep with training volume.';
    }

    final r2Str = r2.toStringAsFixed(2);
    if (r2 >= 0.5) {
      if (slope > 0) {
        return 'Strong positive correlation (R² = $r2Str): Optimal sleep consistently enables significantly higher total tonnage moved.';
      } else {
        return 'Strong correlation detected between sleep hours and workout tonnage (R² = $r2Str).';
      }
    } else if (r2 >= 0.25) {
      if (slope > 0) {
        return 'Moderate correlation (R² = $r2Str): Well-rested days correspond with higher volume completion.';
      } else {
        return 'Moderate correlation detected between sleep duration and tonnage (R² = $r2Str).';
      }
    } else {
      return 'Weak correlation (R² = $r2Str): Session tonnage is primarily dictated by scheduled workout templates rather than nightly sleep fluctuation.';
    }
  }

  static String _formatDateIso(DateTime dt) {
    final y = dt.year.toString().padLeft(4, '0');
    final m = dt.month.toString().padLeft(2, '0');
    final d = dt.day.toString().padLeft(2, '0');
    return '$y-$m-$d';
  }
}
