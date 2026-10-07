import 'package:flutter_test/flutter_test.dart';
import 'package:health/health.dart';
import 'package:herculex/features/analytics/domain/muscle_recovery_v3.dart';
import 'package:herculex/features/analytics/domain/training_snapshot.dart';
import 'package:herculex/features/workouts/domain/session_summary.dart';

void main() {
  group('Health Integration Tests', () {
    test('Climbing affects Back and Forearms more heavily', () {
      final now = DateTime.now();

      final snapshot = const TrainingSnapshot(sets: [], exerciseMuscles: []);

      final climbingWorkout = HealthDataPoint(
        uuid: 'test1',
        value: WorkoutHealthValue(
          workoutActivityType: HealthWorkoutActivityType.CLIMBING,
          totalEnergyBurned: 600,
          totalEnergyBurnedUnit: HealthDataUnit.KILOCALORIE,
          totalDistance: 0,
          totalDistanceUnit: HealthDataUnit.METER,
        ),
        type: HealthDataType.WORKOUT,
        unit: HealthDataUnit.NO_UNIT,
        dateFrom: now.subtract(const Duration(hours: 3)),
        dateTo: now.subtract(const Duration(hours: 1)),
        sourcePlatform: HealthPlatformType.appleHealth,
        sourceDeviceId: 'watch',
        sourceId: 'apple',
        sourceName: 'Apple Watch',
      );

      final muscle = MuscleRecoveryV3.compute(
        snapshot: snapshot,
        externalWorkouts: [climbingWorkout],
        asOf: now,
      );

      final backRecovery = muscle
          .firstWhere((e) => e.muscle == 'Back')
          .recoveryScore;
      final forearmsRecovery = muscle
          .firstWhere((e) => e.muscle == 'Forearms')
          .recoveryScore;
      final chestRecovery = muscle
          .firstWhere((e) => e.muscle == 'Chest')
          .recoveryScore;

      expect(backRecovery, lessThan(chestRecovery));
      expect(forearmsRecovery, lessThan(chestRecovery));
    });

    test('Running affects Quads, Hamstrings, Calves', () {
      final now = DateTime.now();
      final snapshot = const TrainingSnapshot(sets: [], exerciseMuscles: []);

      final runningWorkout = HealthDataPoint(
        uuid: 'test2',
        value: WorkoutHealthValue(
          workoutActivityType: HealthWorkoutActivityType.RUNNING,
          totalEnergyBurned: 500,
          totalEnergyBurnedUnit: HealthDataUnit.KILOCALORIE,
          totalDistance: 10000,
          totalDistanceUnit: HealthDataUnit.METER,
        ),
        type: HealthDataType.WORKOUT,
        unit: HealthDataUnit.NO_UNIT,
        dateFrom: now.subtract(const Duration(hours: 2)),
        dateTo: now.subtract(const Duration(hours: 1)),
        sourcePlatform: HealthPlatformType.appleHealth,
        sourceDeviceId: 'watch',
        sourceId: 'apple',
        sourceName: 'Apple Watch',
      );

      final muscle = MuscleRecoveryV3.compute(
        snapshot: snapshot,
        externalWorkouts: [runningWorkout],
        asOf: now,
      );

      final quadsRecovery = muscle
          .firstWhere((e) => e.muscle == 'Quads')
          .recoveryScore;
      final chestRecovery = muscle
          .firstWhere((e) => e.muscle == 'Chest')
          .recoveryScore;

      expect(quadsRecovery, lessThan(chestRecovery));
    });

    test(
      'SessionSummary calculates estimated calories and retains photoPath',
      () {
        final start = DateTime(2026, 8, 21, 9, 0);
        final end = DateTime(2026, 8, 21, 10, 0); // 60 min

        final summary = SessionSummary.fromSnapshot(
          snapshot: const TrainingSnapshot(sets: [], exerciseMuscles: []),
          sessionId: 1,
          name: 'Arm Day',
          startedAt: start,
          endedAt: end,
          photoPath: '/storage/emulated/0/workout_1.jpg',
          savedCalories: 450,
        );

        expect(summary.name, equals('Arm Day'));
        expect(summary.durationLabel, equals('1h 0m'));
        expect(summary.caloriesBurned, equals(450));
        expect(summary.caloriesLabel, equals('450 kcal'));
        expect(summary.photoPath, equals('/storage/emulated/0/workout_1.jpg'));
      },
    );
  });
}
