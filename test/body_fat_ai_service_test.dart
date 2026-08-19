import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:herculex/features/measurements/data/body_fat_ai_service.dart';
import 'package:herculex/features/profile/domain/profile.dart';
import 'package:herculex/services/gemini_backend_service.dart';

void main() {
  group('BodyFatAiService', () {
    test('Navy formula calculates accurate body fat for male', () {
      // Height 180cm, Waist 82cm, Neck 38cm
      final bf = BodyFatAiService.calculateNavyBodyFat(
        heightCm: 180,
        waistCm: 82,
        neckCm: 38,
        isMale: true,
      );

      expect(bf, isNotNull);
      expect(bf!, greaterThan(10.0));
      expect(bf, lessThan(18.0));
    });

    test('Navy formula calculates accurate body fat for female', () {
      // Height 165cm, Waist 70cm, Neck 32cm, Hips 95cm
      final bf = BodyFatAiService.calculateNavyBodyFat(
        heightCm: 165,
        waistCm: 70,
        neckCm: 32,
        hipsCm: 95,
        isMale: false,
      );

      expect(bf, isNotNull);
      expect(bf!, greaterThan(18.0));
      expect(bf, lessThan(28.0));
    });

    test('BMI formula computes sensible baseline', () {
      final bf = BodyFatAiService.calculateBmiBodyFat(
        weightKg: 80,
        heightCm: 180,
        ageYears: 25,
        isMale: true,
      );

      expect(bf, greaterThan(12.0));
      expect(bf, lessThan(22.0));
    });

    test('Delegates to Gemini backend when images provided', () async {
      final fakeBackend = _MockGeminiBackend();
      final service = BodyFatAiService(fakeBackend);

      final tempDir = await Directory.systemTemp.createTemp('bf_test_');
      final imageFile = File('${tempDir.path}/test_body.jpg');
      await imageFile.writeAsBytes([1, 2, 3, 4]);

      const profile = Profile(
        goal: FitnessGoal.muscleGain,
        activityLevel: ActivityLevel.active,
        weightKg: 80.0,
        heightCm: 180.0,
        ageYears: 28,
        sex: BiologicalSex.male,
      );

      final result = await service.estimateBodyFat(
        imageFiles: [imageFile],
        profile: profile,
        measurements: {'waist': 82.0, 'neck': 38.0},
        userNote: 'morning photo',
      );

      expect(result.estimatedBfPercent, 13.8);
      expect(result.bfRangeMin, 12.5);
      expect(result.bfRangeMax, 15.0);
      expect(result.leanMassKg, isNotNull);
      expect(result.fatMassKg, isNotNull);
      expect(result.isAiGenerated, isTrue);
      expect(fakeBackend.calledEstimate, isTrue);
    });

    test('Falls back gracefully to anthropometric formula without images', () async {
      final fakeBackend = _MockGeminiBackend();
      final service = BodyFatAiService(fakeBackend);

      const profile = Profile(
        goal: FitnessGoal.maintenance,
        activityLevel: ActivityLevel.active,
        weightKg: 80.0,
        heightCm: 180.0,
        ageYears: 28,
        sex: BiologicalSex.male,
      );

      final result = await service.estimateBodyFat(
        imageFiles: [],
        profile: profile,
        measurements: {'waist': 82.0, 'neck': 38.0},
      );

      expect(result.estimatedBfPercent, greaterThan(10.0));
      expect(result.isAiGenerated, isFalse);
      expect(fakeBackend.calledEstimate, isFalse);
    });
  });
}

class _MockGeminiBackend implements GeminiBackend {
  bool calledEstimate = false;

  @override
  Future<Map<String, dynamic>> estimateBodyFat({
    required List<Map<String, dynamic>> images,
    Map<String, dynamic>? biometrics,
    String? userNote,
  }) async {
    calledEstimate = true;
    return {
      'estimatedBfPercent': 13.8,
      'bfRangeMin': 12.5,
      'bfRangeMax': 15.0,
      'confidence': 0.92,
      'explanation': 'Odlična definicija trebušnih mišic in nizka raven podkožne maščobe.',
      'fatDistribution': 'Zmerno na spodnjem delu trebuha.',
      'recommendations': 'Vzdržujte trenutni vnos kalorij.',
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
    throw UnimplementedError();
  }

  @override
  Future<Map<String, dynamic>> analyzeBarcodeProduct({
    required List<int> imageBytes,
    required String mimeType,
    required String barcode,
    String? userNote,
  }) async =>
      throw UnimplementedError();

  @override
  Future<Map<String, dynamic>> analyzeFoodPhoto({
    required List<int> imageBytes,
    required String mimeType,
    String? userNote,
  }) async =>
      throw UnimplementedError();

  @override
  Future<Map<String, dynamic>> analyzeNutritionLabel({
    required List<int> imageBytes,
    required String mimeType,
    required String ocrText,
  }) async =>
      throw UnimplementedError();

  @override
  Future<String> identifyExercise({
    required List<int> imageBytes,
    required String mimeType,
  }) async =>
      throw UnimplementedError();
}
