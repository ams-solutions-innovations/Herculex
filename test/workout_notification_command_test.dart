import 'package:flutter_test/flutter_test.dart';
import 'package:herculex/data/local/database.dart';
import 'package:herculex/features/workouts/domain/workout_notification_command.dart';

void main() {
  group('workoutNotificationPatchForAction', () {
    test('increments and decrements reps with clamps', () {
      expect(
        workoutNotificationPatchForAction(
          actionId: WorkoutNotificationActionIds.repsUp,
          set: _set(reps: 999),
        )?.reps,
        999,
      );
      expect(
        workoutNotificationPatchForAction(
          actionId: WorkoutNotificationActionIds.repsDown,
          set: _set(reps: 0),
        )?.reps,
        0,
      );
      expect(
        workoutNotificationPatchForAction(
          actionId: WorkoutNotificationActionIds.repsUp,
          set: _set(reps: 7),
        )?.reps,
        8,
      );
    });

    test(
      'increments and decrements weight with configurable step and clamps',
      () {
        expect(
          workoutNotificationPatchForAction(
            actionId: WorkoutNotificationActionIds.weightUp,
            set: _set(weightKg: 80),
          )?.weightKg,
          82.5,
        );
        expect(
          workoutNotificationPatchForAction(
            actionId: WorkoutNotificationActionIds.weightDown,
            set: _set(weightKg: 1),
          )?.weightKg,
          0,
        );
        expect(
          workoutNotificationPatchForAction(
            actionId: WorkoutNotificationActionIds.weightUp,
            set: _set(weightKg: 80),
            weightStepKg: 5,
          )?.weightKg,
          85,
        );
      },
    );

    test('completes the current set', () {
      final patch = workoutNotificationPatchForAction(
        actionId: WorkoutNotificationActionIds.completeSet,
        set: _set(),
      );

      expect(patch?.isCompleted, isTrue);
      expect(patch?.reps, isNull);
      expect(patch?.weightKg, isNull);
    });

    test('ignores unknown actions', () {
      expect(
        workoutNotificationPatchForAction(actionId: 'unknown', set: _set()),
        isNull,
      );
    });
  });
}

SetEntryData _set({double weightKg = 80, int reps = 5}) {
  return SetEntryData(
    id: 1,
    workoutExerciseId: 10,
    setIndex: 0,
    weightKg: weightKg,
    reps: reps,
    isWarmup: false,
    isCompleted: false,
    setType: 'standard',
  );
}
