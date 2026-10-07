import 'package:herculex/features/nutrition/domain/diet_phase.dart';
import 'package:herculex/features/nutrition/domain/tdee_trend.dart';

enum ExitCriterionKind { weight, bodyFat, duration }

/// The active phase as stored, reduced to what exit evaluation needs.
class PhaseProgress {
  const PhaseProgress({
    required this.phase,
    required this.plannedWeeks,
    required this.startedAt,
    this.targetWeightKg,
    this.targetBfPercent,
  });

  final DietPhase phase;
  final int plannedWeeks;
  final DateTime startedAt;
  final double? targetWeightKg;
  final double? targetBfPercent;
}

class ExitCriterionStatus {
  const ExitCriterionStatus({
    required this.kind,
    required this.met,
    this.target,
  });

  final ExitCriterionKind kind;
  final bool met;
  final double? target;
}

class ExitEvaluation {
  const ExitEvaluation({
    required this.criteria,
    required this.weekInPhase,
    required this.plannedWeeks,
    required this.targetReached,
    required this.durationElapsed,
  });

  final List<ExitCriterionStatus> criteria;
  final int weekInPhase;
  final int plannedWeeks;
  final bool targetReached;
  final bool durationElapsed;

  bool get criteriaMet => targetReached || durationElapsed;
}

/// Reports whether a roadmap phase has reached its exit criteria (D-02).
/// Report only: nothing here derives or writes daily targets.
abstract final class RoadmapExitEvaluator {
  static ExitEvaluation evaluate({
    required PhaseProgress phase,
    required DateTime now,
    double? latestWeightKg,
    double? latestBfPercent,
    bool bfEstimateReliable = true,
  }) {
    final elapsedDays = _elapsedDays(phase.startedAt, now);
    final weekInPhase = 1 + elapsedDays ~/ 7;
    final criteria = <ExitCriterionStatus>[];

    final targetWeight = phase.targetWeightKg;
    if (targetWeight != null) {
      final bool? met = switch (phase.phase) {
        DietPhase.cut =>
          latestWeightKg == null ? false : latestWeightKg <= targetWeight,
        DietPhase.bulk || DietPhase.maingain =>
          latestWeightKg == null ? false : latestWeightKg >= targetWeight,
        DietPhase.recomp || DietPhase.maintain => null,
      };
      if (met != null) {
        criteria.add(
          ExitCriterionStatus(
            kind: ExitCriterionKind.weight,
            met: met,
            target: targetWeight,
          ),
        );
      }
    }

    final targetBf = phase.targetBfPercent;
    if (targetBf != null &&
        (phase.phase == DietPhase.cut || phase.phase == DietPhase.recomp)) {
      criteria.add(
        ExitCriterionStatus(
          kind: ExitCriterionKind.bodyFat,
          met:
              bfEstimateReliable &&
              latestBfPercent != null &&
              latestBfPercent <= targetBf,
          target: targetBf,
        ),
      );
    }

    final durationElapsed = elapsedDays ~/ 7 >= phase.plannedWeeks;
    criteria.add(
      ExitCriterionStatus(
        kind: ExitCriterionKind.duration,
        met: durationElapsed,
        target: phase.plannedWeeks.toDouble(),
      ),
    );

    final targetReached = criteria.any(
      (c) => c.kind != ExitCriterionKind.duration && c.met,
    );
    return ExitEvaluation(
      criteria: List.unmodifiable(criteria),
      weekInPhase: weekInPhase,
      plannedWeeks: phase.plannedWeeks,
      targetReached: targetReached,
      durationElapsed: durationElapsed,
    );
  }

  static bool shouldOfferAdvance({
    required ExitEvaluation evaluation,
    required bool hasNextPhase,
    required DateTime now,
    DateTime? snoozedUntil,
  }) {
    if (!evaluation.criteriaMet || !hasNextPhase) return false;
    if (snoozedUntil == null) return true;
    return TrendSeries.dayNumber(now) >= TrendSeries.dayNumber(snoozedUntil);
  }

  static int _elapsedDays(DateTime start, DateTime now) {
    final d = TrendSeries.dayNumber(now) - TrendSeries.dayNumber(start);
    return d < 0 ? 0 : d;
  }
}
