import 'package:health/health.dart';

import '../../analytics/domain/muscle_recovery_v3.dart';
import '../../analytics/domain/muscle_volume_trend.dart';
import '../../analytics/domain/training_snapshot.dart';
import 'deload_urgency.dart';
import 'joint_model.dart';

class JointStressResult {
  final String joint;
  final bool isFlagged;
  final DateTime? flaggedSince;

  /// Up to 3 of [JointModel.influencingMuscles] for this joint, sorted by
  /// weighted load — the "why" behind [explanation].
  final List<String> topContributingMuscles;

  /// Weighted average of (average weekly sets ÷ MRV) across the joint's
  /// influencing muscles, plus a cardio bump for joints with a
  /// [JointModel.cardioActivitiesByJoint] entry. Around 1.0 means the
  /// surrounding muscles have, on average, been trained at their
  /// recoverable ceiling.
  final double relativeLoadIndex;
  final bool cardioContributed;
  final double cardioDistanceKm;
  final DeloadUrgency urgency;
  final String explanation;

  const JointStressResult({
    required this.joint,
    required this.isFlagged,
    required this.flaggedSince,
    required this.topContributingMuscles,
    required this.relativeLoadIndex,
    required this.cardioContributed,
    required this.cardioDistanceKm,
    required this.urgency,
    required this.explanation,
  });
}

/// Cross-references a user-flagged joint against the last two months of
/// training load in the muscles that mechanically influence it (plus, for
/// the knee, running/walking/hiking volume from health data). Deliberately
/// reactive: an unflagged joint never surfaces a warning, however loaded its
/// muscles are — this is "I flagged my elbow, is it overtraining?", not a
/// proactive alarm on joints the user hasn't said anything about.
abstract final class JointStressAdvisor {
  static const _lookbackDays = 56; // 8 weeks ≈ "the last month or two"
  static const _watchThreshold = 0.8;
  static const _recommendedThreshold = 1.0;
  static const _maxCardioBump = 0.3;
  static const _cardioKmPerWeekForFullBump = 25.0;

  static JointStressResult evaluate({
    required String joint,
    required DateTime? flaggedSince,
    required TrainingSnapshot snapshot,
    required List<HealthDataPoint> wideExternalWorkouts,
    required DateTime asOf,
  }) {
    final weights = JointModel.influencingMuscles[joint] ?? const {};
    final trends = MuscleVolumeTrends.compute(
      snapshot: snapshot,
      asOf: asOf,
      weekCount: (_lookbackDays / 7).ceil(),
    );

    var weightedSum = 0.0;
    var weightSum = 0.0;
    final contributions = <(String, double)>[];
    for (final entry in weights.entries) {
      final trend = trends[entry.key];
      if (trend == null) continue;
      final mrv = MuscleRecoveryV3.defaultWeeklyMrv[entry.key] ?? double.infinity;
      final ratio = mrv.isFinite && mrv > 0 ? trend.averageWeeklySets / mrv : 0.0;
      weightedSum += ratio * entry.value;
      weightSum += entry.value;
      contributions.add((entry.key, ratio * entry.value));
    }
    final baseIndex = weightSum > 0 ? weightedSum / weightSum : 0.0;
    contributions.sort((a, b) => b.$2.compareTo(a.$2));
    final topMuscles = contributions.take(3).map((c) => c.$1).toList();

    final cardio = _cardioLoad(joint, wideExternalWorkouts, asOf);
    final avgWeeklyKm = (cardio.meters / 1000.0) / (_lookbackDays / 7.0);
    final cardioBump =
        (avgWeeklyKm / _cardioKmPerWeekForFullBump * _maxCardioBump).clamp(0.0, _maxCardioBump);
    final index = baseIndex + cardioBump;

    final isFlagged = flaggedSince != null;
    final urgency = !isFlagged
        ? DeloadUrgency.none
        : index >= _recommendedThreshold
            ? DeloadUrgency.recommended
            : index >= _watchThreshold
                ? DeloadUrgency.watch
                : DeloadUrgency.none;

    return JointStressResult(
      joint: joint,
      isFlagged: isFlagged,
      flaggedSince: flaggedSince,
      topContributingMuscles: topMuscles,
      relativeLoadIndex: index,
      cardioContributed: cardio.sessions > 0,
      cardioDistanceKm: cardio.meters / 1000.0,
      urgency: urgency,
      explanation: _explain(joint, topMuscles, cardio.sessions > 0, avgWeeklyKm, urgency),
    );
  }

  static ({double meters, int sessions}) _cardioLoad(
    String joint,
    List<HealthDataPoint> wideExternalWorkouts,
    DateTime asOf,
  ) {
    final activities = JointModel.cardioActivitiesByJoint[joint];
    if (activities == null || activities.isEmpty) return (meters: 0.0, sessions: 0);

    final cutoff = asOf.subtract(const Duration(days: _lookbackDays));
    var meters = 0.0;
    var sessions = 0;
    for (final point in wideExternalWorkouts) {
      if (point.value is! WorkoutHealthValue) continue;
      final workout = point.value as WorkoutHealthValue;
      if (!activities.contains(workout.workoutActivityType)) continue;
      if (point.dateFrom.isBefore(cutoff)) continue;

      sessions++;
      final distance = workout.totalDistance;
      if (distance != null) meters += distance.toDouble();
    }
    return (meters: meters, sessions: sessions);
  }

  static String _explain(
    String joint,
    List<String> topMuscles,
    bool cardioContributed,
    double avgWeeklyKm,
    DeloadUrgency urgency,
  ) {
    if (urgency == DeloadUrgency.none) {
      return 'Recent training load around the $joint looks manageable.';
    }
    final muscleList = topMuscles.isEmpty ? 'the muscles around it' : topMuscles.join(', ');
    final cardioNote = cardioContributed
        ? ', plus ~${avgWeeklyKm.toStringAsFixed(1)} km/week of running or walking'
        : '';
    final lead = urgency == DeloadUrgency.recommended
        ? 'A deload is recommended for the $joint'
        : 'Worth watching the $joint';
    return '$lead — $muscleList volume has been elevated over the last several weeks$cardioNote.';
  }
}
