import 'package:flutter_test/flutter_test.dart';
import 'package:herculex/features/nutrition/domain/diet_phase.dart';
import 'package:herculex/features/nutrition/domain/phase_eligibility.dart';

void main() {
  group('DietPhase', () {
    test('save labels name the phase', () {
      expect(DietPhase.cut.saveLabel, 'Save: Cut');
      expect(DietPhase.bulk.saveLabel, 'Save: Bulk');
      expect(DietPhase.maingain.saveLabel, 'Save: Lean bulk');
      expect(DietPhase.maintain.saveLabel, 'Save target');
      expect(DietPhase.recomp.saveLabel, 'Save: Recomp');
    });
  });

  group('DietPhaseCalculator.apply', () {
    test('maintain leaves calories untouched', () {
      final t = DietPhaseCalculator.apply(
        phase: DietPhase.maintain,
        baselineKcal: 2500,
        bodyweightKg: 80,
      );
      expect(t.kcal, 2500);
      expect(t.deltaKcal, 0);
    });

    test('maingain applies default lean surplus with high protein', () {
      final t = DietPhaseCalculator.apply(
        phase: DietPhase.maingain,
        baselineKcal: 2500,
        bodyweightKg: 80,
      );
      expect(t.kcal, 2650);
      expect(t.deltaKcal, 150);
      expect(t.proteinG, (80 * 2.2).round());
    });

    test('cut removes the default 20% deficit', () {
      final t = DietPhaseCalculator.apply(
        phase: DietPhase.cut,
        baselineKcal: 2500,
        bodyweightKg: 80,
      );
      expect(t.kcal, 2000);
    });

    test('recomp keeps calories at maintenance with high protein', () {
      final t = DietPhaseCalculator.apply(
        phase: DietPhase.recomp,
        baselineKcal: 2500,
        bodyweightKg: 80,
      );
      expect(t.kcal, 2500);
      expect(t.deltaKcal, 0);
      expect(t.proteinG, (80 * 2.2).round());
    });

    test('bulk adds the default 10% surplus', () {
      final t = DietPhaseCalculator.apply(
        phase: DietPhase.bulk,
        baselineKcal: 2500,
        bodyweightKg: 80,
      );
      expect(t.kcal, 2750);
    });

    test('weeklyRateKg sets cut pace from 0.25 to 1.0 kg/week', () {
      final mild = DietPhaseCalculator.apply(
        phase: DietPhase.cut,
        baselineKcal: 2500,
        bodyweightKg: 80,
        weeklyRateKg: 0.25,
      );
      expect(mild.kcal, 2250);

      final agg = DietPhaseCalculator.apply(
        phase: DietPhase.cut,
        baselineKcal: 2500,
        bodyweightKg: 80,
        weeklyRateKg: 1.0,
      );
      expect(agg.kcal, 1500);
    });

    test('weeklyRateKg sets bulk pace from 0.25 to 1.0 kg/week', () {
      final lean = DietPhaseCalculator.apply(
        phase: DietPhase.bulk,
        baselineKcal: 2500,
        bodyweightKg: 80,
        weeklyRateKg: 0.25,
      );
      expect(lean.kcal, 2750);

      final agg = DietPhaseCalculator.apply(
        phase: DietPhase.bulk,
        baselineKcal: 2500,
        bodyweightKg: 80,
        weeklyRateKg: 1.0,
      );
      expect(agg.kcal, 3500);
    });

    test('an override replaces the default shift', () {
      final t = DietPhaseCalculator.apply(
        phase: DietPhase.cut,
        baselineKcal: 2000,
        bodyweightKg: 80,
        pctOverride: 10,
      );
      expect(t.kcal, 1800);
    });

    test('protein is raised in a cut and maingain relative to maintenance', () {
      final cut = DietPhaseCalculator.apply(
        phase: DietPhase.cut,
        baselineKcal: 2500,
        bodyweightKg: 80,
      );
      final maingain = DietPhaseCalculator.apply(
        phase: DietPhase.maingain,
        baselineKcal: 2500,
        bodyweightKg: 80,
      );
      final maintain = DietPhaseCalculator.apply(
        phase: DietPhase.maintain,
        baselineKcal: 2500,
        bodyweightKg: 80,
      );
      expect(cut.proteinG, greaterThan(maintain.proteinG));
      expect(maingain.proteinG, greaterThan(maintain.proteinG));
      expect(cut.proteinG, (80 * 2.2).round());
      expect(maingain.proteinG, (80 * 2.2).round());
    });

    test('macros add back up to the calorie target', () {
      for (final phase in DietPhase.values) {
        final t = DietPhaseCalculator.apply(
          phase: phase,
          baselineKcal: 2600,
          bodyweightKg: 75,
        );
        final sum = t.proteinG * 4 + t.carbsG * 4 + t.fatG * 9;
        // Rounding to whole grams costs a few kcal at most.
        expect(
          (sum - t.kcal).abs(),
          lessThanOrEqualTo(12),
          reason: '$phase macros summed to $sum vs ${t.kcal} kcal',
        );
      }
    });

    test('falls back to a percentage split without a bodyweight', () {
      final t = DietPhaseCalculator.apply(
        phase: DietPhase.cut,
        baselineKcal: 2000,
        bodyweightKg: null,
      );
      // The fallback is a share of the *adjusted* calories (2000 − 20 %).
      expect(t.kcal, 1600);
      expect(t.proteinG, (1600 * 0.30 / 4).round());
      expect(t.carbsG, greaterThanOrEqualTo(0));
    });

    test('a very low target still yields non-negative carbs', () {
      // 130 kg lifter on 800 kcal: protein alone would exceed the budget.
      final t = DietPhaseCalculator.apply(
        phase: DietPhase.cut,
        baselineKcal: 1000,
        bodyweightKg: 130,
      );
      expect(t.carbsG, greaterThanOrEqualTo(0));
      expect(t.fatG, greaterThanOrEqualTo(0));
      expect(t.proteinG, greaterThanOrEqualTo(0));
      expect(t.proteinG * 4, lessThanOrEqualTo(t.kcal));
    });

    test('a zero baseline produces an all-zero target', () {
      final t = DietPhaseCalculator.apply(
        phase: DietPhase.cut,
        baselineKcal: 0,
        bodyweightKg: 80,
      );
      expect(t.kcal, 0);
      expect(t.proteinG, 0);
      expect(t.carbsG, 0);
      expect(t.fatG, 0);
    });

    test('enforces minProteinG floor when specified', () {
      final t = DietPhaseCalculator.apply(
        phase: DietPhase.maintain,
        baselineKcal: 2500,
        bodyweightKg: 80,
        minProteinG: 176,
      );
      expect(t.proteinG, 176);
    });

    test('enforces minCaloriesKcal floor when specified', () {
      final t = DietPhaseCalculator.apply(
        phase: DietPhase.cut,
        baselineKcal: 2500,
        bodyweightKg: 80,
        weeklyRateKg: 1.0,
        minCaloriesKcal: 1750,
      );
      expect(t.kcal, 1750);
    });
  });

  group('DietPhaseCalculator.apply eligibility', () {
    test('a restricted eligibility neutralises a cut delta', () {
      final t = DietPhaseCalculator.apply(
        phase: DietPhase.cut,
        baselineKcal: 2500,
        calorieDeltaOverride: -500,
        eligibility: const PhaseEligibility(
          allowedPhases: {DietPhase.maintain, DietPhase.recomp},
        ),
      );
      expect(t.deltaKcal, 0);
      expect(t.kcal, 2500);
    });

    test('a maingain cap limits the surplus', () {
      final t = DietPhaseCalculator.apply(
        phase: DietPhase.maingain,
        baselineKcal: 2500,
        calorieDeltaOverride: 250,
        eligibility: const PhaseEligibility(
          allowedPhases: {DietPhase.maingain},
          maxMaingainDeltaKcal: 150,
        ),
      );
      expect(t.deltaKcal, 150);
    });

    test('null and unrestricted eligibility leave every phase unchanged', () {
      for (final phase in DietPhase.values) {
        final base = DietPhaseCalculator.apply(
          phase: phase,
          baselineKcal: 2500,
          bodyweightKg: 80,
        );
        final open = DietPhaseCalculator.apply(
          phase: phase,
          baselineKcal: 2500,
          bodyweightKg: 80,
          eligibility: const PhaseEligibility.unrestricted(),
        );
        expect(open.kcal, base.kcal, reason: '$phase');
        expect(open.deltaKcal, base.deltaKcal, reason: '$phase');
        expect(open.proteinG, base.proteinG, reason: '$phase');
      }
    });
  });

  group('DietPhaseCalculator.paceOptionsFor', () {
    test('provides pace presets for all phases', () {
      for (final phase in DietPhase.values) {
        final options = DietPhaseCalculator.paceOptionsFor(phase);
        expect(options, isNotEmpty);
      }
    });
  });
}
