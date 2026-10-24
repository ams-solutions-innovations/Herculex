// Correlates historical step telemetry with gym performance metrics (Session RPE and Tonnage).
// Pure Dart: no Flutter or Drift dependencies.

import 'dart:math';

import 'package:herculex/data/local/database.dart';
import 'package:herculex/features/analytics/domain/biometric_correlations.dart';
import 'package:herculex/features/analytics/domain/training_snapshot.dart';

export 'package:herculex/features/analytics/domain/biometric_correlations.dart'
    show CorrelationPoint;

/// Correlation analysis linking daily step counts to lifting performance.
class StepLiftingCorrelation {
  final List<CorrelationPoint> stepsVsRpePoints;
  final double r2Rpe;
  final List<CorrelationPoint> stepsVsTonnagePoints;
  final double r2Tonnage;
  final String rpeInsight;
  final String tonnageInsight;

  const StepLiftingCorrelation({
    required this.stepsVsRpePoints,
    required this.r2Rpe,
    required this.stepsVsTonnagePoints,
    required this.r2Tonnage,
    required this.rpeInsight,
    required this.tonnageInsight,
  });

  /// Factory for empty or uninitialized correlation states.
  factory StepLiftingCorrelation.empty() {
    return const StepLiftingCorrelation(
      stepsVsRpePoints: [],
      r2Rpe: 0.0,
      stepsVsTonnagePoints: [],
      r2Tonnage: 0.0,
      rpeInsight:
          'Insufficient data. Log at least 3 workouts with step counts to generate RPE insights.',
      tonnageInsight:
          'Insufficient data. Log at least 3 workouts with step counts to generate tonnage insights.',
    );
  }

  /// Calculates correlations and insights from raw health samples and resolved sets.
  static StepLiftingCorrelation compute({
    required List<HealthSampleData> healthSamples,
    required List<ResolvedSet> resolvedSets,
  }) {
    if (healthSamples.isEmpty || resolvedSets.isEmpty) {
      return StepLiftingCorrelation.empty();
    }

    // Map total steps by calendar date
    final stepsByDate = <String, double>{};
    for (final sample in healthSamples) {
      if (sample.kind == 'steps') {
        stepsByDate[sample.dateIso] = sample.value;
      }
    }

    if (stepsByDate.isEmpty) {
      return StepLiftingCorrelation.empty();
    }

    // Group resolved sets by workout session
    final setsBySession = <int, List<ResolvedSet>>{};
    final sessionMap = <int, WorkoutSessionData>{};
    for (final resolved in resolvedSets) {
      setsBySession.putIfAbsent(resolved.session.id, () => []).add(resolved);
      sessionMap[resolved.session.id] = resolved.session;
    }

    final stepsVsRpePoints = <CorrelationPoint>[];
    final stepsVsTonnagePoints = <CorrelationPoint>[];

    for (final entry in setsBySession.entries) {
      final sessionId = entry.key;
      final sessionSets = entry.value;
      final session = sessionMap[sessionId];
      if (session == null) continue;

      final dateStr = _formatDateIso(session.startedAt);
      final rawSteps = stepsByDate[dateStr];
      if (rawSteps == null || rawSteps <= 0.0) continue;

      // X-axis value in thousands of steps (e.g., 10.5k steps = 10.5)
      final stepsInK = rawSteps / 1000.0;

      // Average RPE and total tonnage for the session
      double rpeSum = 0.0;
      int rpeCount = 0;
      double sessionTonnage = 0.0;

      for (final s in sessionSets) {
        if (s.set.rpeX10 != null && s.set.rpeX10! > 0) {
          rpeSum += s.set.rpeX10! / 10.0;
          rpeCount++;
        }
        sessionTonnage += s.tonnageKg;
      }

      if (rpeCount > 0) {
        final avgRpe = rpeSum / rpeCount;
        stepsVsRpePoints.add(CorrelationPoint(stepsInK, avgRpe));
      }

      if (sessionTonnage > 0.0) {
        stepsVsTonnagePoints.add(CorrelationPoint(stepsInK, sessionTonnage));
      }
    }

    if (stepsVsRpePoints.length < 3 && stepsVsTonnagePoints.length < 3) {
      return StepLiftingCorrelation.empty();
    }

    final r2Rpe = _computeR2(stepsVsRpePoints);
    final r2Tonnage = _computeR2(stepsVsTonnagePoints);

    final rpeInsight = _buildRpeInsight(stepsVsRpePoints, r2Rpe);
    final tonnageInsight = _buildTonnageInsight(
      stepsVsTonnagePoints,
      r2Tonnage,
    );

    return StepLiftingCorrelation(
      stepsVsRpePoints: stepsVsRpePoints,
      r2Rpe: r2Rpe,
      stepsVsTonnagePoints: stepsVsTonnagePoints,
      r2Tonnage: r2Tonnage,
      rpeInsight: rpeInsight,
      tonnageInsight: tonnageInsight,
    );
  }

