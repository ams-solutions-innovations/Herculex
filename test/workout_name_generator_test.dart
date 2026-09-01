import 'package:flutter_test/flutter_test.dart';
import 'package:herculex/data/local/database.dart';
import 'package:herculex/features/workouts/domain/workout_name_generator.dart';

void main() {
  ExerciseCatalogData makeExercise({
    required int id,
    required String name,
    required String primaryMuscle,
    String force = 'push',
    String category = 'strength',
    String? movementPattern,
  }) {
    return ExerciseCatalogData(
      id: id,
      name: name,
      primaryMuscle: primaryMuscle,
      equipment: 'barbell',
      mechanics: 'compound',
      force: force,
      plane: 'horizontal',
      defaultRestSeconds: 120,
      isCustom: false,
      category: category,
      movementPattern: movementPattern,
      modality: 'barbell',
      cnsScore: 3,
      recoveryImpact: 3,
      loggingMetric: 'weight_reps',
      supportsWeightedBodyweight: false,
      isReviewed: true,
    );
  }

  group('WorkoutNameGenerator', () {
    test('returns Quick Workout for empty exercise list', () {
      expect(WorkoutNameGenerator.generate([]), 'Quick Workout');
    });

    test('returns Arm Day for biceps and triceps', () {
      final exercises = [
        makeExercise(
          id: 1,
          name: 'Barbell Curl',
          primaryMuscle: 'Biceps',
          force: 'pull',
        ),
        makeExercise(
          id: 2,
          name: 'Tricep Pushdown',
          primaryMuscle: 'Triceps',
          force: 'push',
        ),
      ];
      expect(WorkoutNameGenerator.generate(exercises), 'Arm Day');
    });

    test('returns Arms & Abs for biceps, triceps, and abs', () {
      final exercises = [
        makeExercise(
          id: 1,
          name: 'Barbell Curl',
          primaryMuscle: 'Biceps',
          force: 'pull',
        ),
        makeExercise(
          id: 2,
          name: 'Tricep Pushdown',
          primaryMuscle: 'Triceps',
          force: 'push',
        ),
        makeExercise(
          id: 3,
          name: 'Plank',
          primaryMuscle: 'Abs',
          force: 'static',
        ),
      ];
      expect(WorkoutNameGenerator.generate(exercises), 'Arms & Abs');
    });

    test('returns Biceps & Abs for biceps and abs', () {
      final exercises = [
        makeExercise(
          id: 1,
          name: 'Barbell Curl',
          primaryMuscle: 'Biceps',
          force: 'pull',
        ),
        makeExercise(
          id: 2,
          name: 'Hanging Leg Raise',
          primaryMuscle: 'Core',
          force: 'pull',
        ),
      ];
      expect(WorkoutNameGenerator.generate(exercises), 'Biceps & Abs');
    });

    test('returns Triceps & Abs for triceps and abs', () {
      final exercises = [
        makeExercise(
          id: 1,
          name: 'Skull Crusher',
          primaryMuscle: 'Triceps',
          force: 'push',
        ),
        makeExercise(
          id: 2,
          name: 'Cable Crunch',
          primaryMuscle: 'Abs',
          force: 'pull',
        ),
      ];
      expect(WorkoutNameGenerator.generate(exercises), 'Triceps & Abs');
    });

    test('returns Chest & Abs for chest and abs', () {
      final exercises = [
        makeExercise(
          id: 1,
          name: 'Bench Press',
          primaryMuscle: 'Chest',
          force: 'push',
        ),
        makeExercise(
          id: 2,
          name: 'Incline Dumbbell Press',
          primaryMuscle: 'Chest',
          force: 'push',
        ),
        makeExercise(
          id: 3,
          name: 'Cable Crunch',
          primaryMuscle: 'Abs',
          force: 'pull',
        ),
      ];
      expect(WorkoutNameGenerator.generate(exercises), 'Chest & Abs');
    });

    test('returns Back & Abs for back and abs', () {
      final exercises = [
        makeExercise(
          id: 1,
          name: 'Barbell Row',
          primaryMuscle: 'Back',
          force: 'pull',
        ),
        makeExercise(
          id: 2,
          name: 'Lat Pulldown',
          primaryMuscle: 'Lats',
          force: 'pull',
        ),
        makeExercise(
          id: 3,
          name: 'Plank',
          primaryMuscle: 'Abs',
          force: 'static',
        ),
      ];
      expect(WorkoutNameGenerator.generate(exercises), 'Back & Abs');
    });

    test('returns Shoulders & Abs for shoulders and abs', () {
      final exercises = [
        makeExercise(
          id: 1,
          name: 'Overhead Press',
          primaryMuscle: 'Shoulders',
          force: 'push',
        ),
        makeExercise(
          id: 2,
          name: 'Lateral Raise',
          primaryMuscle: 'Shoulders',
          force: 'push',
        ),
        makeExercise(
          id: 3,
          name: 'Hanging Leg Raise',
          primaryMuscle: 'Core',
          force: 'pull',
        ),
      ];
      expect(WorkoutNameGenerator.generate(exercises), 'Shoulders & Abs');
    });

    test('returns Legs & Abs for legs and abs', () {
      final exercises = [
        makeExercise(
          id: 1,
          name: 'Barbell Squat',
          primaryMuscle: 'Quads',
          force: 'push',
        ),
        makeExercise(
          id: 2,
          name: 'Romanian Deadlift',
          primaryMuscle: 'Hamstrings',
          force: 'pull',
        ),
        makeExercise(
          id: 3,
          name: 'Plank',
          primaryMuscle: 'Abs',
          force: 'static',
        ),
      ];
      expect(WorkoutNameGenerator.generate(exercises), 'Legs & Abs');
    });

    test('returns Glutes & Abs for glutes and abs', () {
      final exercises = [
        makeExercise(
          id: 1,
          name: 'Hip Thrust',
          primaryMuscle: 'Glutes',
          force: 'push',
        ),
        makeExercise(
          id: 2,
          name: 'Cable Crunch',
          primaryMuscle: 'Abs',
          force: 'pull',
        ),
      ];
      expect(WorkoutNameGenerator.generate(exercises), 'Glutes & Abs');
    });

    test('returns Push & Abs when push day includes abs', () {
      final exercises = [
        makeExercise(
          id: 1,
          name: 'Bench Press',
          primaryMuscle: 'Chest',
          force: 'push',
        ),
        makeExercise(
          id: 2,
          name: 'Overhead Press',
          primaryMuscle: 'Shoulders',
          force: 'push',
        ),
        makeExercise(
          id: 3,
          name: 'Tricep Pushdown',
          primaryMuscle: 'Triceps',
          force: 'push',
        ),
        makeExercise(
          id: 4,
          name: 'Plank',
          primaryMuscle: 'Abs',
          force: 'static',
        ),
      ];
      expect(WorkoutNameGenerator.generate(exercises), 'Push & Abs');
    });

    test('returns Pull & Abs when pull day includes abs', () {
      final exercises = [
        makeExercise(
          id: 1,
          name: 'Barbell Row',
          primaryMuscle: 'Back',
          force: 'pull',
        ),
        makeExercise(
          id: 2,
          name: 'Lat Pulldown',
          primaryMuscle: 'Lats',
          force: 'pull',
        ),
        makeExercise(
          id: 3,
          name: 'Face Pull',
          primaryMuscle: 'Rear Delts',
          force: 'pull',
        ),
        makeExercise(
          id: 4,
          name: 'Bicep Curl',
          primaryMuscle: 'Biceps',
          force: 'pull',
        ),
        makeExercise(
          id: 5,
          name: 'Plank',
          primaryMuscle: 'Abs',
          force: 'static',
        ),
      ];
      expect(WorkoutNameGenerator.generate(exercises), 'Pull & Abs');
    });

    test('returns Legs & Shoulders for legs and shoulders', () {
      final exercises = [
        makeExercise(
          id: 1,
          name: 'Barbell Squat',
          primaryMuscle: 'Quads',
          force: 'push',
        ),
        makeExercise(
          id: 2,
          name: 'Overhead Press',
          primaryMuscle: 'Shoulders',
          force: 'push',
        ),
      ];
      expect(WorkoutNameGenerator.generate(exercises), 'Legs & Shoulders');
    });

    test('returns Legs & Arms for legs and arms', () {
      final exercises = [
        makeExercise(
          id: 1,
          name: 'Barbell Squat',
          primaryMuscle: 'Quads',
          force: 'push',
        ),
        makeExercise(
          id: 2,
          name: 'Bicep Curl',
          primaryMuscle: 'Biceps',
          force: 'pull',
        ),
        makeExercise(
          id: 3,
          name: 'Tricep Pushdown',
          primaryMuscle: 'Triceps',
          force: 'push',
        ),
      ];
      expect(WorkoutNameGenerator.generate(exercises), 'Legs & Arms');
    });

    test('returns Chest & Arms for chest and both arm muscles', () {
      final exercises = [
        makeExercise(
          id: 1,
          name: 'Bench Press',
          primaryMuscle: 'Chest',
          force: 'push',
        ),
        makeExercise(
          id: 2,
          name: 'Bicep Curl',
          primaryMuscle: 'Biceps',
          force: 'pull',
        ),
        makeExercise(
          id: 3,
          name: 'Tricep Pushdown',
          primaryMuscle: 'Triceps',
          force: 'push',
        ),
      ];
      expect(WorkoutNameGenerator.generate(exercises), 'Chest & Arms');
    });

    test('returns Back & Arms for back and both arm muscles', () {
      final exercises = [
        makeExercise(
          id: 1,
          name: 'Barbell Row',
          primaryMuscle: 'Back',
          force: 'pull',
        ),
        makeExercise(
          id: 2,
          name: 'Bicep Curl',
          primaryMuscle: 'Biceps',
          force: 'pull',
        ),
        makeExercise(
          id: 3,
          name: 'Tricep Pushdown',
          primaryMuscle: 'Triceps',
          force: 'push',
        ),
      ];
      expect(WorkoutNameGenerator.generate(exercises), 'Back & Arms');
    });

    test('returns Cardio & Abs for cardio and core', () {
      final exercises = [
        makeExercise(
          id: 1,
          name: 'Treadmill Run',
          primaryMuscle: 'Quads',
          category: 'cardio',
        ),
        makeExercise(
          id: 2,
          name: 'Plank',
          primaryMuscle: 'Abs',
          force: 'static',
        ),
      ];
      expect(WorkoutNameGenerator.generate(exercises), 'Cardio & Abs');
    });

    test('returns Quads & Calves for quads and calves only', () {
      final exercises = [
        makeExercise(
          id: 1,
          name: 'Barbell Squat',
          primaryMuscle: 'Quads',
          force: 'push',
        ),
        makeExercise(
          id: 2,
          name: 'Leg Extension',
          primaryMuscle: 'Quads',
          force: 'push',
        ),
        makeExercise(
          id: 3,
          name: 'Calf Raise',
          primaryMuscle: 'Calves',
          force: 'push',
        ),
      ];
      expect(WorkoutNameGenerator.generate(exercises), 'Quads & Calves');
    });

    test('returns Glutes & Hamstrings for glutes and hamstrings only', () {
      final exercises = [
        makeExercise(
          id: 1,
          name: 'Hip Thrust',
          primaryMuscle: 'Glutes',
          force: 'push',
        ),
        makeExercise(
          id: 2,
          name: 'Romanian Deadlift',
          primaryMuscle: 'Hamstrings',
          force: 'pull',
        ),
      ];
      expect(WorkoutNameGenerator.generate(exercises), 'Glutes & Hamstrings');
    });
  });
}
