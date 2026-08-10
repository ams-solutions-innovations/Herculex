import '../../../data/local/database.dart';

class WorkoutNotificationActionIds {
  static const repsDown = 'workout.reps.down';
  static const repsUp = 'workout.reps.up';
  static const weightDown = 'workout.weight.down';
  static const weightUp = 'workout.weight.up';
  static const completeSet = 'workout.set.complete';
  static const lowRiskSurfaceActionsInPriorityOrder = [
    completeSet,
    repsUp,
    weightUp,
    repsDown,
    weightDown,
  ];

  const WorkoutNotificationActionIds._();
}

class WorkoutNotificationSetPatch {
  final int? reps;
  final double? weightKg;
  final bool? isCompleted;

  const WorkoutNotificationSetPatch({
    this.reps,
    this.weightKg,
    this.isCompleted,
  });
}

WorkoutNotificationSetPatch? workoutNotificationPatchForAction({
  required String actionId,
  required SetEntryData set,
  double weightStepKg = 2.5,
}) {
  switch (actionId) {
    case WorkoutNotificationActionIds.repsDown:
      return WorkoutNotificationSetPatch(reps: (set.reps - 1).clamp(0, 999));
    case WorkoutNotificationActionIds.repsUp:
      return WorkoutNotificationSetPatch(reps: (set.reps + 1).clamp(0, 999));
    case WorkoutNotificationActionIds.weightDown:
      return WorkoutNotificationSetPatch(
        weightKg: (set.weightKg - weightStepKg).clamp(0.0, 9999.0),
      );
    case WorkoutNotificationActionIds.weightUp:
      return WorkoutNotificationSetPatch(
        weightKg: (set.weightKg + weightStepKg).clamp(0.0, 9999.0),
      );
    case WorkoutNotificationActionIds.completeSet:
      return const WorkoutNotificationSetPatch(isCompleted: true);
    default:
      return null;
  }
}
