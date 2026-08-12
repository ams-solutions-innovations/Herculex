import 'package:flutter_test/flutter_test.dart';
import 'package:herculex/data/local/database.dart';
import 'package:herculex/features/workouts/domain/active_workout_notification_target.dart';
import 'package:herculex/features/workouts/domain/ongoing_workout_surface_snapshot.dart';
import 'package:herculex/features/workouts/domain/workout_notification_command.dart';

void main() {
  group('buildOngoingWorkoutSurfaceSnapshot', () {
    test('builds collapsed status labels from the active target', () {
      final snapshot = buildOngoingWorkoutSurfaceSnapshot(
        target: ActiveWorkoutNotificationTarget(
          exerciseName: 'Bench Press',
          set: _set(setIndex: 2, weightKg: 82.5, reps: 8),
          totalSets: 5,
        ),
        formatWeight: _formatKg,
        loadStepKg: 2.5,
      );

      expect(snapshot.exerciseName, 'Bench Press');
      expect(snapshot.currentSet, 3);
      expect(snapshot.targetSetId, 1);
      expect(snapshot.totalSets, 5);
      expect(snapshot.weightKg, 82.5);
      expect(snapshot.setLabel, 'Set 3/5');
      expect(snapshot.valueLabel, '82.5 kg x 8 reps');
    });

    test('builds expanded action labels from the configured load step', () {
      final snapshot = buildOngoingWorkoutSurfaceSnapshot(
        target: ActiveWorkoutNotificationTarget(
          exerciseName: 'Squat',
          set: _set(),
          totalSets: 3,
        ),
        formatWeight: _formatKg,
        loadStepKg: 5,
      );

      // Spelled out rather than spread from the constant the builder itself
      // iterates — otherwise a reordering of the priority list can never fail
      // this test. Completing the set leads: it is the primary action on a
      // collapsed notification.
      expect(snapshot.actions.map((action) => action.id), [
        WorkoutNotificationActionIds.completeSet,
        WorkoutNotificationActionIds.repsUp,
        WorkoutNotificationActionIds.weightUp,
        WorkoutNotificationActionIds.repsDown,
        WorkoutNotificationActionIds.weightDown,
      ]);
      expect(snapshot.actions.map((action) => action.label), [
        'Done',
        '+ Rep',
        '+ 5 kg',
        '- Rep',
        '- 5 kg',
      ]);
    });

    test('builds a generic status when there is no active target', () {
      final snapshot = buildOngoingWorkoutSurfaceSnapshot(
        target: null,
        formatWeight: _formatKg,
        loadStepKg: 2.5,
      );

      expect(snapshot.exerciseName, 'Workout in progress');
      expect(snapshot.currentSet, isNull);
      expect(snapshot.valueLabel, '');
      expect(
        snapshot.actions.map((action) => action.label),
        contains('+ 2.5 kg'),
      );
    });
  });
}

SetEntryData _set({int setIndex = 0, double weightKg = 80, int reps = 5}) {
  return SetEntryData(
    id: 1,
    workoutExerciseId: 10,
    setIndex: setIndex,
    weightKg: weightKg,
    reps: reps,
    isWarmup: false,
    isCompleted: false,
    setType: 'standard',
  );
}

String _formatKg(double kg) {
  return kg.truncateToDouble() == kg
      ? '${kg.toStringAsFixed(0)} kg'
      : '${kg.toStringAsFixed(1)} kg';
}
