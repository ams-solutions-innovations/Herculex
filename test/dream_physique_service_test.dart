import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:herculex/features/profile/data/dream_physique_service.dart';
import 'package:herculex/features/profile/domain/profile.dart';
import 'package:herculex/services/ai/gemini_backend_service.dart';

void main() {
  group('DreamPhysiqueService', () {
    test(
      'Correctly maps backend response into DreamPhysiqueAnalysisResult',
      () async {
        final fakeBackend = _MockGeminiBackend();
        final service = DreamPhysiqueService(fakeBackend);

        final tempDir = await Directory.systemTemp.createTemp('dp_test_');
        addTearDown(() => tempDir.delete(recursive: true));
        final currentFile = File('${tempDir.path}/current.jpg');
        await currentFile.writeAsBytes([1, 2, 3]);
        final targetFile = File('${tempDir.path}/target.jpg');
        await targetFile.writeAsBytes([4, 5, 6]);
        final targetFileTwo = File('${tempDir.path}/target-two.jpg');
        await targetFileTwo.writeAsBytes([7, 8, 9]);

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
          targetImages: [targetFile, targetFileTwo],
          consentGranted: true,
          profile: profile,
          userNote: 'Goal is classic aesthetic',
        );

        expect(result.estimatedMonths, 8);
        expect(result.timeframeRange, '6 - 9 months');
        expect(result.weightChangeKg, -2.5);
        expect(result.leanMuscleGainKg, 3.5);
        expect(result.fatLossKg, 6.0);
        expect(result.targetBfPercent, 11.0);
        expect(result.musclePriorities.length, 2);
        expect(result.musclePriorities.first.group, 'Upper chest');
        expect(result.musclePriorities.first.priority, 'high');
        expect(result.programmingProfile?.schemaVersion, 1);
        expect(
          result.programmingProfile?.musclePriorities.first.muscleId,
          'chest',
        );
        expect(
          result.programmingProfile?.musclePriorities.first.priority,
          ProgrammingPriorityLevel.high,
        );
        expect(
          result.programmingProfile?.musclePriorities.first.confidence,
          0.87,
        );
        expect(result.isAiGenerated, isTrue);
        expect(result.targetAestheticStyle, contains('V-taper'));
        expect(fakeBackend.calledDreamPhysique, isTrue);
        expect(fakeBackend.receivedTargetImages, hasLength(2));
      },
    );

    test('propagates an honest recoverable error when backend fails', () async {
      final failingBackend = _FailingGeminiBackend();
      final service = DreamPhysiqueService(failingBackend);

      final tempDir = await Directory.systemTemp.createTemp(
        'dp_fallback_test_',
      );
      addTearDown(() => tempDir.delete(recursive: true));
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

      await expectLater(
        service.compareAndAnalyzePhysique(
          currentImages: [currentFile],
          targetImages: [targetFile],
          consentGranted: true,
          profile: profile,
        ),
        throwsA(
          isA<DreamPhysiqueAnalysisException>()
              .having((error) => error.recoverable, 'recoverable', isTrue)
              .having(
                (error) => error.message,
                'message',
                contains('Server unreachable'),
              ),
        ),
      );

      expect(failingBackend.calledDreamPhysique, isTrue);
      expect(currentFile.existsSync(), isTrue);
      expect(targetFile.existsSync(), isTrue);
    });

    test('does not read or upload images before explicit consent', () async {
      final backend = _MockGeminiBackend();
      final service = DreamPhysiqueService(backend);

      await expectLater(
        service.compareAndAnalyzePhysique(
          currentImages: [File('does-not-need-to-exist.jpg')],
          targetImages: [File('also-not-read.jpg')],
          consentGranted: false,
        ),
        throwsA(
          isA<DreamPhysiqueAnalysisException>()
              .having((error) => error.recoverable, 'recoverable', isFalse)
              .having(
                (error) => error.message,
                'message',
                contains('privacy notice'),
              ),
        ),
      );

      expect(backend.calledDreamPhysique, isFalse);
    });

    test('keeps current response fields compatible without new profile', () {
      final result = DreamPhysiqueAnalysisResult.fromJson({
        'estimatedMonths': 8,
        'timeframeRange': '6 - 9 months',
        'weightChangeKg': -2.5,
        'leanMuscleGainKg': 3.5,
        'fatLossKg': 6.0,
        'targetBfPercent': 11.0,
        'currentEstimatedBf': 17.5,
        'musclePriorities': [
          {
            'group': 'Upper chest',
            'priority': 'high',
            'focus': 'Additional upper-chest emphasis',
          },
        ],
        'nutritionStrategy': 'Slight deficit.',
        'trainingAdvice': 'Progressive training.',
        'overallAssessment': 'Goal is achievable.',
        'targetAestheticStyle': 'Lean athletic physique.',
      });

      expect(result.estimatedMonths, 8);
      expect(result.musclePriorities.single.group, 'Upper chest');
      expect(result.programmingProfile, isNull);
    });
  });
}

