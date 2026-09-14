import 'package:herculex/features/nutrition/domain/diet_phase.dart';
import 'package:herculex/features/profile/data/dream_physique_summary_repository.dart';
import 'package:herculex/features/profile/domain/profile.dart';

/// A non-clinical planning direction the member can accept, change, or ignore.
///
/// This is intentionally separate from the active nutrition target. Selecting
/// it never changes calories or macros; that remains an explicit action in the
/// nutrition target editor.
enum PhysiqueNutritionDirection {
  recomp('Recomp'),
  maingain('Maingain'),
  cut('Cut'),
  bulk('Bulk');

  const PhysiqueNutritionDirection(this.label);

  final String label;

  String get shortDescription => switch (this) {
    PhysiqueNutritionDirection.recomp =>
      'Keep body weight broadly steady while building training consistency.',
    PhysiqueNutritionDirection.maingain =>
      'Use a small, controlled surplus for gradual muscle gain.',
    PhysiqueNutritionDirection.cut =>
      'Use a measured deficit to move toward a leaner target.',
    PhysiqueNutritionDirection.bulk =>
      'Prioritize a larger weight-gain phase before a later refinement.',
  };

  /// The matching [DietPhase] in the nutrition target editor, so choosing a
  /// direction here and tapping "Set targets" opens the editor already on
  /// the right phase instead of always falling back to Maintain.
  DietPhase get dietPhase => switch (this) {
    PhysiqueNutritionDirection.recomp => DietPhase.recomp,
    PhysiqueNutritionDirection.maingain => DietPhase.maingain,
    PhysiqueNutritionDirection.cut => DietPhase.cut,
    PhysiqueNutritionDirection.bulk => DietPhase.bulk,
  };
}

/// The explainable output for the optional Dream Physique nutrition card.
class DreamPhysiqueNutritionRecommendation {
  const DreamPhysiqueNutritionRecommendation({
    required this.direction,
    required this.reasons,
  });

  final PhysiqueNutritionDirection direction;
  final List<String> reasons;
}

/// A deliberately small, deterministic heuristic. It only reads fields the
/// user has already saved in their Profile and Dream Physique summary; it does
/// not inspect images, infer health status, or make medical recommendations.
class DreamPhysiqueNutritionRecommender {
  const DreamPhysiqueNutritionRecommender._();

  static DreamPhysiqueNutritionRecommendation? recommend({
    required Profile? profile,
    required DreamPhysiqueAnalysisSummary? summary,
  }) {
    if (profile == null || summary == null) return null;

    final weightKg = profile.weightKg;
    final currentBf = summary.currentEstimatedBf;
    final targetBf = summary.targetBfPercent;
    if (weightKg == null ||
        weightKg <= 0 ||
        currentBf <= 0 ||
        currentBf >= 70 ||
        targetBf <= 0 ||
        targetBf >= 70) {
      return null;
    }

    final bfGap = currentBf - targetBf;
    final plannedWeightChange = summary.weightChangeKg;
    final absChange = plannedWeightChange.abs();

    if (bfGap >= 5 || (profile.goal == FitnessGoal.weightLoss && bfGap >= 2)) {
      return DreamPhysiqueNutritionRecommendation(
        direction: PhysiqueNutritionDirection.cut,
        reasons: [
          'Your saved estimate is ${bfGap.toStringAsFixed(0)} percentage points above the target.',
          'The Dream Physique roadmap estimates ${_weightChangeText(plannedWeightChange)}.',
        ],
      );
    }

    if (plannedWeightChange >= 6 && bfGap <= 2) {
      return DreamPhysiqueNutritionRecommendation(
        direction: PhysiqueNutritionDirection.bulk,
        reasons: [
          'Your roadmap calls for a meaningful gain of ${plannedWeightChange.toStringAsFixed(1)} kg.',
          'Your saved body-fat estimate is already close to the target range.',
        ],
      );
    }

    if (bfGap >= 2 || absChange <= 3) {
      return DreamPhysiqueNutritionRecommendation(
        direction: PhysiqueNutritionDirection.recomp,
        reasons: [
          bfGap >= 2
              ? 'Your current estimate is moderately above the target, so a slower transition may be easier to sustain.'
              : 'The roadmap calls for a relatively small scale-weight change.',
          'This keeps the next phase flexible while you review training and progress data.',
        ],
      );
    }

    return DreamPhysiqueNutritionRecommendation(
      direction: PhysiqueNutritionDirection.maingain,
      reasons: [
        'Your saved estimate is close to the target range.',
        'The roadmap suggests ${_weightChangeText(plannedWeightChange)}, which fits a gradual gain phase.',
      ],
    );
  }

  static String _weightChangeText(double changeKg) {
    if (changeKg == 0) return 'little scale-weight change';
    final amount = changeKg.abs().toStringAsFixed(1);
    return changeKg > 0
        ? 'about $amount kg of gain'
        : 'about $amount kg of loss';
  }
}
