import 'package:flutter_test/flutter_test.dart';
import 'package:herculex/features/nutrition/domain/diet_phase.dart';
import 'package:herculex/features/physique/domain/physique_direction.dart';
import 'package:herculex/features/physique/domain/physique_tempo_policy.dart';

void main() {
  group('presetWeeklyKg', () {
    test('matches DietPhaseCalculator presets', () {
      expect(
        PhysiqueTempoPolicy.presetWeeklyKg(
          phase: DietPhase.cut,
          maintenanceKcal: 3000,
        ),
        closeTo(0.6, 1e-9),
      );
      expect(
        PhysiqueTempoPolicy.presetWeeklyKg(
          phase: DietPhase.bulk,
          maintenanceKcal: 2500,
        ),
        closeTo(0.25, 1e-9),
      );
      expect(
        PhysiqueTempoPolicy.presetWeeklyKg(
          phase: DietPhase.maingain,
          maintenanceKcal: 1234,
        ),
        closeTo(0.15, 1e-9),
      );
      for (final p in [DietPhase.maintain, DietPhase.recomp]) {
        expect(
          PhysiqueTempoPolicy.presetWeeklyKg(phase: p, maintenanceKcal: 2500),
          0.0,
        );
      }
    });
  });

  group('weeklyKg / isCapped', () {
    double kg(DietPhase p, double bw, int m, {int? cap}) =>
        PhysiqueTempoPolicy.weeklyKg(
          phase: p,
          bodyweightKg: bw,
          maintenanceKcal: m,
          maxDeltaKcalCap: cap,
        );
    bool capped(DietPhase p, double bw, int m, {int? cap}) =>
        PhysiqueTempoPolicy.isCapped(
          phase: p,
          bodyweightKg: bw,
          maintenanceKcal: m,
          maxDeltaKcalCap: cap,
        );

    test('cut', () {
      expect(kg(DietPhase.cut, 45, 3000), closeTo(0.45, 1e-9));
      expect(capped(DietPhase.cut, 45, 3000), isTrue);
      expect(kg(DietPhase.cut, 80, 2500), closeTo(0.5, 1e-9));
      expect(capped(DietPhase.cut, 80, 2500), isFalse);
    });

    test('bulk and maingain', () {
      expect(kg(DietPhase.bulk, 40, 2500), closeTo(0.2, 1e-9));
      expect(capped(DietPhase.bulk, 40, 2500), isTrue);
      expect(kg(DietPhase.maingain, 80, 2500), closeTo(0.12, 1e-9));
      expect(capped(DietPhase.maingain, 80, 2500), isTrue);
      expect(kg(DietPhase.maingain, 100, 2500), closeTo(0.15, 1e-9));
      expect(capped(DietPhase.maingain, 100, 2500), isFalse);
    });

    test('kcal cap lowers the pace', () {
      expect(kg(DietPhase.maingain, 100, 2500, cap: 75), closeTo(0.075, 1e-9));
      expect(capped(DietPhase.maingain, 100, 2500, cap: 75), isTrue);
    });

    test('maintain and recomp are zero and never capped', () {
      for (final p in [DietPhase.maintain, DietPhase.recomp]) {
        expect(kg(p, 80, 2500), 0.0);
        expect(capped(p, 80, 2500), isFalse);
      }
    });
  });

  test('plannedWeeks', () {
    expect(PhysiqueTempoPolicy.plannedWeeks(deltaKg: 6, weeklyKg: 0.5), 12);
    expect(PhysiqueTempoPolicy.plannedWeeks(deltaKg: 6.1, weeklyKg: 0.5), 13);
    expect(PhysiqueTempoPolicy.plannedWeeks(deltaKg: 6, weeklyKg: 0), 0);
  });

  group('PhysiqueDirectionRule.decide', () {
    PhysiqueDirectionDecision? decide({
      double weight = 80,
      required double current,
      required double target,
      required double change,
      bool loss = false,
    }) => PhysiqueDirectionRule.decide(
      weightKg: weight,
      currentBfPercent: current,
      targetBfPercent: target,
      plannedWeightChangeKg: change,
      prefersWeightLoss: loss,
    );

    test('one input per branch', () {
      expect(decide(current: 22, target: 14, change: -7)?.phase, DietPhase.cut);
      expect(
        decide(current: 16, target: 14, change: -1, loss: true)?.phase,
        DietPhase.cut,
      );
      expect(decide(current: 13, target: 14, change: 7)?.phase, DietPhase.bulk);
      expect(
        decide(current: 17, target: 14, change: -2)?.phase,
        DietPhase.recomp,
      );
      expect(
        decide(current: 13, target: 14, change: 4)?.phase,
        DietPhase.maingain,
      );
      expect(
        decide(current: 22, target: 14, change: -7)?.reasons,
        hasLength(2),
      );
    });

    test('null on unusable data', () {
      expect(decide(weight: 0, current: 20, target: 14, change: 0), isNull);
      expect(decide(current: 0, target: 14, change: 0), isNull);
      expect(decide(current: 70, target: 14, change: 0), isNull);
      expect(decide(current: 20, target: 0, change: 0), isNull);
      expect(decide(current: 20, target: 70, change: 0), isNull);
    });
  });
}
