import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:herculex/features/supplements/data/supplement_ai_service.dart';
import 'package:herculex/features/supplements/domain/supplement.dart';
import 'package:herculex/services/gemini_backend_service.dart';

void main() {
  group('SupplementAiService', () {
    test('parses supplement photo analysis into SupplementAiResult', () async {
      final fakeBackend = _MockSupplementBackend();
      final service = SupplementAiService(fakeBackend);

      final tempDir = await Directory.systemTemp.createTemp('supp_test_');
      final imageFile = File('${tempDir.path}/test_supp.jpg');
      await imageFile.writeAsBytes([1, 2, 3]);

      final result = await service.analyzeSupplementPhoto(
        imageFile: imageFile,
        userNote: '1 scoop daily',
      );

      expect(result.name, 'Creatine Monohydrate');
      expect(result.brand, 'Optimum Nutrition');
      expect(result.doseAmount, 5.0);
      expect(result.doseUnit, 'g');
      expect(result.schedule, SupplementSchedule.postWorkout);
      expect(result.nutrients['protein'], 24.0);
      expect(result.nutrients['creatine'], 5.0);
      expect(result.nutrients['vitamin_d'], 25.0);

      final supplement = result.toSupplement(id: 'supp_123');
      expect(supplement.id, 'supp_123');
      expect(supplement.name, 'Creatine Monohydrate');
      expect(supplement.doseLabel, '5 g');
    });
  });
}

class _MockSupplementBackend implements GeminiBackend {
  @override
  Future<Map<String, dynamic>> analyzeSupplementPhoto({
    required List<int> imageBytes,
    required String mimeType,
    String? userNote,
  }) async {
    return {
      'name': 'Creatine Monohydrate',
      'brand': 'Optimum Nutrition',
      'doseAmount': 5.0,
      'doseUnit': 'g',
      'nutrients': {'protein': 24.0, 'creatine': 5.0, 'vit_d': 25.0},
      'schedule': 'post_workout',
      'timeHHMM': null,
      'confidence': 0.95,
      'description': 'Čisti mikroniziran kreatin monohidrat.',
    };
  }

  @override
  Future<Map<String, dynamic>> analyzeBarcodeProduct({
    required List<int> imageBytes,
    required String mimeType,
    required String barcode,
    String? userNote,
  }) async => throw UnimplementedError();

  @override
  Future<Map<String, dynamic>> analyzeDreamPhysique({
    required List<Map<String, dynamic>> currentImages,
    required List<int> targetImageBytes,
    required String targetImageMimeType,
    Map<String, dynamic>? biometrics,
    String? userNote,
  }) async => throw UnimplementedError();

  @override
  Future<Map<String, dynamic>> analyzeFoodPhoto({
    required List<int> imageBytes,
    required String mimeType,
    String? userNote,
  }) async => throw UnimplementedError();

  @override
  Future<Map<String, dynamic>> analyzeNutritionLabel({
    required List<int> imageBytes,
    required String mimeType,
    required String ocrText,
  }) async => throw UnimplementedError();

  @override
  Future<Map<String, dynamic>> estimateBodyFat({
    required List<Map<String, dynamic>> images,
    Map<String, dynamic>? biometrics,
    String? userNote,
  }) async => throw UnimplementedError();

  @override
  Future<String> identifyExercise({
    required List<int> imageBytes,
    required String mimeType,
  }) async => throw UnimplementedError();

  @override
  Future<Map<String, dynamic>> identifyExerciseDetailed({
    required List<int> imageBytes,
    required String mimeType,
  }) async => throw UnimplementedError();

  @override
  Future<Map<String, dynamic>> analyzeRamblerText({
    required String text,
    String? preferredMealKey,
  }) async => throw UnimplementedError();
}
