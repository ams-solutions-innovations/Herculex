import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:herculex/features/profile/data/dream_physique_service.dart';
import 'package:herculex/features/profile/data/dream_physique_summary_repository.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  group('DreamPhysiqueSummaryRepository', () {
    test(
      'persists a privacy-preserving summary of a successful analysis',
      () async {
        SharedPreferences.setMockInitialValues({});
        final preferences = await SharedPreferences.getInstance();
        final repository = DreamPhysiqueSummaryRepository(preferences);
        addTearDown(repository.dispose);

        final summary = DreamPhysiqueAnalysisSummary.fromResult(
          result: _result(),
          currentPhotoCount: 2,
          targetPhotoCount: 1,
          analyzedAt: DateTime.utc(2026, 9, 11, 8),
        );

        await repository.save(summary);

        final restoredRepository = DreamPhysiqueSummaryRepository(preferences);
        addTearDown(restoredRepository.dispose);
        final restored = restoredRepository.current;
        expect(restored, isNotNull);
        expect(restored!.targetAestheticStyle, 'Athletic classic physique');
        expect(restored.timeframeRange, '12–18 months');
        expect(restored.currentPhotoCount, 2);
        expect(restored.targetPhotoCount, 1);

        final persistedList = preferences.getStringList(
          'herculex.dream_physique_summary_history.v1',
        )!;
        final persisted =
            jsonDecode(persistedList.single) as Map<String, dynamic>;
        expect(persisted.containsKey('imagePath'), isFalse);
        expect(persisted.containsKey('photos'), isFalse);
      },
    );

    test(
      'ignores invalid saved data instead of surfacing a broken goal',
      () async {
        SharedPreferences.setMockInitialValues({
          'herculex.dream_physique_summary.v1': '{invalid json',
        });
        final preferences = await SharedPreferences.getInstance();
        final repository = DreamPhysiqueSummaryRepository(preferences);
        addTearDown(repository.dispose);

        expect(repository.current, isNull);
      },
    );

    test('keeps a history of multiple analyses, newest first', () async {
      SharedPreferences.setMockInitialValues({});
      final preferences = await SharedPreferences.getInstance();
      final repository = DreamPhysiqueSummaryRepository(preferences);
      addTearDown(repository.dispose);

      final first = DreamPhysiqueAnalysisSummary.fromResult(
        result: _result(),
        currentPhotoCount: 2,
        targetPhotoCount: 1,
        analyzedAt: DateTime.utc(2026, 9, 1),
      );
      final second = DreamPhysiqueAnalysisSummary.fromResult(
        result: _result(),
        currentPhotoCount: 2,
        targetPhotoCount: 1,
        analyzedAt: DateTime.utc(2026, 9, 11),
      );

      await repository.save(first);
      await repository.save(second);

      expect(repository.history, hasLength(2));
      expect(repository.history.first.analyzedAt, second.analyzedAt);
      expect(repository.history.last.analyzedAt, first.analyzedAt);
      expect(repository.current!.analyzedAt, second.analyzedAt);
    });

    test('migrates a legacy single-summary entry into history', () async {
      final legacy = DreamPhysiqueAnalysisSummary.fromResult(
        result: _result(),
        currentPhotoCount: 2,
        targetPhotoCount: 1,
        analyzedAt: DateTime.utc(2026, 8, 1),
      );
      SharedPreferences.setMockInitialValues({
        'herculex.dream_physique_summary.v1': jsonEncode(legacy.toJson()),
      });
      final preferences = await SharedPreferences.getInstance();
      final repository = DreamPhysiqueSummaryRepository(preferences);
      addTearDown(repository.dispose);

      expect(repository.history, hasLength(1));
      expect(repository.current!.analyzedAt, legacy.analyzedAt);
    });
  });
}

DreamPhysiqueAnalysisResult _result() => const DreamPhysiqueAnalysisResult(
  estimatedMonths: 15,
  timeframeRange: '12–18 months',
  weightChangeKg: -4.5,
  leanMuscleGainKg: 3.2,
  fatLossKg: 7.7,
  targetBfPercent: 12,
  currentEstimatedBf: 19,
  musclePriorities: [
    MusclePriority(group: 'Back', priority: 'high', focus: 'Lat width'),
  ],
  nutritionStrategy: 'Maintain a modest deficit.',
  trainingAdvice: 'Train consistently.',
  overallAssessment: 'A realistic target.',
  targetAestheticStyle: 'Athletic classic physique',
);
