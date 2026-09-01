import 'dart:math';

import '../../workouts/domain/set_type.dart';
import 'cns_trends.dart';
import 'training_snapshot.dart';

/// Detail of an individual set's contribution to CNS fatigue.
class SetCnsImpact {
  final int exerciseId;
  final String exerciseName;
  final String targetMuscle;
  final int baseCnsScore;
  final int effectiveCnsScore;
  final bool hasWeightedBonus;
  final SetType setType;
  final double rpe;
  final double rpeFactor;
  final double setFactor;
  final double setLoad;
  final double residualFatigue;
  final DateTime? completedAt;

  const SetCnsImpact({
    required this.exerciseId,
    required this.exerciseName,
    required this.targetMuscle,
    required this.baseCnsScore,
    required this.effectiveCnsScore,
    required this.hasWeightedBonus,
    required this.setType,
    required this.rpe,
    required this.rpeFactor,
    required this.setFactor,
    required this.setLoad,
    required this.residualFatigue,
    this.completedAt,
  });
}

/// A workout session's aggregate impact on the central nervous system.
class SessionCnsImpact {
  final int sessionId;
  final String workoutName;
  final DateTime sessionDate;
  final double totalLoad;
  final double currentResidualFatigue;
  final int setCount;
  final double avgRpe;
  final List<SetCnsImpact> sets;

  const SessionCnsImpact({
    required this.sessionId,
    required this.workoutName,
    required this.sessionDate,
    required this.totalLoad,
    required this.currentResidualFatigue,
    required this.setCount,
    required this.avgRpe,
    required this.sets,
  });

  bool get hasActiveResidualFatigue => currentResidualFatigue > 0.005;
}

/// Aggregate CNS demand for a specific exercise across the evaluated window.
class ExerciseCnsImpact {
  final int exerciseId;
  final String exerciseName;
  final String targetMuscle;
  final int cnsScore;
  final int totalSets;
  final double totalLoadContribution;
  final double avgRpe;
  final bool isWeightedBodyweight;

  const ExerciseCnsImpact({
    required this.exerciseId,
    required this.exerciseName,
    required this.targetMuscle,
    required this.cnsScore,
    required this.totalSets,
    required this.totalLoadContribution,
    required this.avgRpe,
    required this.isWeightedBodyweight,
  });
}

/// Comprehensive CNS analytics result containing trends, session breakdown,
/// exercise ranking, ACWR, and recovery predictions.
class CnsDetailedResult {
  final CnsTrendsResult trends;
  final double acuteWeeklyLoad;
  final double chronicWeeklyLoad;
  final double acwr;
  final double? hoursToFullRecovery;
  final List<SessionCnsImpact> recentSessions;
  final List<ExerciseCnsImpact> topCnsExercises;

  const CnsDetailedResult({
    required this.trends,
    required this.acuteWeeklyLoad,
    required this.chronicWeeklyLoad,
    required this.acwr,
    required this.hoursToFullRecovery,
    required this.recentSessions,
    required this.topCnsExercises,
  });

  double get readiness => trends.readiness;
  double get currentLoad => trends.currentLoad;
  String get status => trends.status;
  bool get deloadSuggested => trends.deloadSuggested;
  String? get recommendation => trends.recommendation;

  /// Human-friendly readiness guidance for the athlete today.
  String get trainingGuidance {
    if (deloadSuggested) {
      return 'Acute load exceeds your 4-week adaptation capacity (${acwr.toStringAsFixed(1)}× ratio). A deload week or low-intensity session is strongly advised.';
    }
    if (currentLoad >= 0.7) {
      return 'CNS fatigue is elevated. Focus on recovery, mobility, or submaximal technique work (RPE ≤ 7). Avoid 1RM testing and forced reps.';
    }
    if (currentLoad >= 0.4) {
      return 'Moderate neurological fatigue. Standard training volume is appropriate, but pace intensity and prioritize rest between heavy sets.';
    }
    return 'CNS is fully primed and refreshed. Optimal state for heavy compound lifts, PR attempts, and high-velocity power movements.';
  }
}

/// Engine to compute detailed CNS breakdown from a [TrainingSnapshot].
class CnsBreakdownEngine {
  static const _perSetBase = 0.08;
  static const _gaugeWindowHours = 96;
  static const _gaugeHalfLifeHours = 36.0;