  static double _computeR2(List<CorrelationPoint> points) {
    if (points.length < 3) return 0.0;

    final n = points.length;
    double sumX = 0, sumY = 0, sumXY = 0, sumX2 = 0, sumY2 = 0;

    for (final p in points) {
      sumX += p.x;
      sumY += p.y;
      sumXY += p.x * p.y;
      sumX2 += p.x * p.x;
      sumY2 += p.y * p.y;
    }

    final numerator = (n * sumXY) - (sumX * sumY);
    final denominator = sqrt(
      ((n * sumX2) - (sumX * sumX)) * ((n * sumY2) - (sumY * sumY)),
    );

    if (denominator == 0.0) return 0.0;
    final r = numerator / denominator;
    return (r * r).clamp(0.0, 1.0);
  }

  static String _buildRpeInsight(List<CorrelationPoint> points, double r2) {
    if (points.length < 3) {
      return 'Log at least 3 workouts with step counts to uncover RPE trends.';
    }

    final highStepPoints = points.where((p) => p.x >= 14.0).toList();
    final moderateStepPoints = points.where((p) => p.x < 14.0).toList();

    if (highStepPoints.isNotEmpty && moderateStepPoints.isNotEmpty) {
      final avgRpeHigh =
          highStepPoints.map((p) => p.y).reduce((a, b) => a + b) /
          highStepPoints.length;
      final avgRpeMod =
          moderateStepPoints.map((p) => p.y).reduce((a, b) => a + b) /
          moderateStepPoints.length;

      final diff = avgRpeHigh - avgRpeMod;
      if (diff > 0.4) {
        return 'Workouts on high-step days (>14k) feel ~${diff.toStringAsFixed(1)} RPE harder due to leg fatigue and glycogen drain.';
      } else if (diff < -0.3) {
        return 'Higher daily steps do not hinder your sessions; higher NEAT correlates with better work capacity.';
      }
    }

    if (r2 > 0.3) {
      return 'Moderate correlation detected (R² = ${r2.toStringAsFixed(2)}): daily step volume directly affects your perceived gym exertion.';
    }

    return 'Your perceived exertion remains stable across variable step volumes (R² = ${r2.toStringAsFixed(2)}).';
  }

  static String _buildTonnageInsight(List<CorrelationPoint> points, double r2) {
    if (points.length < 3) {
      return 'Log at least 3 workouts with step counts to analyze tonnage impact.';
    }

    if (r2 > 0.35) {
      return 'Strong relationship (R² = ${r2.toStringAsFixed(2)}): high walking volume noticeably alters your total workout tonnage.';
    }
    return 'Workout tonnage is resilient to daily step variations (R² = ${r2.toStringAsFixed(2)}).';
  }

  static String _formatDateIso(DateTime dt) {
    final y = dt.year.toString().padLeft(4, '0');
    final m = dt.month.toString().padLeft(2, '0');
    final d = dt.day.toString().padLeft(2, '0');
    return '$y-$m-$d';
  }
}
