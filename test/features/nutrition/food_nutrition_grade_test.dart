import 'package:flutter_test/flutter_test.dart';
import 'package:herculex/features/nutrition/domain/food_insights.dart';

void main() {
  group('FoodInsights.gradeFor', () {
    test('Gold grade for >= 10g protein per 100 kcal', () {
      // Exactly 10g protein per 100 kcal
      expect(
        FoodInsights.gradeFor(kcal: 100, proteinG: 10, carbsG: 10, fatG: 2),
        equals(FoodNutritionGrade.gold),
      );

      // Stay Strong Pro Protein Drink from user screenshot: 195 kcal, 38g protein
      expect(
        FoodInsights.gradeFor(
          name: 'Stay Strong Pro Protein Drink',
          kcal: 195,
          proteinG: 38,
          carbsG: 10,
          fatG: 0,
        ),
        equals(FoodNutritionGrade.gold),
      );

      // High protein chicken breast: 165 kcal, 31g protein
      expect(
        FoodInsights.gradeFor(
          name: 'Chicken breast',
          kcal: 165,
          proteinG: 31,
          carbsG: 0,
          fatG: 3.6,
        ),
        equals(FoodNutritionGrade.gold),
      );
    });

    test('Green grade for low calories', () {
      // Very low calorie portion (e.g. cucumber, tea)
      expect(
        FoodInsights.gradeFor(
          name: 'Cucumber',
          kcal: 15,
          proteinG: 0.7,
          carbsG: 3.6,
          fatG: 0.1,
        ),
        equals(FoodNutritionGrade.green),
      );

      // Low calorie density per 100g (e.g. watermelon: 30 kcal/100g)
      expect(
        FoodInsights.gradeFor(
          name: 'Watermelon',
          kcal: 90,
          proteinG: 1.8,
          carbsG: 22,
          fatG: 0.5,
          kcalPer100g: 30,
        ),
        equals(FoodNutritionGrade.green),
      );

      // Apple portion <= 60 kcal
      expect(
        FoodInsights.gradeFor(
          name: 'Apple',
          kcal: 52,
          proteinG: 0.3,
          carbsG: 14,
          fatG: 0.2,
          kcalPer100g: 52,
        ),
        equals(FoodNutritionGrade.green),
      );
    });

    test('Red grade for bad macros (high fat/sugar, negligible protein)', () {
      // Potato chips: high fat, high carbs, low protein
      expect(
        FoodInsights.gradeFor(
          name: 'Potato chips',
          kcal: 540,
          proteinG: 6,
          carbsG: 53,
          fatG: 35,
          kcalPer100g: 540,
        ),
        equals(FoodNutritionGrade.red),
      );

      // Donut / Pastry: high fat + high carbs, very low protein
      expect(
        FoodInsights.gradeFor(
          name: 'Glazed Donut',
          kcal: 450,
          proteinG: 4,
          carbsG: 50,
          fatG: 25,
          kcalPer100g: 450,
        ),
        equals(FoodNutritionGrade.red),
      );

      // Butter: nearly pure fat, no protein
      expect(
        FoodInsights.gradeFor(
          name: 'Butter',
          kcal: 720,
          proteinG: 0.9,
          carbsG: 0.1,
          fatG: 81,
          kcalPer100g: 720,
        ),
        equals(FoodNutritionGrade.red),
      );
    });

    test('Normal grade (no gradient) for balanced everyday foods', () {
      // 'z bregov Protein Snack from screenshot: 183 kcal, 10g protein, 12g carbs, 10g fat
      expect(
        FoodInsights.gradeFor(
          name: "'z bregov Protein Snack",
          kcal: 183,
          proteinG: 10,
          carbsG: 12,
          fatG: 10,
        ),
        equals(FoodNutritionGrade.normal),
      );

      // Cooked white rice: carb staple, not junk
      expect(
        FoodInsights.gradeFor(
          name: 'White rice',
          kcal: 130,
          proteinG: 2.7,
          carbsG: 28,
          fatG: 0.3,
          kcalPer100g: 130,
        ),
        equals(FoodNutritionGrade.normal),
      );

      // Oatmeal: balanced carbs and protein
      expect(
        FoodInsights.gradeFor(
          name: 'Oatmeal',
          kcal: 150,
          proteinG: 5,
          carbsG: 27,
          fatG: 2.5,
          kcalPer100g: 370,
        ),
        equals(FoodNutritionGrade.normal),
      );

      // Placeholder item
      expect(
        FoodInsights.gradeFor(
          name: '—',
          kcal: 0,
          proteinG: 0,
          carbsG: 0,
          fatG: 0,
        ),
        equals(FoodNutritionGrade.normal),
      );
    });
  });
}
