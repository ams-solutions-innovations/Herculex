import 'package:flutter_test/flutter_test.dart';
import 'package:herculex/features/nutrition/domain/diet_phase.dart';

void main() {
  group('DietPhase', () {
    test('save labels name the phase', () {
      expect(DietPhase.cut.saveLabel, 'Save Cut');
      expect(DietPhase.bulk.saveLabel, 'Save Bulk');
      expect(DietPhase.maintain.saveLabel, 'Save Target');
    });
  });

  group('DietPhaseCalculator.apply', () {
    test('maintain leaves calories untouched', () {
      final t = DietPhaseCalculator.apply(
          phase: DietPhase.maintain, baselineKcal: 2500, bodyweightKg: 80);
      expect(t.kcal, 2500);
    });

    test('cut removes the default 20% deficit', () {
      final t = DietPhaseCalculator.apply(
          phase: DietPhase.cut, baselineKcal: 2500, bodyweightKg: 80);
      expect(t.kcal, 2000);
    });

    test('bulk adds the default 10% surplus', () {
      final t = DietPhaseCalculator.apply(
          phase: DietPhase.bulk, baselineKcal: 2500, bodyweightKg: 80);
      expect(t.kcal, 2750);
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

    test('protein is raised in a cut relative to maintenance', () {
      final cut = DietPhaseCalculator.apply(
          phase: DietPhase.cut, baselineKcal: 2500, bodyweightKg: 80);
      final maintain = DietPhaseCalculator.apply(
          phase: DietPhase.maintain, baselineKcal: 2500, bodyweightKg: 80);
      expect(cut.proteinG, greaterThan(maintain.proteinG));
      expect(cut.proteinG, (80 * 2.2).round());
    });

    test('macros add back up to the calorie target', () {
      for (final phase in DietPhase.values) {
        final t = DietPhaseCalculator.apply(
            phase: phase, baselineKcal: 2600, bodyweightKg: 75);
        final sum = t.proteinG * 4 + t.carbsG * 4 + t.fatG * 9;
        // Rounding to whole grams costs a few kcal at most.
        expect((sum - t.kcal).abs(), lessThanOrEqualTo(12),
            reason: '$phase macros summed to $sum vs ${t.kcal} kcal');
      }
    });

    test('falls back to a percentage split without a bodyweight', () {
      final t = DietPhaseCalculator.apply(
          phase: DietPhase.cut, baselineKcal: 2000, bodyweightKg: null);
      // The fallback is a share of the *adjusted* calories (2000 − 20 %).
      expect(t.kcal, 1600);
      expect(t.proteinG, (1600 * 0.30 / 4).round());
      expect(t.carbsG, greaterThanOrEqualTo(0));
    });

    test('a very low target still yields non-negative carbs', () {
      // 130 kg lifter on 800 kcal: protein alone would exceed the budget.
      final t = DietPhaseCalculator.apply(
          phase: DietPhase.cut, baselineKcal: 1000, bodyweightKg: 130);
      expect(t.carbsG, greaterThanOrEqualTo(0));
      expect(t.fatG, greaterThanOrEqualTo(0));
      expect(t.proteinG, greaterThanOrEqualTo(0));
      expect(t.proteinG * 4, lessThanOrEqualTo(t.kcal));
    });

    test('a zero baseline produces an all-zero target', () {
      final t = DietPhaseCalculator.apply(
          phase: DietPhase.cut, baselineKcal: 0, bodyweightKg: 80);
      expect(t.kcal, 0);
      expect(t.proteinG, 0);
      expect(t.carbsG, 0);
      expect(t.fatG, 0);
    });
  });
}
