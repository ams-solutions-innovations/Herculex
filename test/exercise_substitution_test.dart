import 'package:flutter_test/flutter_test.dart';
import 'package:herculex/data/local/database.dart';
import 'package:herculex/features/workouts/domain/exercise_substitution.dart';

void main() {
  ExerciseCatalogData createExercise({
    required int id,
    required String name,
    required String primaryMuscle,
    required String mechanics,
    required String force,
    required String plane,
    String equipment = 'Cable',
    String? movementSlug,
    String? movementFamily,
    String? movementPattern,
  }) {
    return ExerciseCatalogData(
      id: id,
      name: name,
      primaryMuscle: primaryMuscle,
      equipment: equipment,
      mechanics: mechanics,
      force: force,
      plane: plane,
      defaultRestSeconds: 90,
      isCustom: false,
      category: 'hypertrophy',
      modality: 'resistance',
      cnsScore: 3,
      recoveryImpact: 2,
      loggingMetric: 'reps_weight',
      supportsWeightedBodyweight: false,
      isReviewed: true,
      movementSlug: movementSlug,
      movementFamily: movementFamily,
      movementPattern: movementPattern,
    );
  }

  group('ExerciseSubstitution - Biomechanical Matching', () {
    final cableFly = createExercise(
      id: 1,
      name: 'Cable Fly (High to Low)',
      primaryMuscle: 'Chest',
      mechanics: 'isolation',
      force: 'push',
      plane: 'horizontal',
      equipment: 'Cable',
      movementSlug: 'fly-isolation',
      movementFamily: 'cable-fly',
      movementPattern: 'isolation',
    );

    final pecDeck = createExercise(
      id: 2,
      name: 'Pec Deck Machine Fly',
      primaryMuscle: 'Chest',
      mechanics: 'isolation',
      force: 'push',
      plane: 'horizontal',
      equipment: 'Machine',
      movementSlug: 'fly-isolation',
      movementFamily: 'machine-fly',
      movementPattern: 'isolation',
    );

    final dumbbellFly = createExercise(
      id: 3,
      name: 'Dumbbell Fly',
      primaryMuscle: 'Chest',
      mechanics: 'isolation',
      force: 'push',
      plane: 'horizontal',
      equipment: 'Dumbbell',
      movementSlug: 'fly-isolation',
      movementFamily: 'dumbbell-fly',
      movementPattern: 'isolation',
    );

    final dumbbellBench = createExercise(
      id: 4,
      name: 'Dumbbell Bench Press',
      primaryMuscle: 'Chest',
      mechanics: 'compound',
      force: 'push',
      plane: 'horizontal',
      equipment: 'Dumbbell',
      movementSlug: 'bench-press',
      movementPattern: 'horizontal_push',
    );

    final legExtension = createExercise(
      id: 5,
      name: 'Leg Extension',
      primaryMuscle: 'Quads',
      mechanics: 'isolation',
      force: 'push',
      plane: 'axial',
      equipment: 'Machine',
      movementSlug: 'leg-extension',
      movementPattern: 'isolation',
    );

    final luRaise = createExercise(
      id: 6,
      name: 'Lu Raise',
      primaryMuscle: 'Shoulders',
      mechanics: 'isolation',
      force: 'push',
      plane: 'frontal',
      equipment: 'Dumbbell',
      movementSlug: 'lateral-raise',
      movementPattern: 'isolation',
    );

    final seatedLatRaise = createExercise(
      id: 7,
      name: 'Seated Lateral Raise',
      primaryMuscle: 'Shoulders',
      mechanics: 'isolation',
      force: 'push',
      plane: 'frontal',
      equipment: 'Machine',
      movementSlug: 'lateral-raise',
      movementPattern: 'isolation',
    );

    test('Cable Fly strongly matches Pec Deck and Dumbbell Fly', () {
      final candidates = [
        legExtension,
        luRaise,
        seatedLatRaise,
        dumbbellBench,
        dumbbellFly,
        pecDeck,
      ];

      // Even if user recently logged leg extension and lateral raise:
      final recentIds = {legExtension.id, luRaise.id, seatedLatRaise.id};

      final ranked = ExerciseSubstitution.getRankedSubstitutes(
        original: cableFly,
        candidates: candidates,
        recentExerciseIds: recentIds,
      );

      // Leg extension and lateral raises must be completely excluded!
      expect(ranked.any((r) => r.exercise.name == 'Leg Extension'), isFalse);
      expect(ranked.any((r) => r.exercise.name == 'Lu Raise'), isFalse);
      expect(ranked.any((r) => r.exercise.name == 'Seated Lateral Raise'), isFalse);

      // Chest exercises must be at the top
      expect(ranked.first.exercise.primaryMuscle, 'Chest');
      expect(ranked.first.percentage, greaterThanOrEqualTo(90));
      final names = ranked.map((r) => r.exercise.name).toList();
      expect(names.contains('Dumbbell Fly'), isTrue);
      expect(names.contains('Pec Deck Machine Fly'), isTrue);
      expect(names.contains('Dumbbell Bench Press'), isTrue);
      expect(names.indexOf('Dumbbell Bench Press'), greaterThan(names.indexOf('Dumbbell Fly')));
    });

    test('Strict exclusion of wrong muscles for isolation exercises', () {
      final match = ExerciseSubstitution.calculateMatch(
        original: cableFly,
        candidate: legExtension,
        recentExerciseIds: {legExtension.id},
      );

      expect(match['percentage'], 0.0);
      expect(match['score'], 0.0);
    });

    test('Compound exercises allow synergistic compound substitutes but rank primary muscle higher', () {
      final barbellBench = createExercise(
        id: 10,
        name: 'Barbell Bench Press',
        primaryMuscle: 'Chest',
        mechanics: 'compound',
        force: 'push',
        plane: 'horizontal',
        equipment: 'Barbell',
        movementSlug: 'bench-press',
        movementPattern: 'horizontal_push',
      );

      final dips = createExercise(
        id: 11,
        name: 'Dips',
        primaryMuscle: 'Triceps',
        mechanics: 'compound',
        force: 'push',
        plane: 'vertical',
        equipment: 'Bodyweight',
        movementPattern: 'vertical_push',
      );

      final squat = createExercise(
        id: 12,
        name: 'Barbell Squat',
        primaryMuscle: 'Quads',
        mechanics: 'compound',
        force: 'push',
        plane: 'axial',
        equipment: 'Barbell',
        movementPattern: 'squat',
      );

      final ranked = ExerciseSubstitution.getRankedSubstitutes(
        original: barbellBench,
        candidates: [squat, dips, dumbbellBench],
        recentExerciseIds: {},
      );

      // Squat must be excluded
      expect(ranked.any((r) => r.exercise.name == 'Barbell Squat'), isFalse);

      // Dumbbell bench (Chest) ranks above Dips (Triceps compound synergy)
      expect(ranked.first.exercise.name, 'Dumbbell Bench Press');
      expect(ranked.first.percentage, greaterThan(ranked.last.percentage));
    });
  });
}
