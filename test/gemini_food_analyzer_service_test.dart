import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:herculex/features/nutrition/data/gemini_food_analyzer_service.dart';
import 'package:herculex/features/nutrition/domain/nutrition_label.dart';
import 'package:herculex/services/gemini_backend_service.dart';

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
        {
          'group': 'Upper Chest',
          'priority': 'high',
          'focus': 'Incline press',
        }
      ],
      'nutritionStrategy': 'High protein deficit.',
      'trainingAdvice': 'PPL split.',
      'overallAssessment': 'Achievable goal.',
    };
  }
}
