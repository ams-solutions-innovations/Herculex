import 'package:flutter_test/flutter_test.dart';
import 'package:herculex/features/nutrition/domain/diet_phase.dart';
import 'package:herculex/features/nutrition/domain/phase_eligibility.dart';
import 'package:herculex/features/nutrition/domain/target_resolver.dart';
import 'package:herculex/features/nutrition/domain/tdee_estimate.dart';
import 'package:herculex/features/weekly_report/domain/tdee_shift_calculator.dart';
import 'package:herculex/features/weekly_report/domain/tdee_target_proposal.dart';

TdeeEstimateResult _est(
  int kcal, {
  TdeeMethod method = TdeeMethod.observed,
  TdeeConfidence confidence = TdeeConfidence.medium,
}) => TdeeEstimateResult(
  kcal: kcal,
  method: method,
  confidence: confidence,
  windowDays: 28,
  observedQualified: true,
  inputs: const {},
  estimatedAt: DateTime(2026, 10, 1),
);

void main() {
  group('TdeeShiftCalculator materiality', () {
    test('delta of exactly 100 at 2500 is not material (5% is 125)', () {
      final s = TdeeShiftCalculator.compute(
        newest: _est(2600),
        before: _est(2500),
      )!;
      expect(s.material, isFalse);
      expect(s.deltaKcal, 100);
    });

    test('2500 -> 2640 is material and carries the section fields', () {
      final s = TdeeShiftCalculator.compute(
        newest: _est(2640, confidence: TdeeConfidence.high),
        before: _est(2500),
      )!;
      expect(s.oldKcal, 2500);
      expect(s.newKcal, 2640);
      expect(s.deltaKcal, 140);
      expect(s.material, isTrue);
      expect(s.confidence, 'high');
    });

    test('1500 -> 1610 is material (floor 100, 5% is 75)', () {
      final s = TdeeShiftCalculator.compute(
        newest: _est(1610),
        before: _est(1500),
      )!;
      expect(s.material, isTrue);
      expect(s.deltaKcal, 110);
    });

    test('1500 -> 1600 is not material: the boundary is strict', () {
      final s = TdeeShiftCalculator.compute(
        newest: _est(1600),
        before: _est(1500),
      )!;
      expect(s.material, isFalse);
      expect(s.deltaKcal, 100);
    });

    test('a downward shift is signed and judged by magnitude', () {
      final s = TdeeShiftCalculator.compute(
        newest: _est(2360),
        before: _est(2500),
      )!;
      expect(s.deltaKcal, -140);
      expect(s.material, isTrue);
    });

    test('a non-material shift still yields a section', () {
      final s = TdeeShiftCalculator.compute(
        newest: _est(2510),
        before: _est(2500),
      )!;
      expect(s.material, isFalse);
      expect(s.deltaKcal, 10);
    });
  });

  group('TdeeShiftCalculator no section', () {
    test('null without an earlier estimate', () {
      expect(
        TdeeShiftCalculator.compute(newest: _est(2600), before: null),
        isNull,
      );
    });

    test('null without a newest estimate', () {
      expect(
        TdeeShiftCalculator.compute(newest: null, before: _est(2600)),
        isNull,
      );
    });

    test('null when the newest estimate is a cold start', () {
      expect(
        TdeeShiftCalculator.compute(
          newest: _est(3000, method: TdeeMethod.coldStart),
          before: _est(2000),
        ),
        isNull,
      );
    });

    test('a cold-start earlier estimate is still a valid baseline', () {
      final s = TdeeShiftCalculator.compute(
        newest: _est(2700),
        before: _est(2400, method: TdeeMethod.coldStart),
      );
      expect(s, isNotNull);
      expect(s!.material, isTrue);
    });
  });

  group('TdeeTargetProposalCalculator', () {
    const rule = TargetRule(
      kcal: 2400,
      proteinG: 180,
      carbsG: 250,
      fatG: 70,
      fiberG: 30,
      appliesTo: 'global',
    );

    TdeeTargetProposalResult run({
      TargetRule? r = rule,
      int oldKcal = 2500,
      int newKcal = 2640,
      int? floor,
      PhaseEligibility? eligibility,
    }) => TdeeTargetProposalCalculator.compute(
      rule: r,
      oldEstimateKcal: oldKcal,
      newEstimateKcal: newKcal,
      minCaloriesKcal: floor,
      eligibility: eligibility,
    );

    test('preserves the deliberate offset: +140 on 2400 -> 2540', () {
      final res = run();
      expect(res.status, TdeeProposalStatus.proposed);
      final p = res.proposal!;
      expect(p.kcal, 2540);
      expect(p.proteinG, 180);
      expect(p.fatG, 70);
      expect(p.carbsG, 298); // (2540 - 720 - 630) / 4 = 297.5 -> 298
      expect(p.appliesTo, 'global');
    });

    test('carries fiber and scope over from the rule', () {
      final p = run(
        r: const TargetRule(
          kcal: 2400,
          proteinG: 180,
          carbsG: 250,
          fatG: 70,
          fiberG: 30,
          appliesTo: 'training_day',
        ),
      ).proposal!;
      expect(p.fiberG, 30);
      expect(p.appliesTo, 'training_day');
    });

    test('a downward shift lowers the target: -140 -> 2260', () {
      final p = run(newKcal: 2360).proposal!;
      expect(p.kcal, 2260);
      expect(p.carbsG, round4(2260 - 720 - 630));
    });

    test('rounds to the nearest 10, halves up', () {
      expect(run(newKcal: 2643).proposal!.kcal, 2540);
      expect(run(newKcal: 2645).proposal!.kcal, 2550);
    });

    test('the minimum-calories floor wins over a lower proposal', () {
      final p = run(newKcal: 2360, floor: 2300).proposal!;
      expect(p.kcal, 2300);
    });

    test('a proposal clamped onto the current kcal is noChange', () {
      final res = run(
        r: const TargetRule(
          kcal: 2300,
          proteinG: 150,
          carbsG: 250,
          fatG: 70,
          appliesTo: 'global',
        ),
        newKcal: 2360,
        floor: 2300,
      );
      expect(res.status, TdeeProposalStatus.noChange);
      expect(res.proposal, isNull);
    });

    test('restricted eligibility without maingain blocks an increase', () {
      final res = run(
        eligibility: const PhaseEligibility(
          allowedPhases: {DietPhase.maintain},
          reasons: {PhaseRestrictionReason.under18},
        ),
      );
      expect(res.status, TdeeProposalStatus.noChange);
      expect(res.proposal, isNull);
    });

    test('a maingain cap of 100 clamps +140 to +100', () {
      final res = run(
        eligibility: const PhaseEligibility(
          allowedPhases: {DietPhase.maintain, DietPhase.maingain},
          maxMaingainDeltaKcal: 100,
        ),
      );
      expect(res.proposal!.kcal, 2500);
    });

    test('unrestricted and null eligibility never clamp an increase', () {
      expect(
        run(eligibility: const PhaseEligibility.unrestricted()).proposal!.kcal,
        2540,
      );
      expect(run().proposal!.kcal, 2540);
    });

    test('a decrease is never blocked by eligibility', () {
      final res = run(
        newKcal: 2360,
        eligibility: const PhaseEligibility(
          allowedPhases: {DietPhase.maintain},
          maxMaingainDeltaKcal: 0,
        ),
      );
      expect(res.proposal!.kcal, 2260);
    });

    test('a zero shift is noChange', () {
      final res = run(newKcal: 2500);
      expect(res.status, TdeeProposalStatus.noChange);
    });

    test('no room left for carbs is belowMacroFloor', () {
      final res = run(
        r: const TargetRule(
          kcal: 1500,
          proteinG: 200,
          carbsG: 10,
          fatG: 80,
          appliesTo: 'global',
        ),
        newKcal: 2400,
        oldKcal: 2500,
      );
      // 1400 kcal < 200*4 + 80*9 = 1520
      expect(res.status, TdeeProposalStatus.belowMacroFloor);
      expect(res.proposal, isNull);
    });

    test('no saved rule is noSavedRule', () {
      final res = run(r: null);
      expect(res.status, TdeeProposalStatus.noSavedRule);
      expect(res.proposal, isNull);
    });

    test('a target outside the storable decision range is noChange', () {
      final res = run(
        r: const TargetRule(
          kcal: 5950,
          proteinG: 150,
          carbsG: 500,
          fatG: 100,
          appliesTo: 'global',
        ),
        oldKcal: 2500,
        newKcal: 2700,
      );
      expect(res.status, TdeeProposalStatus.noChange);
    });
  });
}

int round4(int kcal) => (kcal / 4).round();
