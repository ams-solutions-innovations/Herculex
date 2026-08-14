import 'dart:math';

import '../../../data/local/database.dart';
import 'training_snapshot.dart';

class CorrelationPoint {
  final double x;
  final double y;

  const CorrelationPoint(this.x, this.y);
}

class BiometricCorrelationResult {
  final List<CorrelationPoint> points;
  final double r2; // R² coefficient of determination
  final int sampleSize;

  const BiometricCorrelationResult({
    required this.points,
    required this.r2,
    required this.sampleSize,
  });

  String get interpretation {
    if (sampleSize < 3) return "Insufficient sessions recorded yet.";
    if (r2 > 0.6) return "Strong correlation detected. Priority recovery shifts targets positively.";
    if (r2 > 0.3) return "Moderate correlation detected.";
    return "Weak or neutral correlation.";
  }
}

class BiometricCorrelations {
  static BiometricCorrelationResult sleepVsRpe({
    required List<HealthSampleData> healthSamples,
    required List<ResolvedSet> resolvedSets,
  }) {
    final Map<String, double> sleepByDate = {};
    for (final s in healthSamples) {
      if (s.kind == 'sleep_hours') {
        sleepByDate[s.dateIso] = s.value;
      }
    }

    final sessions = <int, WorkoutSessionData>{
      for (final r in resolvedSets) r.session.id: r.session,
    };

    final points = <CorrelationPoint>[];

    // Compute average session RPE and join by date
    for (final session in sessions.values) {
      final sessionDateStr = _formatDateIso(session.startedAt);
      final sleepHrs = sleepByDate[sessionDateStr];
      if (sleepHrs == null) continue;

      // Find average RPE for this session
      final sessionSets =
          resolvedSets.where((r) => r.session.id == session.id).toList();
      if (sessionSets.isEmpty) continue;

      double sumRpe = 0;
      int rpeCount = 0;
      for (final s in sessionSets) {
        if (s.set.rpeX10 != null) {
          sumRpe += s.set.rpeX10! / 10.0;
          rpeCount++;
        }
      }

      if (rpeCount > 0) {
        final avgRpe = sumRpe / rpeCount;
        points.add(CorrelationPoint(sleepHrs, avgRpe));
      }
    }

    final r2 = _calculateR2(points);

    return BiometricCorrelationResult(
      points: points,
      r2: r2,
      sampleSize: points.length,
    );
  }

  static BiometricCorrelationResult restingHrVsTonnage({
    required List<HealthSampleData> healthSamples,
    required List<ResolvedSet> resolvedSets,
  }) {
    final Map<String, double> hrByDate = {};
    for (final s in healthSamples) {
      if (s.kind == 'resting_hr') {
        hrByDate[s.dateIso] = s.value;
      }
    }

    final sessions = <int, WorkoutSessionData>{
      for (final r in resolvedSets) r.session.id: r.session,
    };

    final points = <CorrelationPoint>[];

    for (final session in sessions.values) {
      final sessionDateStr = _formatDateIso(session.startedAt);
      final rHr = hrByDate[sessionDateStr];
      if (rHr == null) continue;

      final sessionSets =
          resolvedSets.where((r) => r.session.id == session.id).toList();
      if (sessionSets.isEmpty) continue;

      double sessionTonnage = 0.0;
      for (final r in sessionSets) {
        sessionTonnage += r.tonnageKg;
      }

      if (sessionTonnage > 0) {
        points.add(CorrelationPoint(rHr, sessionTonnage));
      }
    }

    final r2 = _calculateR2(points);

    return BiometricCorrelationResult(
      points: points,
      r2: r2,
      sampleSize: points.length,
    );
  }

  static double _calculateR2(List<CorrelationPoint> points) {
    final n = points.length;
    double sumX = 0;
    double sumY = 0;
    double sumXY = 0;
    double sumX2 = 0;
    double sumY2 = 0;

    for (final p in points) {
      sumX += p.x;
      sumY += p.y;
      sumXY += p.x * p.y;
      sumX2 += p.x * p.x;
      sumY2 += p.y * p.y;
    }

    final num = n * sumXY - sumX * sumY;
    final den = sqrt((n * sumX2 - sumX * sumX) * (n * sumY2 - sumY * sumY));
    if (den == 0) return 0.0;

    final r = num / den;
    return r * r; // Coefficient of determination R²
  }

  static String _formatDateIso(DateTime dt) {
    return "${dt.year}-${dt.month.toString().padLeft(2, '0')}-${dt.day.toString().padLeft(2, '0')}";
  }
}
