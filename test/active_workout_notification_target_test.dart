import 'package:flutter_test/flutter_test.dart';
import 'package:herculex/data/local/database.dart';
import 'package:herculex/features/workouts/domain/active_workout_notification_target.dart';

void main() {
  group('selectActiveWorkoutNotificationTarget', () {
    test('selects the first uncompleted set in workout order', () {
      final target = selectActiveWorkoutNotificationTarget(
        exercises: [
          _exercise(id: 10, exerciseId: 1, orderIndex: 0),
          _exercise(id: 20, exerciseId: 2, orderIndex: 1),
        ],
        setsByWorkoutExerciseId: {
          10: [
            _set(id: 100, workoutExerciseId: 10, setIndex: 0, completed: true),
          ],
          20: [
            _set(id: 200, workoutExerciseId: 20, setIndex: 0, completed: true),
            _set(
              id: 201,
              workoutExerciseId: 20,
              setIndex: 1,
              weightKg: 82.5,
              reps: 8,
            ),
          ],
        },
        catalog: [
          _catalog(id: 1, name: 'Squat'),
          _catalog(id: 2, name: 'Bench Press'),
        ],
      );

      expect(target, isNotNull);
      expect(target!.exerciseName, 'Bench Press');
      expect(target.set.id, 201);
      expect(target.set.weightKg, 82.5);
      expect(target.set.reps, 8);
      expect(target.totalSets, 2);
    });

    test('falls back to the last known set when all sets are completed', () {
      final target = selectActiveWorkoutNotificationTarget(
        exercises: [
          _exercise(id: 10, exerciseId: 1, orderIndex: 0),
          _exercise(id: 20, exerciseId: 2, orderIndex: 1),
        ],
        setsByWorkoutExerciseId: {
          10: [
            _set(id: 100, workoutExerciseId: 10, setIndex: 0, completed: true),
          ],
          20: [
            _set(id: 200, workoutExerciseId: 20, setIndex: 0, completed: true),
            _set(id: 201, workoutExerciseId: 20, setIndex: 1, completed: true),
          ],
        },
        catalog: [
          _catalog(id: 1, name: 'Squat'),
          _catalog(id: 2, name: 'Bench Press'),
        ],
      );

      expect(target, isNotNull);
      expect(target!.exerciseName, 'Bench Press');
      expect(target.set.id, 201);
      expect(target.totalSets, 2);
    });

    test('uses a generic label when catalog data is unavailable', () {
      final target = selectActiveWorkoutNotificationTarget(
        exercises: [_exercise(id: 10, exerciseId: 404, orderIndex: 0)],
        setsByWorkoutExerciseId: {
          10: [_set(id: 100, workoutExerciseId: 10, setIndex: 0)],
        },
        catalog: const [],
      );

      expect(target, isNotNull);
      expect(target!.exerciseName, 'Workout in progress');
    });
  });
}

WorkoutExerciseData _exercise({
  required int id,
  required int exerciseId,
  required int orderIndex,
}) {
  return WorkoutExerciseData(
    id: id,
    sessionId: 1,
    exerciseId: exerciseId,
    orderIndex: orderIndex,
  );
}

SetEntryData _set({
  required int id,
  required int workoutExerciseId,
  required int setIndex,
  double weightKg = 80,
  int reps = 5,
  bool completed = false,
}) {
  return SetEntryData(
    id: id,
    workoutExerciseId: workoutExerciseId,
    setIndex: setIndex,
    weightKg: weightKg,
    reps: reps,
    isWarmup: false,
    isCompleted: completed,
    setType: 'standard',
  );
}

ExerciseCatalogData _catalog({required int id, required String name}) {
  return ExerciseCatalogData(
    id: id,
    name: name,
    primaryMuscle: 'Chest',
    equipment: 'Barbell',
    mechanics: 'compound',
    force: 'push',
    plane: 'horizontal',
    defaultRestSeconds: 120,
    isCustom: false,
    category: 'strength',
    modality: 'barbell',
    cnsScore: 5,
    recoveryImpact: 3,
    loggingMetric: 'weight_reps',
    supportsWeightedBodyweight: false,
    isReviewed: true,
  );
}
