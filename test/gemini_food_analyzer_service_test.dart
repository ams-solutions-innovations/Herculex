import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:herculex/features/nutrition/data/gemini_food_analyzer_service.dart';
import 'package:herculex/features/nutrition/domain/nutrition_label.dart';
import 'package:herculex/services/ai/gemini_backend_service.dart';

void main() {
  test(
    'food photo analysis is delegated to the server-side Gemini backend',
    () async {
      final backend = _FakeGeminiBackend();
      final service = GeminiFoodAnalyzerService(backend);
      final image = await _tempImage('.png');

      final result = await service.analyzeFoodPhoto(
        imageFile: image,
        userNote: 'large bowl',
      );

      expect(backend.lastKind, 'food_photo');
      expect(backend.lastMimeType, 'image/png');
      expect(backend.lastUserNote, 'large bowl');
      expect(result.name, 'Test meal');
      expect(result.kcalPer100g, 123);
    },
  );

  test(
    'nutrition label fallback maps backend JSON into an editable draft',
    () async {
      final backend = _FakeGeminiBackend();
      final service = GeminiFoodAnalyzerService(backend);
      final image = await _tempImage('.webp');

      final draft = await service.analyzeNutritionLabel(
        imageFile: image,
        ocrText: 'Serving 50 g Calories 200 Protein 10 g',
      );

      expect(backend.lastKind, 'nutrition_label');
      expect(backend.lastMimeType, 'image/webp');
      expect(backend.lastOcrText, contains('Serving 50 g'));
      expect(draft.source, LabelExtractionSource.gemini);
      expect(draft.kcalPer100g, 400);
      expect(draft.proteinPer100g, 20);
    },
  );

  test(
    'rambler voice and text food analysis parses structured food items and macros',
    () async {
      final backend = _FakeGeminiBackend();
      final service = GeminiFoodAnalyzerService(backend);

      final result = await service.analyzeRamblerText(
        text: '200g piščančjih prsi in 150g riža',
        preferredMealKey: 'lunch',
      );

      expect(backend.lastKind, 'rambler_food');
      expect(backend.lastText, '200g piščančjih prsi in 150g riža');
      expect(result.suggestedMealKey, 'lunch');
      expect(result.items.length, 2);
      expect(result.items[0].name, 'Piščančje prsi');
      expect(result.items[0].servingGrams, 200);
      expect(result.items[0].totalKcal, 330);
      expect(result.items[0].totalProtein, 62);
      expect(result.items[1].name, 'Kuhan riž');
      expect(result.items[1].servingGrams, 150);
    },
  );
}

Future<File> _tempImage(String extension) async {
  final dir = await Directory.systemTemp.createTemp('herculex_ai_test_');
  return File('${dir.path}/image$extension').writeAsBytes(<int>[1, 2, 3]);
}

class _FakeGeminiBackend implements GeminiBackend {
  String? lastKind;
  String? lastMimeType;
  String? lastUserNote;
  String? lastOcrText;

  @override
  Future<Map<String, dynamic>> analyzeFoodPhoto({
    required List<int> imageBytes,
    required String mimeType,
    String? userNote,
  }) async {
    lastKind = 'food_photo';
    lastMimeType = mimeType;
    lastUserNote = userNote;
    return {
      'name': 'Test meal',
      'brand': 'Gemini AI',
      'estimatedServingGrams': 250,
      'kcalPer100g': 123,
      'proteinPer100g': 12,
      'carbsPer100g': 20,
      'fatPer100g': 5,
      'fiberPer100g': 2,
      'rating': 8,
      'ratingReason': 'Looks balanced.',
    };
  }

  @override
  Future<Map<String, dynamic>> analyzeNutritionLabel({
    required List<int> imageBytes,
    required String mimeType,
    required String ocrText,
  }) async {
    lastKind = 'nutrition_label';
    lastMimeType = mimeType;
    lastOcrText = ocrText;
    return {
      'name': 'Protein bar',
      'brand': 'Test',
      'servingGrams': 50,
      'kcalPerServing': 200,
      'proteinPerServing': 10,
      'carbsPerServing': 18,
      'fatPerServing': 7,
      'fiberPerServing': 3,
      'sodiumMgPerServing': 120,
      'microsPerServing': {'calcium': 40},
      'confidence': 0.8,
      'notes': 'Checked against image.',
    };
  }

