import 'package:flutter_test/flutter_test.dart';
import 'package:herculex/data/local/database.dart';
import 'package:herculex/features/workouts/domain/circuit_stats.dart';

void main() {
  group('calculateCircuitStats', () {
    test('returns empty when exercises are empty', () {
      final stats = calculateCircuitStats(exercises: [], setsByExerciseId: {});
      expect(stats.completedRounds, 0);
      expect(stats.totalPlannedRounds, 0);
      expect(stats.averageRestBetweenRoundsSeconds, isNull);
      expect(stats.formattedAvgRest, '—');
    });

    test('calculates completed rounds and avg rest correctly', () {
      final ex1 = WorkoutExerciseData(
        id: 101,
        sessionId: 1,
        exerciseId: 1,
        orderIndex: 0,
        supersetGroup: 1,
        targetRestSeconds: 90,
      );
      final ex2 = WorkoutExerciseData(
        id: 102,
        sessionId: 1,
        exerciseId: 2,
        orderIndex: 1,
        supersetGroup: 1,
        targetRestSeconds: 90,
      );

      final now = DateTime(2026, 1, 1, 10, 0, 0);

      final sets1 = [
        SetEntryData(
          id: 1,
          workoutExerciseId: 101,
          setIndex: 1,
          reps: 10,
          weightKg: 50,
          isCompleted: true,
          completedAt: now,
          isWarmup: false,
          setType: 'standard',
        ),
        SetEntryData(
          id: 2,
          workoutExerciseId: 101,
          setIndex: 2,
          reps: 10,
          weightKg: 50,
          isCompleted: true,
          completedAt: now.add(const Duration(seconds: 120)),
          isWarmup: false,
          setType: 'standard',
        ),
        SetEntryData(
          id: 3,
          workoutExerciseId: 101,
          setIndex: 3,
          reps: 10,
          weightKg: 50,
          isCompleted: true,
          completedAt: now.add(const Duration(seconds: 240)),
          isWarmup: false,
          setType: 'standard',
        ),
      ];

      final sets2 = [
        SetEntryData(
          id: 4,
          workoutExerciseId: 102,
          setIndex: 1,
          reps: 12,
          weightKg: 20,
          isCompleted: true,
          completedAt: now.add(const Duration(seconds: 30)),
          isWarmup: false,
          setType: 'standard',
        ),
        SetEntryData(
          id: 5,
          workoutExerciseId: 102,
          setIndex: 2,
          reps: 12,
          weightKg: 20,
          isCompleted: true,
          completedAt: now.add(const Duration(seconds: 150)),
          isWarmup: false,
          setType: 'standard',
        ),
        SetEntryData(
          id: 6,
          workoutExerciseId: 102,
          setIndex: 3,
          reps: 12,
          weightKg: 20,
          isCompleted: false,
          isWarmup: false,
          setType: 'standard',
        ),
      ];

      final stats = calculateCircuitStats(
        exercises: [ex1, ex2],
        setsByExerciseId: {101: sets1, 102: sets2},
      );

      expect(stats.totalPlannedRounds, 3);
      expect(stats.completedRounds, 2);
      expect(stats.averageRestBetweenRoundsSeconds, 90);
      expect(stats.formattedAvgRest, '1m 30s');
    });
  });
}
