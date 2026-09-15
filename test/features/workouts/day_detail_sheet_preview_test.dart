import 'package:flutter_test/flutter_test.dart';
import 'package:herculex/features/programs/presentation/sheets/day_detail_sheet.dart';
import 'package:herculex/features/workouts/data/planned_session_resolver.dart';

PlannedSetSnapshot _set({
  required int index,
  int? repsMin,
  int? repsMax,
  bool isWarmup = false,
  String setType = 'standard',
  String intent = 'rir2',
  double? percentOf1Rm,
}) {
  return PlannedSetSnapshot(
    index: index,
    repsMin: repsMin,
    repsMax: repsMax,
    isWarmup: isWarmup,
    setType: setType,
    intent: intent,
    percentOf1Rm: percentOf1Rm,
  );
}

PlannedExerciseSnapshot _exercise({
  required List<PlannedSetSnapshot> sets,
  int restSeconds = 90,
}) {
  return PlannedExerciseSnapshot(
    exerciseId: 1,
    orderIndex: 0,
    restSeconds: restSeconds,
    slotRole: 'primary',
    trainingMethod: 'straight_sets',
    why: 'test',
    sets: sets,
    allowsAdvancedTechniques: true,
  );
}

void main() {
  group('formatPlannedExerciseSets', () {
    test('groups warmups and working sets into separate labeled runs', () {
      final exercise = _exercise(
        restSeconds: 120,
        sets: [
          _set(
            index: 0,
            repsMin: 5,
            repsMax: 5,
            isWarmup: true,
            percentOf1Rm: 0.4,
          ),
          _set(
            index: 1,
            repsMin: 5,
            repsMax: 5,
            isWarmup: true,
            percentOf1Rm: 0.6,
          ),
          _set(index: 2, repsMin: 8, repsMax: 8, percentOf1Rm: 0.7),
          _set(index: 3, repsMin: 8, repsMax: 8, percentOf1Rm: 0.7),
          _set(index: 4, repsMin: 8, repsMax: 8, percentOf1Rm: 0.7),
        ],
      );

      final formatted = formatPlannedExerciseSets(exercise);

      expect(formatted, contains('Warmup:'));
      expect(formatted, contains('@40%'));
      expect(formatted, contains('3x8 @70%'));
      expect(formatted, contains('Rest 120s'));
    });

    test('renders the set type label instead of the raw id', () {
      final exercise = _exercise(
        sets: [
          _set(
            index: 0,
            repsMin: 12,
            repsMax: 20,
            setType: 'myo_reps',
            intent: 'to_failure',
          ),
        ],
      );

      final formatted = formatPlannedExerciseSets(exercise);

      expect(formatted, contains('Myo Reps'));
      expect(formatted, isNot(contains('myo_reps')));
    });

    test('falls back to RIR when no %1RM is prescribed', () {
      final exercise = _exercise(
        sets: [
          _set(index: 0, repsMin: 8, repsMax: 8, intent: 'rir2'),
          _set(index: 1, repsMin: 8, repsMax: 8, intent: 'rir2'),
        ],
      );

      final formatted = formatPlannedExerciseSets(exercise);

      expect(formatted, contains('2x8 @RIR2'));
    });

    test('returns a placeholder when no sets are prescribed', () {
      final exercise = _exercise(sets: const []);

      expect(formatPlannedExerciseSets(exercise), 'No sets prescribed');
    });
  });
}