  @override
  Future<String> identifyExercise({
    required List<int> imageBytes,
    required String mimeType,
  }) async {
    lastKind = 'exercise_identification';
    lastMimeType = mimeType;
    return 'Unknown';
  }

  @override
  Future<Map<String, dynamic>> identifyExerciseDetailed({
    required List<int> imageBytes,
    required String mimeType,
  }) async {
    lastKind = 'exercise_identification';
    lastMimeType = mimeType;
    return {'identifiedName': 'Bench Press', 'confidence': 0.9};
  }

  @override
  Future<Map<String, dynamic>> analyzeSupplementPhoto({
    required List<int> imageBytes,
    required String mimeType,
    String? userNote,
  }) async {
    lastKind = 'supplement_photo';
    lastMimeType = mimeType;
    lastUserNote = userNote;
    return {
      'name': 'Creatine Monohydrate',
      'brand': 'Optimum Nutrition',
      'doseAmount': 5.0,
      'doseUnit': 'g',
      'nutrients': {'protein': 0.0},
      'schedule': 'post_workout',
      'confidence': 0.95,
    };
  }

  @override
  Future<Map<String, dynamic>> analyzeBarcodeProduct({
    required List<int> imageBytes,
    required String mimeType,
    required String barcode,
    String? userNote,
  }) async {
    lastKind = 'barcode_product';
    lastMimeType = mimeType;
    lastUserNote = userNote;
    return {
      'name': 'Test Barcode Product',
      'brand': 'Test Brand',
      'servingGrams': 100,
      'kcalPer100g': 250,
      'proteinPer100g': 15,
      'carbsPer100g': 30,
      'fatPer100g': 8,
      'fiberPer100g': 4,
    };
  }

  @override
  Future<Map<String, dynamic>> estimateBodyFat({
    required List<Map<String, dynamic>> images,
    Map<String, dynamic>? biometrics,
    String? userNote,
  }) async {
    lastKind = 'body_fat_estimate';
    return {
      'estimatedBfPercent': 14.5,
      'bfRangeMin': 13.0,
      'bfRangeMax': 16.0,
      'confidence': 0.9,
      'explanation': 'Good muscle definition.',
    };
  }

  @override
  Future<Map<String, dynamic>> analyzeDreamPhysique({
    required List<Map<String, dynamic>> currentImages,
    required List<int> targetImageBytes,
    required String targetImageMimeType,
    Map<String, dynamic>? biometrics,
    String? userNote,
  }) async {
    lastKind = 'dream_physique';
    return {
      'estimatedMonths': 6,
      'timeframeRange': '5 - 7 mesecev',
      'weightChangeKg': -2.0,
      'leanMuscleGainKg': 3.0,
      'fatLossKg': 5.0,
      'targetBfPercent': 11.0,
      'currentEstimatedBf': 17.0,
      'musclePriorities': [
        {'group': 'Upper Chest', 'priority': 'high', 'focus': 'Incline press'},
      ],
      'nutritionStrategy': 'High protein deficit.',
      'trainingAdvice': 'PPL split.',
      'overallAssessment': 'Achievable goal.',
    };
  }

  String? lastText;
  String? lastPreferredMealKey;

  @override
  Future<Map<String, dynamic>> analyzeRamblerText({
    required String text,
    String? preferredMealKey,
  }) async {
    lastKind = 'rambler_food';
    lastText = text;
    lastPreferredMealKey = preferredMealKey;
    return {
      'suggestedMealKey': 'lunch',
      'summary': 'Piščančje prsi in riž',
      'items': [
        {
          'name': 'Piščančje prsi',
          'servingGrams': 200.0,
          'portionAmount': 200.0,
          'portionUnit': 'g',
          'kcalPer100g': 165.0,
          'proteinPer100g': 31.0,
          'carbsPer100g': 0.0,
          'fatPer100g': 3.6,
          'fiberPer100g': 0.0,
          'confidence': 0.95,
        },
        {
          'name': 'Kuhan riž',
          'servingGrams': 150.0,
          'portionAmount': 150.0,
          'portionUnit': 'g',
          'kcalPer100g': 130.0,
          'proteinPer100g': 2.7,
          'carbsPer100g': 28.0,
          'fatPer100g': 0.3,
          'fiberPer100g': 0.4,
          'confidence': 0.9,
        },
      ],
    };
  }
}
