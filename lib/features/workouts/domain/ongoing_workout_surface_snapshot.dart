import 'package:herculex/data/local/database.dart';
import 'package:herculex/features/workouts/domain/active_workout_notification_target.dart';
import 'package:herculex/features/workouts/domain/equipment_variants.dart';
import 'package:herculex/features/workouts/domain/workout_notification_command.dart';

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

  /// "{muscle} • {equipment}", e.g. "Quads • Barbell" — same wording the full
  /// active-workout screen uses (`active_exercise_card.dart`'s exercise
  /// subtitle), reused here for the bubble popup's subtitle line.
  final String subtitle;

  /// "Last set: {weight} × {reps}", with " @{rpe}" appended when an RPE was
  /// logged. Null when nothing has been completed for this exercise yet.
  final String? lastSetSummary;

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
    this.subtitle = '',
    this.lastSetSummary,
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
    subtitle: target == null ? '' : _subtitleFor(target),
    lastSetSummary: target == null
        ? null
        : _lastSetSummaryFor(target.lastCompletedSet, formatWeight),
  );
}

/// "{muscle} • {equipment}", matching `active_exercise_card.dart`'s own
/// exercise subtitle wording so the bubble reads the same as the full app.
String _subtitleFor(ActiveWorkoutNotificationTarget target) {
  final muscle = target.primaryMuscle;
  final equipment = equipmentVariantLabel(target.equipmentVariant);
  if (muscle.isEmpty) return equipment;
  if (equipment.isEmpty) return muscle;
  return '$muscle • $equipment';
}

String? _lastSetSummaryFor(
  SetEntryData? lastSet,
  String Function(double kg) formatWeight,
) {
  if (lastSet == null) return null;
  final weight = formatWeight(lastSet.weightKg);
  final rpeX10 = lastSet.rpeX10;
  final rpeSuffix = rpeX10 == null ? '' : ' @${_formatRpe(rpeX10)}';
  return 'Last set: $weight × ${lastSet.reps}$rpeSuffix';
}

/// `rpeX10` halves are stored ×10 as plain int math — 85 -> "8.5", 80 -> "8"
/// (never "8.0"), matching the mock's `@8.5` style.
String _formatRpe(int rpeX10) {
  final whole = rpeX10 / 10;
  return whole.truncateToDouble() == whole
      ? whole.toStringAsFixed(0)
      : whole.toStringAsFixed(1);
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
