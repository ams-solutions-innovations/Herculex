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

    test('follows the exercise worked on last, not always the first', () {
      final t0 = DateTime(2026, 1, 1, 10);
      final target = selectActiveWorkoutNotificationTarget(
        exercises: [
          _exercise(id: 10, exerciseId: 1, orderIndex: 0),
          _exercise(id: 20, exerciseId: 2, orderIndex: 1),
          _exercise(id: 30, exerciseId: 3, orderIndex: 2),
        ],
        setsByWorkoutExerciseId: {
          10: [_set(id: 100, workoutExerciseId: 10, setIndex: 0)],
          20: [_set(id: 200, workoutExerciseId: 20, setIndex: 0)],
          30: [
            _set(
              id: 300,
              workoutExerciseId: 30,
              setIndex: 0,
              completed: true,
              completedAt: t0,
            ),
            _set(id: 301, workoutExerciseId: 30, setIndex: 1),
          ],
        },
        catalog: [
          _catalog(id: 1, name: 'Squat'),
          _catalog(id: 2, name: 'Bench Press'),
          _catalog(id: 3, name: 'Row'),
        ],
      );

      expect(target!.exerciseName, 'Row');
      expect(target.set.id, 301);
    });

    test('moves on to the next exercise once the last-worked one is done', () {
      final t0 = DateTime(2026, 1, 1, 10);
      final target = selectActiveWorkoutNotificationTarget(
        exercises: [
          _exercise(id: 10, exerciseId: 1, orderIndex: 0),
          _exercise(id: 20, exerciseId: 2, orderIndex: 1),
          _exercise(id: 30, exerciseId: 3, orderIndex: 2),
        ],
        setsByWorkoutExerciseId: {
          10: [_set(id: 100, workoutExerciseId: 10, setIndex: 0)],
          20: [
            _set(
              id: 200,
              workoutExerciseId: 20,
              setIndex: 0,
              completed: true,
              completedAt: t0,
            ),
          ],
          30: [_set(id: 300, workoutExerciseId: 30, setIndex: 0)],
        },
        catalog: [
          _catalog(id: 1, name: 'Squat'),
          _catalog(id: 2, name: 'Bench Press'),
          _catalog(id: 3, name: 'Row'),
        ],
      );

      expect(target!.exerciseName, 'Row');
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

    test(
      'carries muscle group and equipment variant from the catalog entry',
      () {
        final target = selectActiveWorkoutNotificationTarget(
          exercises: [_exercise(id: 10, exerciseId: 1, orderIndex: 0)],
          setsByWorkoutExerciseId: {
            10: [_set(id: 100, workoutExerciseId: 10, setIndex: 0)],
          },
          catalog: [_catalog(id: 1, name: 'Squat')],
        );

        expect(target, isNotNull);
        expect(target!.primaryMuscle, 'Chest');
        expect(target.equipmentVariant, 'barbell');
      },
    );

    test(
      "prefers the workout exercise's own equipment variant over the catalog default",
      () {
        final target = selectActiveWorkoutNotificationTarget(
          exercises: [
            _exercise(
              id: 10,
              exerciseId: 1,
              orderIndex: 0,
              equipmentVariant: 'dumbbell',
            ),
          ],
          setsByWorkoutExerciseId: {
            10: [_set(id: 100, workoutExerciseId: 10, setIndex: 0)],
          },
          catalog: [_catalog(id: 1, name: 'Squat')],
        );

        expect(target!.equipmentVariant, 'dumbbell');
      },
    );

    test('picks the most recently completed set as lastCompletedSet', () {
      final target = selectActiveWorkoutNotificationTarget(
        exercises: [_exercise(id: 10, exerciseId: 1, orderIndex: 0)],
        setsByWorkoutExerciseId: {
          10: [
            _set(
              id: 100,
              workoutExerciseId: 10,
              setIndex: 0,
              completed: true,
              weightKg: 60,
            ),
            _set(
              id: 101,
              workoutExerciseId: 10,
              setIndex: 1,
              completed: true,
              weightKg: 65,
            ),
            _set(id: 102, workoutExerciseId: 10, setIndex: 2),
          ],
        },
        catalog: [_catalog(id: 1, name: 'Squat')],
      );

      expect(target!.lastCompletedSet?.id, 101);
    });

    test('lastCompletedSet is null when nothing has been completed yet', () {
      final target = selectActiveWorkoutNotificationTarget(
        exercises: [_exercise(id: 10, exerciseId: 1, orderIndex: 0)],
        setsByWorkoutExerciseId: {
          10: [_set(id: 100, workoutExerciseId: 10, setIndex: 0)],
        },
        catalog: [_catalog(id: 1, name: 'Squat')],
      );

      expect(target!.lastCompletedSet, isNull);
    });

    test(
      'advances to next exercise when first exercise has all sets completed',
      () {
        final target = selectActiveWorkoutNotificationTarget(
          exercises: [
            _exercise(id: 10, exerciseId: 1, orderIndex: 0),
            _exercise(id: 20, exerciseId: 2, orderIndex: 1),
          ],
          setsByWorkoutExerciseId: {
            10: [
              _set(
                id: 100,
                workoutExerciseId: 10,
                setIndex: 0,
                completed: true,
              ),
              _set(
                id: 101,
                workoutExerciseId: 10,
                setIndex: 1,
                completed: true,
              ),
              _set(
                id: 102,
                workoutExerciseId: 10,
                setIndex: 2,
                completed: true,
              ),
            ],
            20: [
              _set(
                id: 200,
                workoutExerciseId: 20,
                setIndex: 0,
                completed: false,
              ),
              _set(
                id: 201,
                workoutExerciseId: 20,
                setIndex: 1,
                completed: false,
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
        expect(target.set.id, 200);
        expect(target.totalSets, 2);
      },
    );

    test('advances to next exercise even if next exercise has no sets yet', () {
      final target = selectActiveWorkoutNotificationTarget(
        exercises: [
          _exercise(id: 10, exerciseId: 1, orderIndex: 0),
          _exercise(id: 20, exerciseId: 2, orderIndex: 1),
        ],
        setsByWorkoutExerciseId: {
          10: [
            _set(id: 100, workoutExerciseId: 10, setIndex: 0, completed: true),
          ],
          20: [],
        },
        catalog: [
          _catalog(id: 1, name: 'Squat'),
          _catalog(id: 2, name: 'Incline Press'),
        ],
      );

      expect(target, isNotNull);
      expect(target!.exerciseName, 'Incline Press');
      expect(target.totalSets, 1);
    });
  });
}

WorkoutExerciseData _exercise({
  required int id,
  required int exerciseId,
  required int orderIndex,
  String? equipmentVariant,
}) {
  return WorkoutExerciseData(
    id: id,
    sessionId: 1,
    exerciseId: exerciseId,
    orderIndex: orderIndex,
    equipmentVariant: equipmentVariant,
    plannedAllowsAdvancedTechniques: false,
  );
}

SetEntryData _set({
  required int id,
  required int workoutExerciseId,
  required int setIndex,
  double weightKg = 80,
  int reps = 5,
  bool completed = false,
  DateTime? completedAt,
}) {
  return SetEntryData(
    id: id,
    workoutExerciseId: workoutExerciseId,
    setIndex: setIndex,
    weightKg: weightKg,
    reps: reps,
    isWarmup: false,
    isCompleted: completed,
    completedAt: completedAt,
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
