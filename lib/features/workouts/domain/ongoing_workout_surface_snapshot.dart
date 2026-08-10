import 'active_workout_notification_target.dart';
import 'workout_notification_command.dart';

class OngoingWorkoutSurfaceSnapshot {
  final String exerciseName;
  final int? currentSet;
  final int? targetSetId;
  final int? totalSets;
  final double? weightKg;
  final String? weightLabel;
  final int? reps;
  final double loadStepKg;
  final String loadStepLabel;
  final List<OngoingWorkoutSurfaceAction> actions;

  const OngoingWorkoutSurfaceSnapshot({
    required this.exerciseName,
    required this.currentSet,
    required this.targetSetId,
    required this.totalSets,
    required this.weightKg,
    required this.weightLabel,
    required this.reps,
    required this.loadStepKg,
    required this.loadStepLabel,
    required this.actions,
  });

  String get setLabel {
    if (currentSet == null) return '';
    if (totalSets == null || totalSets! <= 0) return 'Set $currentSet';
    return 'Set $currentSet/$totalSets';
  }

  String get valueLabel {
    if (weightLabel != null && reps != null) {
      return '$weightLabel x $reps reps';
    }
    if (reps != null) return '$reps reps';
    return '';
  }
}

class OngoingWorkoutSurfaceAction {
  final String id;
  final String label;

  const OngoingWorkoutSurfaceAction({required this.id, required this.label});
}

OngoingWorkoutSurfaceSnapshot buildOngoingWorkoutSurfaceSnapshot({
  required ActiveWorkoutNotificationTarget? target,
  required String Function(double kg) formatWeight,
  required double loadStepKg,
}) {
  final loadStepLabel = formatWeight(loadStepKg);
  return OngoingWorkoutSurfaceSnapshot(
    exerciseName: target?.exerciseName ?? 'Workout in progress',
    currentSet: target == null ? null : target.set.setIndex + 1,
    targetSetId: target?.set.id,
    totalSets: target?.totalSets,
    weightKg: target?.set.weightKg,
    weightLabel: target == null ? null : formatWeight(target.set.weightKg),
    reps: target?.set.reps,
    loadStepKg: loadStepKg,
    loadStepLabel: loadStepLabel,
    actions: buildOngoingWorkoutSurfaceActions(loadStepLabel: loadStepLabel),
  );
}

List<OngoingWorkoutSurfaceAction> buildOngoingWorkoutSurfaceActions({
  required String loadStepLabel,
}) {
  return [
    for (final actionId
        in WorkoutNotificationActionIds.lowRiskSurfaceActionsInPriorityOrder)
      OngoingWorkoutSurfaceAction(
        id: actionId,
        label: _surfaceActionLabel(actionId, loadStepLabel),
      ),
  ];
}

String _surfaceActionLabel(String actionId, String loadStepLabel) {
  return switch (actionId) {
    WorkoutNotificationActionIds.repsUp => '+ Rep',
    WorkoutNotificationActionIds.weightUp => '+ $loadStepLabel',
    WorkoutNotificationActionIds.completeSet => 'Done',
    WorkoutNotificationActionIds.repsDown => '- Rep',
    WorkoutNotificationActionIds.weightDown => '- $loadStepLabel',
    _ => actionId,
  };
}
