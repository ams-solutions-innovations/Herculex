import 'package:flutter_test/flutter_test.dart';
import 'package:herculex/features/profile/data/dream_physique_summary_repository.dart';
import 'package:herculex/features/profile/domain/dream_physique_nutrition_recommendation.dart';
import 'package:herculex/features/profile/domain/profile.dart';

void main() {
  const profile = Profile(
    goal: FitnessGoal.muscleGain,
    activityLevel: ActivityLevel.active,
    weightKg: 80,
    heightCm: 180,
  );

  test('recommends a cut for a large saved body-fat gap', () {
    final result = DreamPhysiqueNutritionRecommender.recommend(
      profile: profile,
      summary: _summary(currentBf: 22, targetBf: 14, weightChangeKg: -7),
    );

    expect(result?.direction, PhysiqueNutritionDirection.cut);
    expect(result?.reasons, hasLength(2));
  });

  test('recommends a bulk for a large gain roadmap near target leanness', () {
    final result = DreamPhysiqueNutritionRecommender.recommend(
      profile: profile,
      summary: _summary(currentBf: 13, targetBf: 14, weightChangeKg: 7),
    );

    expect(result?.direction, PhysiqueNutritionDirection.bulk);
  });

  test('recommends recomp for a modest body-fat gap', () {
    final result = DreamPhysiqueNutritionRecommender.recommend(
      profile: profile,
      summary: _summary(currentBf: 17, targetBf: 14, weightChangeKg: -2),
    );

    expect(result?.direction, PhysiqueNutritionDirection.recomp);
  });

  test('recommends maingain for a gradual gain roadmap near target', () {
    final result = DreamPhysiqueNutritionRecommender.recommend(
      profile: profile,
      summary: _summary(currentBf: 13, targetBf: 14, weightChangeKg: 4),
    );

    expect(result?.direction, PhysiqueNutritionDirection.maingain);
  });

  test('does not make a suggestion without a usable saved weight', () {
    const incompleteProfile = Profile(
      goal: FitnessGoal.muscleGain,
      activityLevel: ActivityLevel.active,
    );

    expect(
      DreamPhysiqueNutritionRecommender.recommend(
        profile: incompleteProfile,
        summary: _summary(currentBf: 18, targetBf: 14, weightChangeKg: -2),
      ),
      isNull,
    );
  });
}

DreamPhysiqueAnalysisSummary _summary({
  required double currentBf,
  required double targetBf,
  required double weightChangeKg,
}) => DreamPhysiqueAnalysisSummary(
  schemaVersion: 1,
  analyzedAt: DateTime.utc(2026, 9, 11),
  targetAestheticStyle: 'Athletic',
  timeframeRange: '12 months',
  estimatedMonths: 12,
  targetBfPercent: targetBf,
  currentEstimatedBf: currentBf,
  weightChangeKg: weightChangeKg,
  currentPhotoCount: 0,
  targetPhotoCount: 0,
);
