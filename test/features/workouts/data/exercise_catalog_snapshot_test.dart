import 'package:flutter_test/flutter_test.dart';
import 'package:herculex/data/local/database.dart';
import 'package:herculex/features/workouts/data/workouts_repository.dart';

ExerciseCatalogData _exercise({
  required int id,
  required String name,
  required String primaryMuscle,
  String equipment = 'barbell',
}) => ExerciseCatalogData(
  id: id,
  name: name,
  primaryMuscle: primaryMuscle,
  equipment: equipment,
  mechanics: 'compound',
  force: 'push',
  plane: 'horizontal',
  defaultRestSeconds: 90,
  isCustom: false,
  category: 'strength',
  modality: 'barbell',
  cnsScore: 3,
  recoveryImpact: 3,
  loggingMetric: 'weight_reps',
  supportsWeightedBodyweight: false,
  isReviewed: true,
  programmingDifficulty: 'intermediate',
  programmingCommonness: 'basic',
  allowedTrainingStyles: '[]',
  technicalEligibility: 'automatic',
);

ExerciseMuscleData _muscle(
  int id,
  int exerciseId,
  String muscle,
  String role,
) => ExerciseMuscleData(
  id: id,
  exerciseId: exerciseId,
  muscle: muscle,
  role: role,
  contribution: role == 'primary' ? 1.0 : 0.5,
);

void main() {
  test(
    'Chest filter excludes positional-name and unrelated exercises and sorts by chest focus',
    () {
      // Deliberately put secondary/multi-primary/false-positives before sole primary.
      final snapshot = ExerciseCatalogSnapshot.from(
        [
          _exercise(id: 1, name: 'Cable Crunch', primaryMuscle: 'Abs', equipment: 'cable'),
          _exercise(
            id: 2,
            name: 'Chest-Supported Dumbbell Row',
            primaryMuscle: 'Back',
            equipment: 'dumbbell',
          ),
          _exercise(
            id: 3,
            name: 'Dumbbell Pullover',
            primaryMuscle: 'Lats',
            equipment: 'dumbbell',
          ),
          _exercise(
            id: 4,
            name: 'Dip',
            primaryMuscle: 'Chest',
            equipment: 'bodyweight',
          ),
          _exercise(
            id: 5,
            name: 'Barbell Bench Press',
            primaryMuscle: 'Chest',
            equipment: 'barbell',
          ),
          _exercise(
            id: 6,
            name: 'Man Maker',
            primaryMuscle: 'Shoulders',
            equipment: 'dumbbell',
          ),
        ],
        [
          _muscle(1, 1, 'Abs', 'primary'),
          _muscle(2, 1, 'Obliques', 'secondary'),
          _muscle(3, 2, 'Lats', 'primary'),
          _muscle(4, 2, 'Rhomboids', 'primary'),
          _muscle(5, 3, 'Lats', 'primary'),
          _muscle(6, 3, 'Chest', 'secondary'),
          _muscle(7, 4, 'Chest', 'primary'),
          _muscle(8, 4, 'Triceps', 'primary'),
          _muscle(9, 5, 'Chest', 'primary'),
          _muscle(10, 5, 'Triceps', 'secondary'),
          _muscle(11, 6, 'Shoulders', 'primary'),
          _muscle(12, 6, 'Chest', 'primary'),
        ],
      );

      final chestResults = snapshot
          .select(category: 'Chest')
          .map((e) => e.name)
          .toList();

      expect(chestResults, [
        'Barbell Bench Press', // sole primary chest (rank 0)
        'Dip', // headline chest shared primary (rank 1)
        'Man Maker', // non-headline primary chest (rank 2)
        'Dumbbell Pullover', // secondary chest (rank 3)
      ]);
      expect(chestResults, isNot(contains('Cable Crunch')));
      expect(chestResults, isNot(contains('Chest-Supported Dumbbell Row')));
    },
  );

  test(
    'Core and Abs filters exclude cable exercises without core involvement and stabilizers',
    () {
      final snapshot = ExerciseCatalogSnapshot.from(
        [
          _exercise(id: 1, name: 'Cable Fly', primaryMuscle: 'Chest', equipment: 'cable'),
          _exercise(id: 2, name: 'Barbell Row', primaryMuscle: 'Back'),
          _exercise(id: 3, name: 'Cable Crunch', primaryMuscle: 'Abs', equipment: 'cable'),
        ],
        [
          _muscle(1, 1, 'Chest', 'primary'),
          // Stabilizer core must not qualify Cable Fly as a Core exercise.
          _muscle(2, 1, 'Core', 'stabilizer'),
          _muscle(3, 2, 'Lats', 'primary'),
          _muscle(4, 2, 'Abs', 'stabilizer'),
          _muscle(5, 3, 'Abs', 'primary'),
        ],
      );

      expect(
        snapshot.select(category: 'Core').map((e) => e.name).toList(),
        ['Cable Crunch'],
      );
      expect(
        snapshot.select(category: 'Abs').map((e) => e.name).toList(),
        ['Cable Crunch'],
      );
    },
  );
}
