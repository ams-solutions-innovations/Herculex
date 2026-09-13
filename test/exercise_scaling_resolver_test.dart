import 'package:flutter_test/flutter_test.dart';
import 'package:herculex/data/local/database.dart';
import 'package:herculex/features/programs/domain/exercise_scaling_resolver.dart';
import 'package:herculex/features/programs/domain/programming_models.dart';

ExerciseCatalogData _makeExercise({
  required int id,
  required String slug,
  required String name,
  String? movementSlug,
  String programmingDifficulty = 'novice',
  String programmingCommonness = 'basic',
  String allowedTrainingStyles = '["basic", "calisthenics"]',
  String technicalEligibility = 'automatic',
  String? prerequisiteSlugs,
  String? scalingGroup,
  int? scalingOrder,
  String? requiredEquipmentKeys,
  String modality = 'bodyweight',
}) {
  return ExerciseCatalogData(
    id: id,
    slug: slug,
    name: name,
    primaryMuscle: 'back',
    equipment: 'bodyweight',
    mechanics: 'compound',
    force: 'pull',
    plane: 'vertical',
    defaultRestSeconds: 120,
    isCustom: false,
    category: 'calisthenics',
    modality: modality,
    cnsScore: 3,
    recoveryImpact: 3,
    loggingMetric: 'weight_reps',
    supportsWeightedBodyweight: true,
    isReviewed: true,
    movementSlug: movementSlug,
    programmingDifficulty: programmingDifficulty,
    programmingCommonness: programmingCommonness,
    allowedTrainingStyles: allowedTrainingStyles,
    technicalEligibility: technicalEligibility,
    prerequisiteSlugs: prerequisiteSlugs,
    scalingGroup: scalingGroup,
    scalingOrder: scalingOrder,
    requiredEquipmentKeys: requiredEquipmentKeys,
  );
}

