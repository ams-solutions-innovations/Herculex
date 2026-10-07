import 'package:collection/collection.dart';

import 'package:herculex/data/local/database.dart';
import 'package:herculex/features/workouts/domain/set_numbering.dart';

class ActiveWorkoutNotificationTarget {
  final String exerciseName;
  final SetEntryData set;
  final int totalSets;
  final String primaryMuscle;
  final String equipmentVariant;
  final SetEntryData? lastCompletedSet;

  /// How [set] is numbered on screen — warmups as W1, W2, working sets
  /// counting from 1. Null only for the synthetic set of an empty exercise.
  final SetNumber? setNumber;

  const ActiveWorkoutNotificationTarget({
    required this.exerciseName,
    required this.set,
    required this.totalSets,
    this.primaryMuscle = '',
    this.equipmentVariant = '',
    this.lastCompletedSet,
    this.setNumber,
  });
}

ActiveWorkoutNotificationTarget? selectActiveWorkoutNotificationTarget({
  required List<WorkoutExerciseData> exercises,
  required Map<int, List<SetEntryData>> setsByWorkoutExerciseId,
  required List<ExerciseCatalogData> catalog,
}) {
  if (exercises.isEmpty) return null;

  ActiveWorkoutNotificationTarget? fallback;
  for (final exercise in exercises) {
    final sets = setsByWorkoutExerciseId[exercise.id] ?? const <SetEntryData>[];

    final catalogEntry = catalog.firstWhereOrNull(
      (e) => e.id == exercise.exerciseId,
    );
    final exerciseName = catalogEntry?.name ?? 'Workout in progress';

    if (sets.isEmpty) {
      final syntheticSet = SetEntryData(
        id: -exercise.id,
        workoutExerciseId: exercise.id,
        setIndex: 0,
        weightKg: 0.0,
        reps: 0,
        setType: 'standard',
        isWarmup: false,
        isCompleted: false,
      );
      return ActiveWorkoutNotificationTarget(
        exerciseName: exerciseName,
        set: syntheticSet,
        totalSets: 1,
        primaryMuscle: catalogEntry?.primaryMuscle ?? '',
        equipmentVariant:
            exercise.equipmentVariant ?? catalogEntry?.modality ?? '',
      );
    }

    final nextOpenSet = sets.where((s) => !s.isCompleted).firstOrNull;
    final targetSet = nextOpenSet ?? sets.last;
    final target = ActiveWorkoutNotificationTarget(
      exerciseName: exerciseName,
      set: targetSet,
      setNumber: numberSets(sets)[sets.indexOf(targetSet)],
      totalSets: sets.length,
      primaryMuscle: catalogEntry?.primaryMuscle ?? '',
      equipmentVariant:
          exercise.equipmentVariant ?? catalogEntry?.modality ?? '',
      lastCompletedSet: sets.where((s) => s.isCompleted).lastOrNull,
    );

    if (nextOpenSet != null) {
      return target;
    }
    fallback = target;
  }

  return fallback;
}
