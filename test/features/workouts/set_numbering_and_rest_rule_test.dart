import 'package:flutter_test/flutter_test.dart';
import 'package:herculex/data/local/database.dart';
import 'package:herculex/features/workouts/domain/active_workout_notification_target.dart';
import 'package:herculex/features/workouts/domain/ongoing_workout_surface_snapshot.dart';
import 'package:herculex/features/workouts/domain/rest_rule.dart';
import 'package:herculex/features/workouts/domain/set_numbering.dart';

SetEntryData _set(int id, {bool warmup = false}) => SetEntryData(
  id: id,
  workoutExerciseId: 1,
  setIndex: id,
  weightKg: 60,
  reps: 8,
  setType: 'standard',
  isWarmup: warmup,
  isCompleted: false,
);

WorkoutExerciseData _exercise(
  int id, {
  int orderIndex = 0,
  int? supersetGroup,
  int? rest,
}) => WorkoutExerciseData(
  id: id,
  sessionId: 1,
  exerciseId: id,
  orderIndex: orderIndex,
  supersetGroup: supersetGroup,
  targetRestSeconds: rest,
  plannedAllowsAdvancedTechniques: false,
);

void main() {
  group('numberSets', () {
    test('working sets count from 1 after warmups', () {
      final numbers = numberSets([
        _set(1, warmup: true),
        _set(2, warmup: true),
        _set(3),
        _set(4),
        _set(5),
      ]);
      expect(numbers.map((n) => n.short), ['W1', 'W2', '1', '2', '3']);
      expect(numbers[2].withTotal, '1/3');
      expect(numbers[0].withTotal, 'W1');
    });

    test('no warmups numbers plainly', () {
      final numbers = numberSets([_set(1), _set(2)]);
      expect(numbers.map((n) => n.ordinal), [1, 2]);
      expect(numbers.every((n) => n.ofKind == 2), isTrue);
    });

    test('a warmup between working sets does not shift them', () {
      final numbers = numberSetFlags([false, true, false]);
      expect(numbers.map((n) => n.short), ['1', 'W1', '2']);
    });
  });

  group('restAfterCompletedSet', () {
    test('a single exercise rests its own target', () {
      final ex = _exercise(1, rest: 150);
      final plan = restAfterCompletedSet(
        completed: ex,
        sessionExercises: [ex],
        exerciseName: 'Bench Press',
        catalogDefaultRestSeconds: 120,
        round: 1,
      );
      expect(plan?.seconds, 150);
      expect(plan?.label, 'Bench Press');
    });

    test('falls back to the catalog, then to the default', () {
      final ex = _exercise(1);
      expect(
        restAfterCompletedSet(
          completed: ex,
          sessionExercises: [ex],
          exerciseName: 'Row',
          catalogDefaultRestSeconds: 75,
          round: 1,
        )?.seconds,
        75,
      );
      expect(
        restAfterCompletedSet(
          completed: ex,
          sessionExercises: [ex],
          exerciseName: 'Row',
          round: 1,
        )?.seconds,
        kDefaultRestSeconds,
      );
    });

    test('only the last member of a superset rests', () {
      final a = _exercise(1, orderIndex: 0, supersetGroup: 7, rest: 90);
      final b = _exercise(2, orderIndex: 1, supersetGroup: 7, rest: 90);
      expect(
        restAfterCompletedSet(
          completed: a,
          sessionExercises: [a, b],
          exerciseName: 'A',
          round: 2,
        ),
        isNull,
      );
      final plan = restAfterCompletedSet(
        completed: b,
        sessionExercises: [a, b],
        exerciseName: 'B',
        round: 2,
      );
      expect(plan?.label, 'Superset Rest (Round 2)');
      expect(plan?.seconds, 90);
    });

    test('a zero rest means no timer', () {
      final ex = _exercise(1, rest: 0);
      expect(
        restAfterCompletedSet(
          completed: ex,
          sessionExercises: [ex],
          exerciseName: 'Plank',
          round: 1,
        ),
        isNull,
      );
    });
  });

  group('ongoing workout surface label', () {
    String labelFor(List<SetEntryData> sets) {
      final target = selectActiveWorkoutNotificationTarget(
        exercises: [_exercise(1)],
        setsByWorkoutExerciseId: {1: sets},
        catalog: const [],
      );
      return buildOngoingWorkoutSurfaceSnapshot(
        target: target,
        formatWeight: (kg) => '$kg kg',
        loadStepKg: 2.5,
      ).setLabel;
    }

    test('an open warmup reads as a warmup, not as set 1', () {
      expect(labelFor([_set(1, warmup: true), _set(2), _set(3)]), 'Warmup W1');
    });

    test('the first working set after warmups is set 1', () {
      final done = _set(1, warmup: true).copyWith(isCompleted: true);
      expect(labelFor([done, _set(2), _set(3)]), 'Set 1/2');
    });
  });
}
