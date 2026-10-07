import 'package:flutter_test/flutter_test.dart';
import 'package:herculex/features/nutrition/domain/diet_phase.dart';
import 'package:herculex/features/physique/domain/roadmap_exit_criteria.dart';

PhaseProgress _p(
  DietPhase phase, {
  int weeks = 8,
  double? w,
  double? bf,
  DateTime? start,
}) => PhaseProgress(
  phase: phase,
  plannedWeeks: weeks,
  startedAt: start ?? DateTime(2026, 9, 1),
  targetWeightKg: w,
  targetBfPercent: bf,
);

ExitCriterionStatus? _c(ExitEvaluation e, ExitCriterionKind k) {
  for (final c in e.criteria) {
    if (c.kind == k) return c;
  }
  return null;
}

void main() {
  final now = DateTime(2026, 9, 10);

  test('cut weight criterion', () {
    final met = RoadmapExitEvaluator.evaluate(
      phase: _p(DietPhase.cut, w: 73),
      now: now,
      latestWeightKg: 72.9,
    );
    expect(_c(met, ExitCriterionKind.weight)!.met, isTrue);
    expect(met.targetReached, isTrue);
    final notMet = RoadmapExitEvaluator.evaluate(
      phase: _p(DietPhase.cut, w: 73),
      now: now,
      latestWeightKg: 73.1,
    );
    expect(_c(notMet, ExitCriterionKind.weight)!.met, isFalse);
    expect(notMet.targetReached, isFalse);
  });

  test('bulk and maingain met at or above target', () {
    for (final ph in [DietPhase.bulk, DietPhase.maingain]) {
      final e = RoadmapExitEvaluator.evaluate(
        phase: _p(ph, w: 80),
        now: now,
        latestWeightKg: 80,
      );
      expect(_c(e, ExitCriterionKind.weight)!.met, isTrue);
    }
  });

  test('recomp and maintain have no weight criterion', () {
    for (final ph in [DietPhase.recomp, DietPhase.maintain]) {
      final e = RoadmapExitEvaluator.evaluate(
        phase: _p(ph, w: 80),
        now: now,
        latestWeightKg: 80,
      );
      expect(_c(e, ExitCriterionKind.weight), isNull);
    }
  });

  test(
    'body fat criterion only for cut and recomp, needs reliable estimate',
    () {
      final ok = RoadmapExitEvaluator.evaluate(
        phase: _p(DietPhase.recomp, bf: 15),
        now: now,
        latestBfPercent: 14.5,
      );
      expect(_c(ok, ExitCriterionKind.bodyFat)!.met, isTrue);
      final unreliable = RoadmapExitEvaluator.evaluate(
        phase: _p(DietPhase.cut, bf: 15),
        now: now,
        latestBfPercent: 12,
        bfEstimateReliable: false,
      );
      expect(_c(unreliable, ExitCriterionKind.bodyFat)!.met, isFalse);
      final bulk = RoadmapExitEvaluator.evaluate(
        phase: _p(DietPhase.bulk, bf: 15),
        now: now,
        latestBfPercent: 12,
      );
      expect(_c(bulk, ExitCriterionKind.bodyFat), isNull);
    },
  );

  test('duration and weekInPhase', () {
    final start = DateTime(2026, 9, 1);
    final e0 = RoadmapExitEvaluator.evaluate(
      phase: _p(DietPhase.cut, weeks: 2, start: start),
      now: DateTime(2026, 9, 14, 23),
    );
    expect(e0.weekInPhase, 2);
    expect(e0.durationElapsed, isFalse);
    final e1 = RoadmapExitEvaluator.evaluate(
      phase: _p(DietPhase.cut, weeks: 2, start: start),
      now: DateTime(2026, 9, 15),
    );
    expect(e1.durationElapsed, isTrue);
    expect(e1.criteriaMet, isTrue);
    expect(e1.targetReached, isFalse);
    final before = RoadmapExitEvaluator.evaluate(
      phase: _p(DietPhase.cut, start: start),
      now: DateTime(2026, 8, 20),
    );
    expect(before.weekInPhase, 1);
  });

  test('shouldOfferAdvance', () {
    final due = RoadmapExitEvaluator.evaluate(
      phase: _p(DietPhase.cut, weeks: 1),
      now: DateTime(2026, 9, 20),
    );
    bool offer({bool next = true, DateTime? snooze, DateTime? at}) =>
        RoadmapExitEvaluator.shouldOfferAdvance(
          evaluation: due,
          hasNextPhase: next,
          now: at ?? DateTime(2026, 9, 20),
          snoozedUntil: snooze,
        );
    expect(offer(), isTrue);
    expect(offer(next: false), isFalse);
    expect(offer(snooze: DateTime(2026, 9, 27)), isFalse);
    expect(
      offer(snooze: DateTime(2026, 9, 27, 18), at: DateTime(2026, 9, 27, 1)),
      isTrue,
    );
    final notDue = RoadmapExitEvaluator.evaluate(
      phase: _p(DietPhase.cut, weeks: 8),
      now: DateTime(2026, 9, 5),
    );
    expect(
      RoadmapExitEvaluator.shouldOfferAdvance(
        evaluation: notDue,
        hasNextPhase: true,
        now: DateTime(2026, 9, 5),
      ),
      isFalse,
    );
  });
}