void main() {
  group('ExerciseScalingResolver', () {
    const resolver = ExerciseScalingResolver();

    // Setup vertical_pull ladder matching curated catalog
    final assistedMachine = _makeExercise(
      id: 1,
      slug: 'assisted-pull-up-machine-wide-grip',
      name: 'Assisted Pull-Up Machine (Wide Grip)',
      movementSlug: 'pull-up-vertical-pull',
      scalingGroup: 'vertical_pull',
      scalingOrder: 1,
      programmingDifficulty: 'novice',
      programmingCommonness: 'basic',
      allowedTrainingStyles: '["basic", "calisthenics", "weightlifting"]',
      modality: 'machine_selectorized',
      requiredEquipmentKeys: '["assisted_pull_up_machine"]',
    );

    final bandAssisted = _makeExercise(
      id: 2,
      slug: 'band-assisted-pull-up-wide-grip',
      name: 'Band-Assisted Pull-Up (Wide Grip)',
      movementSlug: 'pull-up-vertical-pull',
      scalingGroup: 'vertical_pull',
      scalingOrder: 2,
      programmingDifficulty: 'novice',
      programmingCommonness: 'basic',
      allowedTrainingStyles: '["basic", "calisthenics"]',
      modality: 'bodyweight',
      requiredEquipmentKeys: '["pull_up_bar", "resistance_band"]',
    );

    final negativePullUp = _makeExercise(
      id: 3,
      slug: 'negative-pull-up',
      name: 'Negative Pull-Up',
      movementSlug: 'pull-up-vertical-pull',
      scalingGroup: 'vertical_pull',
      scalingOrder: 3,
      programmingDifficulty: 'novice',
      programmingCommonness: 'basic',
      allowedTrainingStyles: '["basic", "calisthenics"]',
      modality: 'bodyweight',
      requiredEquipmentKeys: '["pull_up_bar"]',
    );

    final pullUp = _makeExercise(
      id: 4,
      slug: 'pull-up',
      name: 'Pull-Up',
      movementSlug: 'pull-up-vertical-pull',
      scalingGroup: 'vertical_pull',
      scalingOrder: 4,
      programmingDifficulty: 'intermediate',
      programmingCommonness: 'basic',
      allowedTrainingStyles: '["basic", "calisthenics"]',
      modality: 'bodyweight',
      requiredEquipmentKeys: '["pull_up_bar"]',
    );

    final chestToBar = _makeExercise(
      id: 5,
      slug: 'chest-to-bar-pull-up',
      name: 'Chest-to-Bar Pull-Up',
      movementSlug: 'pull-up-vertical-pull',
      scalingGroup: 'vertical_pull',
      scalingOrder: 5,
      programmingDifficulty: 'intermediate',
      programmingCommonness: 'common',
      allowedTrainingStyles: '["calisthenics", "crossfit"]',
      modality: 'bodyweight',
      requiredEquipmentKeys: '["pull_up_bar"]',
      prerequisiteSlugs: '["pull-up"]',
    );

    final barMuscleUp = _makeExercise(
      id: 6,
      slug: 'bar-muscle-up',
      name: 'Bar Muscle-Up',
      movementSlug: 'muscle-up-vertical-pull',
      scalingGroup: 'vertical_pull',
      scalingOrder: 6,
      programmingDifficulty: 'advanced',
      programmingCommonness: 'specialty',
      technicalEligibility: 'manual_only',
      allowedTrainingStyles: '["calisthenics", "crossfit"]',
      modality: 'bodyweight',
      requiredEquipmentKeys: '["pull_up_bar"]',
      prerequisiteSlugs: '["pull-up", "chest-dips"]',
    );

    final ringMuscleUp = _makeExercise(
      id: 7,
      slug: 'ring-muscle-up',
      name: 'Ring Muscle-Up',
      movementSlug: 'muscle-up-vertical-pull',
      scalingGroup: 'vertical_pull',
      scalingOrder: 7,
      programmingDifficulty: 'advanced',
      programmingCommonness: 'specialty',
      technicalEligibility: 'manual_only',
      allowedTrainingStyles: '["calisthenics"]',
      modality: 'bodyweight',
      requiredEquipmentKeys: '["gymnastic_rings"]',
      prerequisiteSlugs: '["pull-up", "chest-dips"]',
    );

    final ladderCandidates = [
      assistedMachine,
      bandAssisted,
      negativePullUp,
      pullUp,
      chestToBar,
      barMuscleUp,
      ringMuscleUp,
    ];

    final catalogBySlug = {
      for (final candidate in ladderCandidates) candidate.slug!: candidate,
    };

    test(
      'intermediate athlete under basic style regresses from ring-muscle-up to pull-up (order 4)',
      () {
        final result = resolver.regress(
          target: ringMuscleUp,
          groupCandidates: ladderCandidates,
          experience: ExperienceLevel.intermediate,
          style: TrainingStyle.basic,
          availableEquipmentKeys: {'pull_up_bar', 'gymnastic_rings'},
          completedExerciseSlugs: {},
          completedMovementSlugs: {},
          catalogBySlug: catalogBySlug,
        );

        expect(result.isSuccess, isTrue);
        expect(result.candidate, isNotNull);
        expect(result.candidate!.slug, 'pull-up');
        expect(result.candidate!.scalingOrder, 4);
        expect(
          result.rationale,
          contains('Regressed from Ring Muscle-Up (order 7) to Pull-Up (order 4)'),
        );
      },
    );

    test(
      'novice athlete regresses from ring-muscle-up to negative-pull-up (order 3) when pull_up_bar is available',
      () {
        final result = resolver.regress(
          target: ringMuscleUp,
          groupCandidates: ladderCandidates,
          experience: ExperienceLevel.novice,
          style: TrainingStyle.basic,
          availableEquipmentKeys: {'pull_up_bar'},
          completedExerciseSlugs: {},
          completedMovementSlugs: {},
          catalogBySlug: catalogBySlug,
        );

        expect(result.isSuccess, isTrue);
        expect(result.candidate, isNotNull);
        expect(result.candidate!.slug, 'negative-pull-up');
        expect(result.candidate!.scalingOrder, 3);
        expect(
          result.rationale,
          contains(
            'Regressed from Ring Muscle-Up (order 7) to Negative Pull-Up (order 3)',
          ),
        );
      },
    );

    test(
      'novice athlete regresses from ring-muscle-up to assisted-pull-up-machine (order 1) when only machine is available',
      () {
        final result = resolver.regress(
          target: ringMuscleUp,
          groupCandidates: ladderCandidates,
          experience: ExperienceLevel.novice,
          style: TrainingStyle.basic,
          availableEquipmentKeys: {'assisted_pull_up_machine'},
          completedExerciseSlugs: {},
          completedMovementSlugs: {},
          catalogBySlug: catalogBySlug,
        );

        expect(result.isSuccess, isTrue);
        expect(result.candidate, isNotNull);
        expect(result.candidate!.slug, 'assisted-pull-up-machine-wide-grip');
        expect(result.candidate!.scalingOrder, 1);
        expect(
          result.rationale,
          contains(
            'Regressed from Ring Muscle-Up (order 7) to Assisted Pull-Up Machine (Wide Grip) (order 1)',
          ),
        );
      },
    );

    test(
      'strict boundary enforcement (D-16): returns noSafeCandidate when all ladder equipment is missing',
      () {
        final result = resolver.regress(
          target: ringMuscleUp,
          groupCandidates: ladderCandidates,
          experience: ExperienceLevel.intermediate,
          style: TrainingStyle.basic,
          availableEquipmentKeys: {'barbell', 'dumbbell'}, // no pull up equipment
          completedExerciseSlugs: {},
          completedMovementSlugs: {},
          catalogBySlug: catalogBySlug,
        );

        expect(result.isSuccess, isFalse);
        expect(result.candidate, isNull);
        expect(
          result.rationale,
          contains('No safe candidate found in scaling ladder "vertical_pull"'),
        );
      },
    );

    test(
      'exercise not belonging to any ladder returns noSafeCandidate',
      () {
        final standalone = _makeExercise(
          id: 99,
          slug: 'custom-lateral-raise',
          name: 'Custom Lateral Raise',
          scalingGroup: null,
          scalingOrder: null,
        );

        final result = resolver.regress(
          target: standalone,
          groupCandidates: ladderCandidates,
          experience: ExperienceLevel.intermediate,
          style: TrainingStyle.basic,
          availableEquipmentKeys: {'dumbbell'},
          completedExerciseSlugs: {},
          completedMovementSlugs: {},
          catalogBySlug: catalogBySlug,
        );

        expect(result.isSuccess, isFalse);
        expect(result.candidate, isNull);
        expect(
          result.rationale,
          contains('Custom Lateral Raise does not belong to a scaling ladder.'),
        );
      },
    );

    test(
      'lowest ladder candidate (order 1) returns noSafeCandidate when regressed',
      () {
        final result = resolver.regress(
          target: assistedMachine,
          groupCandidates: ladderCandidates,
          experience: ExperienceLevel.novice,
          style: TrainingStyle.basic,
          availableEquipmentKeys: {'assisted_pull_up_machine'},
          completedExerciseSlugs: {},
          completedMovementSlugs: {},
          catalogBySlug: catalogBySlug,
        );

        expect(result.isSuccess, isFalse);
        expect(result.candidate, isNull);
        expect(
          result.rationale,
          contains('No safe candidate found in scaling ladder "vertical_pull"'),
        );
      },
    );
  });
}
