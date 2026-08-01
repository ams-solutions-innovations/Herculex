import 'package:flutter_test/flutter_test.dart';
import 'package:health/health.dart';
import 'package:herculex/features/analytics/domain/cns_fatigue.dart';
import 'package:herculex/features/analytics/domain/muscle_recovery_v3.dart';
import 'package:herculex/features/analytics/domain/training_snapshot.dart';

void main() {
  group('Health Integration Tests', () {
    test('Climbing affects Back and Forearms more heavily', () {
      final now = DateTime.now();
      
      final snapshot = const TrainingSnapshot(
        sets: [],
        exerciseMuscles: [],
      );

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

      final cns = CnsFatigue.compute(
        sets: [],
        workoutExercises: [],
        catalog: [],
        externalWorkouts: [climbingWorkout],
        asOf: now,
      );

      final muscle = MuscleRecoveryV3.compute(
        snapshot: snapshot, 
        externalWorkouts: [climbingWorkout],
        asOf: now,
      );

      expect(cns.load, greaterThan(0.0));
      expect(cns.readiness, lessThan(1.0));

      final backRecovery = muscle.firstWhere((e) => e.muscle == 'Back').recoveryScore;
      final forearmsRecovery = muscle.firstWhere((e) => e.muscle == 'Forearms').recoveryScore;
      final chestRecovery = muscle.firstWhere((e) => e.muscle == 'Chest').recoveryScore;

      expect(backRecovery, lessThan(chestRecovery));
      expect(forearmsRecovery, lessThan(chestRecovery));
    });

    test('Running affects Quads, Hamstrings, Calves', () {
      final now = DateTime.now();
      final snapshot = const TrainingSnapshot(
        sets: [],
        exerciseMuscles: [],
      );

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

      final quadsRecovery = muscle.firstWhere((e) => e.muscle == 'Quads').recoveryScore;
      final chestRecovery = muscle.firstWhere((e) => e.muscle == 'Chest').recoveryScore;

      expect(quadsRecovery, lessThan(chestRecovery));
    });
  });
}
