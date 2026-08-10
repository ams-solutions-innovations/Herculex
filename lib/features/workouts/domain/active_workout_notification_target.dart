import 'package:collection/collection.dart';

import '../../../data/local/database.dart';

class ActiveWorkoutNotificationTarget {
  final String exerciseName;
  final SetEntryData set;
  final int totalSets;

  const ActiveWorkoutNotificationTarget({
    required this.exerciseName,
    required this.set,
    required this.totalSets,
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

    final exerciseName =
        catalog.firstWhereOrNull((e) => e.id == exercise.exerciseId)?.name ??
        'Workout in progress';
    final nextOpenSet = sets.where((s) => !s.isCompleted).firstOrNull;
    final target = ActiveWorkoutNotificationTarget(
      exerciseName: exerciseName,
      set: nextOpenSet ?? sets.last,
      totalSets: sets.length,
    );

    if (nextOpenSet != null) {
      return target;
    }
    fallback = target;
  }

  return fallback;
}
