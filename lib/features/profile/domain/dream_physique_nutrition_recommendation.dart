import 'package:herculex/features/nutrition/domain/diet_phase.dart';
import 'package:herculex/features/physique/domain/physique_direction.dart';
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

    final decision = PhysiqueDirectionRule.decide(
      weightKg: weightKg,
      currentBfPercent: currentBf,
      targetBfPercent: targetBf,
      plannedWeightChangeKg: summary.weightChangeKg,
      prefersWeightLoss: profile.goal == FitnessGoal.weightLoss,
    );
    if (decision == null) return null;

    return DreamPhysiqueNutritionRecommendation(
      direction: PhysiqueNutritionDirection.values.firstWhere(
        (d) => d.dietPhase == decision.phase,
      ),
      reasons: decision.reasons,
    );
  }
}
