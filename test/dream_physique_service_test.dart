import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:herculex/features/profile/data/dream_physique_service.dart';
import 'package:herculex/features/profile/domain/profile.dart';
import 'package:herculex/services/gemini_backend_service.dart';

void main() {
  group('DreamPhysiqueService', () {
    test('Correctly maps backend response into DreamPhysiqueAnalysisResult', () async {
      final fakeBackend = _MockGeminiBackend();
      final service = DreamPhysiqueService(fakeBackend);

      final tempDir = await Directory.systemTemp.createTemp('dp_test_');
      final currentFile = File('${tempDir.path}/current.jpg');
      await currentFile.writeAsBytes([1, 2, 3]);
      final targetFile = File('${tempDir.path}/target.jpg');
      await targetFile.writeAsBytes([4, 5, 6]);

      const profile = Profile(
        goal: FitnessGoal.muscleGain,
        activityLevel: ActivityLevel.active,
        weightKg: 82.0,
        heightCm: 182.0,
        ageYears: 27,
        sex: BiologicalSex.male,
      );

      final result = await service.compareAndAnalyzePhysique(
        currentImages: [currentFile],
        targetImage: targetFile,
        profile: profile,
        targetGoalStyle: 'Lean & Aesthetic',
        userNote: 'Goal is classic aesthetic',
      );

      expect(result.estimatedMonths, 8);
      expect(result.timeframeRange, '6 - 9 mesecev');
      expect(result.weightChangeKg, -2.5);
      expect(result.leanMuscleGainKg, 3.5);
      expect(result.fatLossKg, 6.0);
      expect(result.targetBfPercent, 11.0);
      expect(result.musclePriorities.length, 2);
      expect(result.musclePriorities.first.group, 'Zgornji del prsi');
      expect(result.musclePriorities.first.priority, 'high');
      expect(result.isAiGenerated, isTrue);
      expect(fakeBackend.calledDreamPhysique, isTrue);
    });

    test('Provides fallback computation when backend call fails', () async {
      final failingBackend = _FailingGeminiBackend();
      final service = DreamPhysiqueService(failingBackend);

      final tempDir = await Directory.systemTemp.createTemp('dp_fallback_test_');
      final currentFile = File('${tempDir.path}/curr.jpg');
      await currentFile.writeAsBytes([1]);
      final targetFile = File('${tempDir.path}/targ.jpg');
      await targetFile.writeAsBytes([2]);

      const profile = Profile(
        goal: FitnessGoal.muscleGain,
        activityLevel: ActivityLevel.active,
        weightKg: 80.0,
        heightCm: 180.0,
        ageYears: 25,
        sex: BiologicalSex.male,
      );

      final result = await service.compareAndAnalyzePhysique(
        currentImages: [currentFile],
        targetImage: targetFile,
        profile: profile,
        targetGoalStyle: 'Lean & Aesthetic',
      );

      expect(result.estimatedMonths, greaterThan(0));
      expect(result.leanMuscleGainKg, greaterThan(0));
      expect(result.fatLossKg, greaterThan(0));
      expect(result.musclePriorities.isNotEmpty, isTrue);
      expect(result.isAiGenerated, isFalse);
    });
  });
}

class _MockGeminiBackend implements GeminiBackend {
  bool calledDreamPhysique = false;

  @override
  Future<Map<String, dynamic>> analyzeDreamPhysique({
    required List<Map<String, dynamic>> currentImages,
    required List<int> targetImageBytes,
    required String targetImageMimeType,
    Map<String, dynamic>? biometrics,
    String? userNote,
  }) async {
    calledDreamPhysique = true;
    return {
      'estimatedMonths': 8,
      'timeframeRange': '6 - 9 mesecev',
      'weightChangeKg': -2.5,
      'leanMuscleGainKg': 3.5,
      'fatLossKg': 6.0,
      'targetBfPercent': 11.0,
      'currentEstimatedBf': 17.5,
      'musclePriorities': [
        {
          'group': 'Zgornji del prsi',
          'priority': 'high',
          'focus': 'Incline dumbell press',
        },
        {
          'group': 'Stranske rame',
          'priority': 'high',
          'focus': 'Lateral raises',
        },
      ],
      'nutritionStrategy': 'Rahel deficit.',
      'trainingAdvice': 'PPL split 5x tedensko.',
      'overallAssessment': 'Cilj je dosegljiv.',
    };
  }

  @override
  Future<Map<String, dynamic>> estimateBodyFat({
    required List<Map<String, dynamic>> images,
    Map<String, dynamic>? biometrics,
    String? userNote,
  }) async =>
      throw UnimplementedError();

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

class _FailingGeminiBackend implements GeminiBackend {
  @override
  Future<Map<String, dynamic>> analyzeDreamPhysique({
    required List<Map<String, dynamic>> currentImages,
    required List<int> targetImageBytes,
    required String targetImageMimeType,
    Map<String, dynamic>? biometrics,
    String? userNote,
  }) async {
    throw Exception('Server unreachable');
  }

  @override
  Future<Map<String, dynamic>> estimateBodyFat({
    required List<Map<String, dynamic>> images,
    Map<String, dynamic>? biometrics,
    String? userNote,
  }) async =>
      throw UnimplementedError();

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
