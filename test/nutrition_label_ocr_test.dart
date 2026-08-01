import 'package:flutter_test/flutter_test.dart';
import 'package:herculex/features/nutrition/data/nutrition_label_ocr_service.dart';
import 'package:herculex/features/nutrition/domain/nutrition_label.dart';

void main() {
  group('NutritionLabelOcrService.parse', () {
    test('converts per-serving label values to per-100 g', () {
      final draft = NutritionLabelOcrService.parse('''
        Alpine Oats
        Nutrition Facts
        Serving size 40 g
        Calories 160
        Protein 6 g
        Total Fat 4 g
        Total Carbohydrate 25 g
        Dietary Fiber 3 g
        Sodium 120 mg
      ''');

      expect(draft.source, LabelExtractionSource.ocr);
      expect(draft.name, 'Alpine Oats');
      expect(draft.servingGrams, 40);
      expect(draft.kcalPer100g, 400);
      expect(draft.proteinPer100g, 15);
      expect(draft.carbsPer100g, 62.5);
      expect(draft.fatPer100g, 10);
      expect(draft.fiberPer100g, 7.5);
      expect(draft.sodiumMgPer100g, 300);
      expect(draft.confidence, greaterThan(0.75));
    });

    test('recognises Slovenian label terms and marks incomplete OCR', () {
      final draft = NutritionLabelOcrService.parse('''
        Test jogurt
        Porcija 100 g
        Energija 80
        Beljakovin 5 g
        Maščob 2 g
      ''');

      expect(draft.name, 'Test jogurt');
      expect(draft.kcalPer100g, 80);
      expect(draft.proteinPer100g, 5);
      expect(draft.fatPer100g, 2);
      expect(draft.hasCoreNutrition, isFalse);
      expect(
        draft.confidence,
        lessThan(NutritionLabelOcrService.geminiFallbackThreshold),
      );
    });
  });
}