  static CnsDetailedResult compute({
    required TrainingSnapshot snapshot,
    required DateTime asOf,
    int days = 28,
  }) {
    // 1. Compute baseline trends
    final trends = CnsTrends.compute(
      snapshot: snapshot,
      asOf: asOf,
      days: days,
    );

    // 2. Group sets by session and by exercise
    final sessionSetsMap = <int, List<ResolvedSet>>{};
    final exerciseSetsMap = <int, List<ResolvedSet>>{};

    for (final rs in snapshot.sets) {
      sessionSetsMap.putIfAbsent(rs.session.id, () => []).add(rs);
      exerciseSetsMap.putIfAbsent(rs.exercise.id, () => []).add(rs);
    }

    // 3. Process sessions
    final sessionImpacts = <SessionCnsImpact>[];

    for (final entry in sessionSetsMap.entries) {
      final sets = entry.value;
      if (sets.isEmpty) continue;

      final session = sets.first.session;
      final sessionDate = session.startedAt;
      var sessionTotalLoad = 0.0;
      var sessionResidualFatigue = 0.0;
      var totalRpe = 0.0;
      var rpeCount = 0;

      final setDetails = <SetCnsImpact>[];

      for (final rs in sets) {
        final completedAt = rs.set.completedAt ?? sessionDate;
        final intensity = rs.cnsScore / 10.0;
        final rpe = rs.set.rpeX10 != null ? rs.set.rpeX10! / 10.0 : 7.0;
        if (rs.set.rpeX10 != null) {
          totalRpe += rpe;
          rpeCount++;
        }

        final rpeFactor = rpe >= 9
            ? 1.5
            : rpe >= 8
            ? 1.3
            : 1.0;
        final setFactor = rs.setType.cnsFactor;
        final setLoad = intensity * rpeFactor * setFactor;

        sessionTotalLoad += setLoad;

        final hours = asOf.difference(completedAt).inHours;
        var residual = 0.0;
        if (hours >= 0 && hours <= _gaugeWindowHours) {
          residual =
              _perSetBase * setLoad * exp(-hours * ln2 / _gaugeHalfLifeHours);
          sessionResidualFatigue += residual;
        }

        setDetails.add(
          SetCnsImpact(
            exerciseId: rs.exercise.id,
            exerciseName: rs.exercise.name,
            targetMuscle: rs.exercise.primaryMuscle,
            baseCnsScore: rs.exercise.cnsScore,
            effectiveCnsScore: rs.cnsScore,
            hasWeightedBonus: rs.cnsScore > rs.exercise.cnsScore,
            setType: rs.setType,
            rpe: rpe,
            rpeFactor: rpeFactor,
            setFactor: setFactor,
            setLoad: setLoad,
            residualFatigue: residual,
            completedAt: rs.set.completedAt,
          ),
        );
      }

      final avgRpe = rpeCount > 0 ? totalRpe / rpeCount : 7.0;

      sessionImpacts.add(
        SessionCnsImpact(
          sessionId: session.id,
          workoutName: session.name ?? 'Workout Session',
          sessionDate: sessionDate,
          totalLoad: sessionTotalLoad,
          currentResidualFatigue: sessionResidualFatigue,
          setCount: sets.length,
          avgRpe: avgRpe,
          sets: setDetails,
        ),
      );
    }

    // Sort sessions most recent first
    sessionImpacts.sort((a, b) => b.sessionDate.compareTo(a.sessionDate));

    // 4. Process exercises (ranking by total CNS load impact)
    final exerciseImpacts = <ExerciseCnsImpact>[];

    for (final entry in exerciseSetsMap.entries) {
      final sets = entry.value;
      if (sets.isEmpty) continue;

      final firstEx = sets.first.exercise;
      var totalLoad = 0.0;
      var totalRpe = 0.0;
      var rpeCount = 0;

      for (final rs in sets) {
        final intensity = rs.cnsScore / 10.0;
        final rpe = rs.set.rpeX10 != null ? rs.set.rpeX10! / 10.0 : 7.0;
        if (rs.set.rpeX10 != null) {
          totalRpe += rpe;
          rpeCount++;
        }
        final rpeFactor = rpe >= 9
            ? 1.5
            : rpe >= 8
            ? 1.3
            : 1.0;
        final setLoad = intensity * rpeFactor * rs.setType.cnsFactor;
        totalLoad += setLoad;
      }

      final avgRpe = rpeCount > 0 ? totalRpe / rpeCount : 7.0;

      exerciseImpacts.add(
        ExerciseCnsImpact(
          exerciseId: firstEx.id,
          exerciseName: firstEx.name,
          targetMuscle: firstEx.primaryMuscle,
          cnsScore: firstEx.cnsScore,
          totalSets: sets.length,
          totalLoadContribution: totalLoad,
          avgRpe: avgRpe,
          isWeightedBodyweight: firstEx.supportsWeightedBodyweight,
        ),
      );
    }

    // Sort exercises by highest total CNS load
    exerciseImpacts.sort(
      (a, b) => b.totalLoadContribution.compareTo(a.totalLoadContribution),
    );

    // 5. ACWR (Acute / Chronic Workload Ratio)
    final acute = trends.acuteWeeklyLoad;
    final chronic = trends.chronicWeeklyLoad;
    final acwr = chronic > 0 ? acute / chronic : (acute > 0 ? 1.0 : 0.0);

    // 6. Recovery ETA estimation (hours to reach <= 5% fatigue / 95% readiness)
    double? etaHours;
    if (trends.currentLoad > 0.05) {
      final hours =
          _gaugeHalfLifeHours * (log(trends.currentLoad / 0.05) / ln2);
      etaHours = hours.clamp(0.0, _gaugeWindowHours.toDouble());
    } else {
      etaHours = 0.0;
    }

    return CnsDetailedResult(
      trends: trends,
      acuteWeeklyLoad: acute,
      chronicWeeklyLoad: chronic,
      acwr: acwr,
      hoursToFullRecovery: etaHours,
      recentSessions: sessionImpacts,
      topCnsExercises: exerciseImpacts,
    );
  }
}
