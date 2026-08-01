import 'package:flutter_test/flutter_test.dart';
import 'package:herculex/features/nutrition/domain/food_insights.dart';

void main() {
  group('FoodInsights.forPer100g', () {
    List<String> labels(List<FoodInsight> insights) =>
        [for (final i in insights) i.label];

    test('a food with no energy produces no claims', () {
      expect(
        FoodInsights.forPer100g(kcal: 0, proteinG: 0, carbsG: 0, fatG: 0),
        isEmpty,
      );
    });

    test('chicken breast is high in protein and low fat', () {
      final out = FoodInsights.forPer100g(
          kcal: 165, proteinG: 31, carbsG: 0, fatG: 3.6);
      expect(labels(out), contains('High in protein'));
    });

    test('protein between 12% and 20% of energy is only a "source"', () {
      // 5 g protein = 20 kcal of 130 kcal ≈ 15 %.
      final out = FoodInsights.forPer100g(
          kcal: 130, proteinG: 5, carbsG: 25, fatG: 1);
      expect(labels(out), contains('Source of protein'));
      expect(labels(out), isNot(contains('High in protein')));
    });

    test('olive oil is flagged as high in fat, not low fat', () {
      final out = FoodInsights.forPer100g(
          kcal: 884, proteinG: 0, carbsG: 0, fatG: 100);
      expect(labels(out), contains('High in fat'));
      expect(labels(out), isNot(contains('Low fat')));
    });

    test('lettuce is low calorie and low fat', () {
      final out = FoodInsights.forPer100g(
          kcal: 15, proteinG: 1.4, carbsG: 2.9, fatG: 0.2);
      expect(labels(out), containsAll(['Low fat', 'Low calorie']));
    });

    test('high fibre is claimed at or above 6 g per 100 g', () {
      final out = FoodInsights.forPer100g(
          kcal: 340, proteinG: 13, carbsG: 60, fatG: 7, fiberG: 10);
      expect(labels(out), contains('High in fibre'));
    });

    test('sodium above the threshold raises a caution badge', () {
      final out = FoodInsights.forPer100g(
        kcal: 300,
        proteinG: 5,
        carbsG: 60,
        fatG: 2,
        sodiumMg: 1200,
        limit: 10,
      );
      final sodium = out.firstWhere((i) => i.label == 'High in sodium');
      expect(sodium.tone, InsightTone.caution);
    });

    test('carb-dense is only used when nothing more specific applies', () {
      // High-carb but also low fat, so "Low fat" wins and carb-dense is
      // suppressed.
      final lowFat = FoodInsights.forPer100g(
          kcal: 350, proteinG: 6, carbsG: 78, fatG: 1);
      expect(labels(lowFat), isNot(contains('Carb-dense')));

      // Mid-range fat: nothing else qualifies, so the descriptive badge shows.
      final plain = FoodInsights.forPer100g(
          kcal: 400, proteinG: 5, carbsG: 60, fatG: 12);
      expect(labels(plain), contains('Carb-dense'));
    });

    test('never returns more than the requested limit', () {
      final out = FoodInsights.forPer100g(
        kcal: 100,
        proteinG: 10,
        carbsG: 5,
        fatG: 0.5,
        fiberG: 12,
        sodiumMg: 900,
        limit: 2,
      );
      expect(out.length, 2);
    });
  });

  group('MacroSplit', () {
    test('converts grams to energy with 4/4/9 factors', () {
      final s = MacroSplit.fromGrams(proteinG: 10, carbsG: 20, fatG: 5);
      expect(s.proteinKcal, 40);
      expect(s.carbsKcal, 80);
      expect(s.fatKcal, 45);
      expect(s.totalKcal, 165);
    });

    test('shares sum to one', () {
      final s = MacroSplit.fromGrams(proteinG: 10, carbsG: 20, fatG: 5);
      expect(s.proteinShare + s.carbsShare + s.fatShare, closeTo(1.0, 1e-9));
    });

    test('an empty split reports zero shares rather than dividing by zero', () {
      final s = MacroSplit.fromGrams(proteinG: 0, carbsG: 0, fatG: 0);
      expect(s.proteinShare, 0);
      expect(s.carbsShare, 0);
      expect(s.fatShare, 0);
    });
  });
}
