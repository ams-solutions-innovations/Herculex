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

/// Index of the exercise the user is "on".
///
/// Not simply the first exercise with an open set: if the user skips ahead or
/// works out of order, that would keep pointing at exercise 1. Instead we
/// anchor on the exercise whose set was completed most recently, stay there
/// while it still has open sets, and otherwise continue with the next
/// exercise (wrapping around) that has something left to do.
///
/// With no completed set yet it is the first exercise with open (or no) sets.
/// When everything is done it is the last exercise.
int currentExerciseIndexFor(List<List<SetEntryData>> setsPerExercise) {
  final n = setsPerExercise.length;
  if (n == 0) return 0;

  bool hasWork(List<SetEntryData> sets) =>
      sets.isEmpty || sets.any((s) => !s.isCompleted);

  var anchor = 0;
  DateTime? latest;
  for (var i = 0; i < n; i++) {
    for (final s in setsPerExercise[i]) {
      final at = s.completedAt;
      if (s.isCompleted &&
          at != null &&
          (latest == null || at.isAfter(latest))) {
        latest = at;
        anchor = i;
      }
    }
  }

  for (var step = 0; step < n; step++) {
    final i = (anchor + step) % n;
    if (hasWork(setsPerExercise[i])) return i;
  }
  return n - 1;
}

ActiveWorkoutNotificationTarget? selectActiveWorkoutNotificationTarget({
  required List<WorkoutExerciseData> exercises,
  required Map<int, List<SetEntryData>> setsByWorkoutExerciseId,
  required List<ExerciseCatalogData> catalog,
}) {
  if (exercises.isEmpty) return null;

  final index = currentExerciseIndexFor([
    for (final e in exercises)
      setsByWorkoutExerciseId[e.id] ?? const <SetEntryData>[],
  ]);
  final exercise = exercises[index];
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
  return ActiveWorkoutNotificationTarget(
    exerciseName: exerciseName,
    set: targetSet,
    setNumber: numberSets(sets)[sets.indexOf(targetSet)],
    totalSets: sets.length,
    primaryMuscle: catalogEntry?.primaryMuscle ?? '',
    equipmentVariant: exercise.equipmentVariant ?? catalogEntry?.modality ?? '',
    lastCompletedSet: sets.where((s) => s.isCompleted).lastOrNull,
  );
}
