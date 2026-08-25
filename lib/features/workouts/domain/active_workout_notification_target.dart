import 'package:collection/collection.dart';

import '../../../data/local/database.dart';

class ActiveWorkoutNotificationTarget {
  final String exerciseName;
  final SetEntryData set;
  final int totalSets;
  final String primaryMuscle;
  final String equipmentVariant;
  final SetEntryData? lastCompletedSet;

  const ActiveWorkoutNotificationTarget({
    required this.exerciseName,
    required this.set,
    required this.totalSets,
    this.primaryMuscle = '',
    this.equipmentVariant = '',
    this.lastCompletedSet,
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
    if (sets.isEmpty) continue;

    final catalogEntry = catalog.firstWhereOrNull(
      (e) => e.id == exercise.exerciseId,
    );
    final exerciseName = catalogEntry?.name ?? 'Workout in progress';
    final nextOpenSet = sets.where((s) => !s.isCompleted).firstOrNull;
    final target = ActiveWorkoutNotificationTarget(
      exerciseName: exerciseName,
      set: nextOpenSet ?? sets.last,
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
