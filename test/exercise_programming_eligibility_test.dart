import 'package:flutter_test/flutter_test.dart';
import 'package:herculex/data/local/database.dart';
import 'package:herculex/features/programs/domain/exercise_programming_eligibility.dart';
import 'package:herculex/features/programs/domain/programming_models.dart';

void main() {
  group('ExerciseProgrammingEligibility', () {
    test(
      'a novice calisthenics plan cannot receive advanced manual skills',
      () {
        expect(
          ExerciseProgrammingEligibility.allows(
            experience: ExperienceLevel.novice,
            style: TrainingStyle.calisthenics,
            difficulty: 'advanced',
            commonness: 'specialty',
            allowedTrainingStylesJson: '["calisthenics"]',
            technicalEligibility: 'manual_only',
          ),
          isFalse,
        );
        expect(
          ExerciseProgrammingEligibility.allows(
            experience: ExperienceLevel.novice,
            style: TrainingStyle.calisthenics,
            difficulty: 'novice',
            commonness: 'basic',
            allowedTrainingStylesJson: '["calisthenics"]',
            technicalEligibility: 'automatic',
          ),
          isTrue,
        );
      },
    );

    test('strict novice ceiling bars intermediate and advanced movements', () {
      // Novice is barred from intermediate movements with zero relaxation
      expect(
        ExerciseProgrammingEligibility.allows(
          experience: ExperienceLevel.novice,
          style: TrainingStyle.weightlifting,
          difficulty: 'intermediate',
          commonness: 'basic',
          allowedTrainingStylesJson: '["weightlifting"]',
          technicalEligibility: 'automatic',
        ),
        isFalse,
      );

      // Novice is barred from advanced movements
      expect(
        ExerciseProgrammingEligibility.allows(
          experience: ExperienceLevel.novice,
          style: TrainingStyle.weightlifting,
          difficulty: 'advanced',
          commonness: 'basic',
          allowedTrainingStylesJson: '["weightlifting"]',
          technicalEligibility: 'automatic',
        ),
        isFalse,
      );

      // Novice can only receive novice movements
      expect(
        ExerciseProgrammingEligibility.allows(
          experience: ExperienceLevel.novice,
          style: TrainingStyle.weightlifting,
          difficulty: 'novice',
          commonness: 'basic',
          allowedTrainingStylesJson: '["weightlifting"]',
          technicalEligibility: 'automatic',
        ),
        isTrue,
      );

      // Intermediate can receive novice and intermediate, but not advanced
      expect(
        ExerciseProgrammingEligibility.allows(
          experience: ExperienceLevel.intermediate,
          style: TrainingStyle.weightlifting,
          difficulty: 'novice',
          commonness: 'basic',
          allowedTrainingStylesJson: '["weightlifting"]',
          technicalEligibility: 'automatic',
        ),
        isTrue,
      );
      expect(
        ExerciseProgrammingEligibility.allows(
          experience: ExperienceLevel.intermediate,
          style: TrainingStyle.weightlifting,
          difficulty: 'intermediate',
          commonness: 'basic',
          allowedTrainingStylesJson: '["weightlifting"]',
          technicalEligibility: 'automatic',
        ),
        isTrue,
      );
      expect(
        ExerciseProgrammingEligibility.allows(
          experience: ExperienceLevel.intermediate,
          style: TrainingStyle.weightlifting,
          difficulty: 'advanced',
          commonness: 'basic',
          allowedTrainingStylesJson: '["weightlifting"]',
          technicalEligibility: 'automatic',
        ),
        isFalse,
      );
    });

    test('two-layer basicWeights hard gate: commonness & modality/equipment', () {
      // Allows standard barbell/dumbbell/cable/machine with basic or common
      for (final modality in const [
        'barbell',
        'dumbbell',
        'cable',
        'machine_plate',
        'machine_selectorized',
        'bodyweight',
      ]) {
        for (final commonness in const ['basic', 'common']) {
          expect(
            ExerciseProgrammingEligibility.allows(
              experience: ExperienceLevel.intermediate,
              style: TrainingStyle.basic,
              difficulty: 'intermediate',
              commonness: commonness,
              allowedTrainingStylesJson: '["basic"]',
              technicalEligibility: 'automatic',
              modality: modality,
              requiredEquipmentKeysJson: '["$modality"]',
            ),
            isTrue,
            reason: '$modality with $commonness should pass basic style',
          );
        }
      }

      // Layer 1: Blocks movements with specialty commonness (even if using standard barbell)
      expect(
        ExerciseProgrammingEligibility.allows(
          experience: ExperienceLevel.advanced,
          style: TrainingStyle.basic,
          difficulty: 'intermediate',
          commonness: 'specialty',
          allowedTrainingStylesJson: '["basic"]',
          technicalEligibility: 'automatic',
          modality: 'barbell',
          requiredEquipmentKeysJson: '["barbell"]',
        ),
        isFalse,
      );

      // Layer 1: Blocks manualOnly commonness
      expect(
        ExerciseProgrammingEligibility.allows(
          experience: ExperienceLevel.advanced,
          style: TrainingStyle.basic,
          difficulty: 'novice',
          commonness: 'manualOnly',
          allowedTrainingStylesJson: '["basic"]',
          technicalEligibility: 'automatic',
          modality: 'barbell',
          requiredEquipmentKeysJson: '["barbell"]',
        ),
        isFalse,
      );

      // Layer 2: Blocks disallowed modality (e.g. suspension)
      expect(
        ExerciseProgrammingEligibility.allows(
          experience: ExperienceLevel.intermediate,
          style: TrainingStyle.basic,
          difficulty: 'intermediate',
          commonness: 'basic',
          allowedTrainingStylesJson: '["basic"]',
          technicalEligibility: 'automatic',
          modality: 'suspension',
          requiredEquipmentKeysJson: '["suspension"]',
        ),
        isFalse,
      );

      // Layer 2: Blocks movements with specialty bars even if commonness was marked basic
      for (final barredKey in const [
        'safety_squat_bar',
        'swiss_bar',
        'cambered_bar',
        'axle_bar',
        'trap_bar',
        'duffalo_bar',
        'chains',
        'reverse_hyper',
        'ghr',
        'belt_squat',
      ]) {
        expect(
          ExerciseProgrammingEligibility.allows(
            experience: ExperienceLevel.advanced,
            style: TrainingStyle.basic,
            difficulty: 'intermediate',
            commonness: 'basic',
            allowedTrainingStylesJson: '["basic"]',
            technicalEligibility: 'automatic',
            modality: 'barbell',
            requiredEquipmentKeysJson: '["$barredKey"]',
          ),
          isFalse,
          reason: '$barredKey must be blocked under basic style',
        );
      }
    });

    test(
      'mixed style accepts either curated calisthenics or weightlifting',
      () {
        for (final style in const ['calisthenics', 'weightlifting']) {
          expect(
            ExerciseProgrammingEligibility.allows(
              experience: ExperienceLevel.intermediate,
              style: TrainingStyle.mixedCalisthenicsWeights,
              difficulty: 'intermediate',
              commonness: 'basic',
              allowedTrainingStylesJson: '["$style"]',
              technicalEligibility: 'automatic',
            ),
            isTrue,
            reason: '$style should be valid for the mixed profile',
          );
        }
      },
    );

    test(
      'missing metadata stays blocked rather than silently entering a plan',
      () {
        expect(
          ExerciseProgrammingEligibility.allows(
            experience: ExperienceLevel.advanced,
            style: TrainingStyle.weightlifting,
            difficulty: null,
            commonness: null,
            allowedTrainingStylesJson: null,
            technicalEligibility: null,
          ),
          isFalse,
        );
      },
    );

    group('excludedMuscles hard gate (D-06)', () {
      bool allowsWith({String? primaryMuscle, Set<String> excludedMuscles = const {}}) =>
          ExerciseProgrammingEligibility.allows(
            experience: ExperienceLevel.advanced,
            style: TrainingStyle.weightlifting,
            difficulty: 'novice',
            commonness: 'basic',
            allowedTrainingStylesJson: '["weightlifting"]',
            technicalEligibility: 'automatic',
            primaryMuscle: primaryMuscle,
            excludedMuscles: excludedMuscles,
          );

      test(
        'a flagged primaryMuscle is hard-excluded even when every other check would allow it',
        () {
          expect(
            allowsWith(
              primaryMuscle: 'Triceps',
              excludedMuscles: {'Triceps'},
            ),
            isFalse,
          );
        },
      );

      test('a non-excluded primaryMuscle is unaffected by the exclusion set', () {
        expect(
          allowsWith(primaryMuscle: 'Chest', excludedMuscles: {'Triceps'}),
          isTrue,
        );
      });

      test(
        'a null primaryMuscle never participates in this gate either way',
        () {
          expect(
            allowsWith(primaryMuscle: null, excludedMuscles: {'Triceps'}),
            isTrue,
          );
        },
      );
    });

    group('verifyPrerequisites', () {
      final pullUp = _makeCatalogEntry(
        id: 1,
        slug: 'pull-up',
        name: 'Pull-Up',
        movementSlug: 'pull-up-vertical-pull',
        programmingDifficulty: 'intermediate',
        programmingCommonness: 'basic',
      );

      final chestDips = _makeCatalogEntry(
        id: 2,
        slug: 'chest-dips',
        name: 'Chest Dips',
        movementSlug: 'dip-vertical-push',
        programmingDifficulty: 'intermediate',
        programmingCommonness: 'basic',
      );

      final catalogBySlug = {
        'pull-up': pullUp,
        'chest-dips': chestDips,
      };

      test(
        'advanced user satisfies prerequisite pull-up via Condition (a) experience check',
        () {
          final satisfied = ExerciseProgrammingEligibility.verifyPrerequisites(
            prerequisiteSlugsJson: '["pull-up"]',
            userExperience: ExperienceLevel.advanced,
            completedExerciseSlugs: {},
            completedMovementSlugs: {},
            catalogBySlug: catalogBySlug,
          );
          expect(satisfied, isTrue);
        },
      );

      test('novice user fails prerequisite pull-up when history is empty', () {
        final satisfied = ExerciseProgrammingEligibility.verifyPrerequisites(
          prerequisiteSlugsJson: '["pull-up"]',
          userExperience: ExperienceLevel.novice,
          completedExerciseSlugs: {},
          completedMovementSlugs: {},
          catalogBySlug: catalogBySlug,
        );
        expect(satisfied, isFalse);
      });

      test(
        'novice user satisfies prerequisite pull-up via Condition (b) when completedExerciseSlugs contains pull-up',
        () {
          final satisfied = ExerciseProgrammingEligibility.verifyPrerequisites(
            prerequisiteSlugsJson: '["pull-up"]',
            userExperience: ExperienceLevel.novice,
            completedExerciseSlugs: {'pull-up'},
            completedMovementSlugs: {},
            catalogBySlug: catalogBySlug,
          );
          expect(satisfied, isTrue);
        },
      );

      test(
        'novice user satisfies prerequisite pull-up via Condition (b) when completedMovementSlugs contains pull-up-vertical-pull',
        () {
          final satisfied = ExerciseProgrammingEligibility.verifyPrerequisites(
            prerequisiteSlugsJson: '["pull-up"]',
            userExperience: ExperienceLevel.novice,
            completedExerciseSlugs: {},
            completedMovementSlugs: {'pull-up-vertical-pull'},
            catalogBySlug: catalogBySlug,
          );
          expect(satisfied, isTrue);
        },
      );

      test(
        'multi-prerequisite exercise fails if only one prerequisite is satisfied and the other is unverified',
        () {
          // Novice with pull-up logged, but chest-dips unverified
          final satisfied = ExerciseProgrammingEligibility.verifyPrerequisites(
            prerequisiteSlugsJson: '["pull-up", "chest-dips"]',
            userExperience: ExperienceLevel.novice,
            completedExerciseSlugs: {'pull-up'},
            completedMovementSlugs: {},
            catalogBySlug: catalogBySlug,
          );
          expect(satisfied, isFalse);

          // Novice with both logged succeeds
          final bothSatisfied =
              ExerciseProgrammingEligibility.verifyPrerequisites(
            prerequisiteSlugsJson: '["pull-up", "chest-dips"]',
            userExperience: ExperienceLevel.novice,
            completedExerciseSlugs: {'pull-up', 'chest-dips'},
            completedMovementSlugs: {},
            catalogBySlug: catalogBySlug,
          );
          expect(bothSatisfied, isTrue);
        },
      );

      test('empty or null prerequisites json trivially satisfies check', () {
        expect(
          ExerciseProgrammingEligibility.verifyPrerequisites(
            prerequisiteSlugsJson: null,
            userExperience: ExperienceLevel.novice,
            completedExerciseSlugs: {},
            completedMovementSlugs: {},
            catalogBySlug: catalogBySlug,
          ),
          isTrue,
        );
        expect(
          ExerciseProgrammingEligibility.verifyPrerequisites(
            prerequisiteSlugsJson: '[]',
            userExperience: ExperienceLevel.novice,
            completedExerciseSlugs: {},
            completedMovementSlugs: {},
            catalogBySlug: catalogBySlug,
          ),
          isTrue,
        );
      });
    });
  });
}

ExerciseCatalogData _makeCatalogEntry({
  required int id,
  required String slug,
  required String name,
  String? movementSlug,
  String programmingDifficulty = 'novice',
  String programmingCommonness = 'basic',
  String allowedTrainingStyles = '["basic"]',
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