class _MockGeminiBackend implements GeminiBackend {
  bool calledDreamPhysique = false;
  List<Map<String, dynamic>>? receivedTargetImages;

  @override
  Future<Map<String, dynamic>> analyzeDreamPhysique({
    required List<Map<String, dynamic>> currentImages,
    required List<Map<String, dynamic>> targetImages,
    Map<String, dynamic>? biometrics,
    String? userNote,
  }) async {
    calledDreamPhysique = true;
    receivedTargetImages = targetImages;
    return {
      'estimatedMonths': 8,
      'timeframeRange': '6 - 9 months',
      'weightChangeKg': -2.5,
      'leanMuscleGainKg': 3.5,
      'fatLossKg': 6.0,
      'targetBfPercent': 11.0,
      'currentEstimatedBf': 17.5,
      'musclePriorities': [
        {
          'group': 'Upper chest',
          'priority': 'high',
          'focus': 'Incline dumbbell press',
        },
        {
          'group': 'Lateral delts',
          'priority': 'high',
          'focus': 'Lateral raises',
        },
      ],
      'programmingProfile': {
        'schemaVersion': 1,
        'overallConfidence': 0.81,
        'musclePriorities': [
          {
            'muscleId': 'chest',
            'priority': 'high',
            'confidence': 0.87,
            'rationale': 'The target has more upper-chest emphasis.',
            'uncertainties': ['Camera angle differs.'],
          },
          {
            'muscleId': 'side_delts',
            'priority': 'high',
            'confidence': 0.79,
            'rationale': 'Shoulder width differs visibly.',
            'uncertainties': ['Lighting differs.'],
          },
        ],
        'uncertainties': ['Visual estimates are pose-dependent.'],
      },
      'nutritionStrategy': 'Slight deficit.',
      'trainingAdvice': 'PPL split 5x weekly.',
      'overallAssessment': 'Goal is achievable.',
      'targetAestheticStyle': 'Athletic V-taper physique.',
    };
  }

  @override
  Future<Map<String, dynamic>> estimateBodyFat({
    required List<Map<String, dynamic>> images,
    Map<String, dynamic>? biometrics,
    String? userNote,
  }) async => throw UnimplementedError();

  @override
  Future<Map<String, dynamic>> analyzeBarcodeProduct({
    required List<int> imageBytes,
    required String mimeType,
    required String barcode,
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
  Future<Map<String, dynamic>> analyzeSupplementPhoto({
    required List<int> imageBytes,
    required String mimeType,
    String? userNote,
  }) async => throw UnimplementedError();

  @override
  Future<Map<String, dynamic>> analyzeRamblerText({
    required String text,
    String? preferredMealKey,
  }) async => throw UnimplementedError();
}

class _FailingGeminiBackend implements GeminiBackend {
  bool calledDreamPhysique = false;

  @override
  Future<Map<String, dynamic>> analyzeDreamPhysique({
    required List<Map<String, dynamic>> currentImages,
    required List<Map<String, dynamic>> targetImages,
    Map<String, dynamic>? biometrics,
    String? userNote,
  }) async {
    calledDreamPhysique = true;
    throw Exception('Server unreachable');
  }

  @override
  Future<Map<String, dynamic>> estimateBodyFat({
    required List<Map<String, dynamic>> images,
    Map<String, dynamic>? biometrics,
    String? userNote,
  }) async => throw UnimplementedError();

  @override
  Future<Map<String, dynamic>> analyzeBarcodeProduct({
    required List<int> imageBytes,
    required String mimeType,
    required String barcode,
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
  Future<Map<String, dynamic>> analyzeSupplementPhoto({
    required List<int> imageBytes,
    required String mimeType,
    String? userNote,
  }) async => throw UnimplementedError();

  @override
  Future<Map<String, dynamic>> analyzeRamblerText({
    required String text,
    String? preferredMealKey,
  }) async => throw UnimplementedError();
}
