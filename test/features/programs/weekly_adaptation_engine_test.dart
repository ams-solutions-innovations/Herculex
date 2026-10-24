import 'package:flutter_test/flutter_test.dart';
import 'package:herculex/features/programs/domain/weekly_adaptation_engine.dart';

AdaptedExercise _exercise(int id, int sets) => AdaptedExercise(
  exerciseId: id,
  orderIndex: 0,
  restSeconds: 90,
  slotRole: 'accessory',
  trainingMethod: 'straight_sets',
  why: 'test',
  allowsAdvancedTechniques: false,
  sets: [
    for (var index = 0; index < sets; index++)
      AdaptedSet(
        index: index + 1,
        isWarmup: false,
        setType: 'standard',
        intent: 'rir2',
        repsMin: 8,
        repsMax: 12,
      ),
  ],
);

AdaptationCandidate _candidate({
  required int recovery,
  bool nextWeekConflict = false,
  int plannedSets = 10,
  int addedSets = 2,
}) => AdaptationCandidate(
  scheduleId: 2,
  date: DateTime(2026, 10, 16),
  plan: AdaptedSessionPlan(
    name: 'Friday',
    exercises: [_exercise(1, plannedSets)],
  ),
  addition: _exercise(2, addedSets),
  muscleCredit: {'Chest': addedSets.toDouble()},
  recoveryScore: recovery,
  conflictsNextWeek: nextWeekConflict,
);

void main() {
  group('WeeklyAdaptationEngine', () {
    test('uses the least disruptive recovered scheduled session', () {
      final result = WeeklyAdaptationEngine.propose(
        trigger: AdaptationTrigger.skippedWorkout,
        weekStart: DateTime(2026, 10, 12),
        targetVolume: {'Chest': 10},
        actualVolume: {'Chest': 8},
        candidates: [_candidate(recovery: 80)],
        inputFingerprint: 'test',
      );

      expect(result.changes, hasLength(1));
      expect(result.changes.single.scheduleId, 2);
      expect(result.uncoveredVolume, isEmpty);
    });

    test('does not add volume to an under-recovered muscle', () {
      final result = WeeklyAdaptationEngine.propose(
        trigger: AdaptationTrigger.skippedWorkout,
        weekStart: DateTime(2026, 10, 12),
        targetVolume: {'Chest': 10},
        actualVolume: {'Chest': 8},
        candidates: [_candidate(recovery: 69)],
        inputFingerprint: 'test',
      );

      expect(result.changes, isEmpty);
      expect(result.uncoveredVolume['Chest'], 2);
    });

    test('does not create a Sunday-to-next-week overlap', () {
      final result = WeeklyAdaptationEngine.propose(
        trigger: AdaptationTrigger.skippedWorkout,
        weekStart: DateTime(2026, 10, 12),
        targetVolume: {'Chest': 10},
        actualVolume: {'Chest': 8},
        candidates: [_candidate(recovery: 90, nextWeekConflict: true)],
        inputFingerprint: 'test',
      );

      expect(result.changes, isEmpty);
      expect(result.uncoveredVolume['Chest'], 2);
    });

    test('honours the 20 percent per-session growth cap', () {
      final result = WeeklyAdaptationEngine.propose(
        trigger: AdaptationTrigger.skippedWorkout,
        weekStart: DateTime(2026, 10, 12),
        targetVolume: {'Chest': 10},
        actualVolume: {'Chest': 8},
        candidates: [_candidate(recovery: 90, plannedSets: 5, addedSets: 2)],
        inputFingerprint: 'test',
      );

      expect(result.changes, isEmpty);
      expect(result.uncoveredVolume['Chest'], 2);
    });

    test('does not overshoot volume already covered by a manual extra', () {
      final result = WeeklyAdaptationEngine.propose(
        trigger: AdaptationTrigger.incompleteWorkout,
        weekStart: DateTime(2026, 10, 12),
        targetVolume: {'Chest': 10},
        // This reflects the user's already logged manual working sets.
        actualVolume: {'Chest': 9},
        candidates: [_candidate(recovery: 90, addedSets: 2)],
        inputFingerprint: 'manual-extra',
      );

      expect(result.changes, isEmpty);
      expect(result.uncoveredVolume['Chest'], 1);
    });
  });
}
