import 'package:flutter_test/flutter_test.dart';
import 'package:herculex/core/utils/clock.dart';
import 'package:herculex/data/local/database.dart';
import 'package:herculex/features/analytics/domain/training_snapshot.dart';
import 'package:herculex/features/steps/data/step_repository.dart';
import 'package:herculex/features/steps/domain/step_lifting_correlation.dart';
import 'package:herculex/features/steps/domain/step_record.dart';
import 'package:herculex/features/steps/domain/step_score_engine.dart';
import 'package:herculex/features/steps/domain/step_weightlifting_impact.dart';
import 'package:herculex/features/workouts/domain/set_type.dart';

import '../../support/test_database.dart';

class _FakeClock implements Clock {
  final DateTime fixed;
  const _FakeClock(this.fixed);

  @override
  DateTime now() => fixed;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('StepRecord domain model', () {
    test('calculates biomechanical estimates when distance/kcal omitted', () {
      final record = StepRecord.fromStepCount(
        dateIso: '2026-10-14',
        stepCount: 10000,
        goal: 10000,
      );

      expect(record.stepCount, equals(10000));
      expect(record.goal, equals(10000));
      expect(record.progressRatio, equals(1.0));
      expect(record.progressPercentage, equals(100.0));
      expect(record.isGoalReached, isTrue);
      expect(record.remainingSteps, equals(0));
      // ~0.762m per step -> 7.62 km
      expect(record.distanceKm, closeTo(7.62, 0.05));
      // ~0.04 kcal per step -> 400 kcal
      expect(record.activeKcal, closeTo(400.0, 1.0));
      expect(record.activeMinutes, greaterThan(0));
    });

    test('preserves explicit distance and active calories when provided', () {
      final record = StepRecord.fromStepCount(
        dateIso: '2026-10-14',
        stepCount: 8500,
        goal: 10000,
        distanceKm: 6.8,
        activeKcal: 380.0,
        activeMinutes: 75,
      );

      expect(record.stepCount, equals(8500));
      expect(record.distanceKm, equals(6.8));
      expect(record.activeKcal, equals(380.0));
      expect(record.activeMinutes, equals(75));
      expect(record.progressRatio, closeTo(0.85, 0.01));
      expect(record.progressPercentage, closeTo(85.0, 0.1));
      expect(record.isGoalReached, isFalse);
      expect(record.remainingSteps, equals(1500));
    });
  });

  group('StepScoreEngine', () {
    test('classifies activity tiers accurately', () {
      expect(
        StepScoreEngine.determineZone(3000),
        equals(StepActivityZone.sedentary),
      );
      expect(
        StepScoreEngine.determineZone(6000),
        equals(StepActivityZone.lightlyActive),
      );
      expect(
        StepScoreEngine.determineZone(10000),
        equals(StepActivityZone.optimal),
      );
      expect(
        StepScoreEngine.determineZone(15000),
        equals(StepActivityZone.highNeat),
      );
      expect(
        StepScoreEngine.determineZone(20000),
        equals(StepActivityZone.exhaustive),
      );
      expect(
        StepScoreEngine.determineZone(28000),
        equals(StepActivityZone.extreme),
      );
    });

    test('computes high score for optimal step range reaching goal', () {
      final result = StepScoreEngine.calculate(steps: 10000, goal: 10000);
      expect(result.score, greaterThanOrEqualTo(85));
      expect(result.zone, equals(StepActivityZone.optimal));
      expect(result.statusLabel, contains('PRIME'));
    });

    test('flags sedentary status below 5000 steps', () {
      final result = StepScoreEngine.calculate(steps: 2500, goal: 10000);
      expect(result.score, lessThan(50));
      expect(result.zone, equals(StepActivityZone.sedentary));
      expect(result.statusLabel, equals('INSUFFICIENT'));
    });
  });

  group('StepWeightliftingEngine', () {
    test('protects full leg volume in optimal recovery zone', () {
      final impact = StepWeightliftingEngine.calculate(steps: 9500);

      expect(impact.lowerBodyVolumeFactor, equals(1.0));
      expect(impact.upperBodyVolumeFactor, equals(1.0));
      expect(impact.workCapacityScore, greaterThanOrEqualTo(90));
      expect(impact.recommendedIntraWorkoutCarbsGrams, lessThanOrEqualTo(20));
      expect(impact.legDayTacticalTip, contains('Goldilocks zone'));
    });

    test(
      'scales down leg volume and prompts carbs on exhaustive days (>18k)',
      () {
        final impact = StepWeightliftingEngine.calculate(steps: 19500);

        expect(impact.lowerBodyVolumeFactor, equals(0.80)); // -20% volume
        expect(
          impact.recommendedIntraWorkoutCarbsGrams,
          greaterThanOrEqualTo(40),
        );
        expect(impact.expectedRpeShift, greaterThanOrEqualTo(1.0));
        expect(impact.legDayTacticalTip, contains('RPE 8.0'));
      },
    );

    test('identifies sedentary pelvic tightness under 5k steps', () {
      final impact = StepWeightliftingEngine.calculate(steps: 2500);

      expect(impact.lowerBodyVolumeFactor, equals(1.0));
      expect(impact.legDayTacticalTip, contains('Tight hip flexors'));
      expect(impact.workCapacityLabel, contains('Stiff'));
    });
  });

  group('StepLiftingCorrelation', () {
    test('returns empty analysis with insufficient sample points', () {
      final empty = StepLiftingCorrelation.empty();
      expect(empty.stepsVsRpePoints, isEmpty);
      expect(empty.r2Rpe, equals(0.0));
      expect(empty.rpeInsight, contains('Insufficient'));
    });

    test(
      'computes regression points from matched workouts and health samples',
      () {
        final healthSamples = [
          HealthSampleData(
            id: 1,
            dateIso: '2026-10-10',
            kind: 'steps',
            value: 8000,
          ),
          HealthSampleData(
            id: 2,
            dateIso: '2026-10-11',
            kind: 'steps',
            value: 12000,
          ),
          HealthSampleData(
            id: 3,
            dateIso: '2026-10-12',
            kind: 'steps',
            value: 18000,
          ),
        ];

        final exercise = ExerciseCatalogData(
          id: 1,
          name: 'Back Squat',
          primaryMuscle: 'quadriceps',
          equipment: 'barbell',
          mechanics: 'compound',
          force: 'push',
          plane: 'vertical',
          defaultRestSeconds: 180,
          isCustom: false,
          category: 'strength',
          modality: 'barbell',
          cnsScore: 5,
          recoveryImpact: 4,
          loggingMetric: 'weight_reps',
          supportsWeightedBodyweight: false,
          isReviewed: true,
        );

        ResolvedSet makeSet({
          required int sessionId,
          required DateTime date,
          required int rpeX10,
          required double weight,
          required int reps,
        }) {
          final session = WorkoutSessionData(id: sessionId, startedAt: date);
          final workoutEx = WorkoutExerciseData(
            id: sessionId,
            sessionId: sessionId,
            exerciseId: 1,
            orderIndex: 0,
            plannedAllowsAdvancedTechniques: false,
          );
          final setEntry = SetEntryData(
            id: sessionId,
            workoutExerciseId: sessionId,
            setIndex: 0,
            weightKg: weight,
            reps: reps,
            rpeX10: rpeX10,
            isWarmup: false,
            isCompleted: true,
            completedAt: date,
            setType: 'standard',
          );
          return ResolvedSet(
            session: session,
            workoutExercise: workoutEx,
            exercise: exercise,
            set: setEntry,
            setType: SetType.fromId(setEntry.setType),
            bands: const [],
            accessoryNames: const [],
            forearmMultiplier: 1.0,
          );
        }

        final resolvedSets = [
          makeSet(
            sessionId: 1,
            date: DateTime(2026, 10, 10, 17, 0),
            rpeX10: 70, // RPE 7.0 on 8k steps
            weight: 100.0,
            reps: 5,
          ),
          makeSet(
            sessionId: 2,
            date: DateTime(2026, 10, 11, 17, 0),
            rpeX10: 80, // RPE 8.0 on 12k steps
            weight: 100.0,
            reps: 5,
          ),
          makeSet(
            sessionId: 3,
            date: DateTime(2026, 10, 12, 17, 0),
            rpeX10: 95, // RPE 9.5 on 18k steps
            weight: 100.0,
            reps: 5,
          ),
        ];

        final correlation = StepLiftingCorrelation.compute(
          healthSamples: healthSamples,
          resolvedSets: resolvedSets,
        );

        expect(correlation.stepsVsRpePoints.length, equals(3));
        expect(
          correlation.r2Rpe,
          greaterThan(0.8),
        ); // Strong linear relationship
        expect(correlation.rpeInsight, contains('RPE harder'));
      },
    );
  });

  group('StepRepository database integration', () {
    test('persists manual steps and retrieves record', () async {
      final db = await openTestDatabase();
      addTearDown(db.close);

      final fixedClock = _FakeClock(DateTime(2026, 10, 14, 12, 0));
      final repo = StepRepository(db, fixedClock);

      await repo.saveManualSteps(
        dateIso: '2026-10-14',
        stepCount: 11200,
        goal: 10000,
        distanceKm: 8.5,
        activeKcal: 450.0,
      );

      final record = await repo.getStepsForDate('2026-10-14');
      expect(record, isNotNull);
      expect(record!.stepCount, equals(11200));
      expect(record.distanceKm, equals(8.5));
      expect(record.activeKcal, equals(450.0));
      expect(record.isGoalReached, isTrue);
    });

    test('updates and queries custom global daily goal', () async {
      final db = await openTestDatabase();
      addTearDown(db.close);

      final fixedClock = _FakeClock(DateTime(2026, 10, 14, 12, 0));
      final repo = StepRepository(db, fixedClock);

      final initialGoal = await repo.getDailyGoal();
      expect(initialGoal, equals(10000));

      await repo.setDailyGoal(12500);
      final updatedGoal = await repo.getDailyGoal();
      expect(updatedGoal, equals(12500));
    });

    test('deletes steps for date', () async {
      final db = await openTestDatabase();
      addTearDown(db.close);

      final fixedClock = _FakeClock(DateTime(2026, 10, 14, 12, 0));
      final repo = StepRepository(db, fixedClock);

      await repo.saveManualSteps(dateIso: '2026-10-14', stepCount: 9000);

      var record = await repo.getStepsForDate('2026-10-14');
      expect(record, isNotNull);

      await repo.deleteStepsForDate('2026-10-14');
      record = await repo.getStepsForDate('2026-10-14');
      expect(record, isNull);
    });
  });
}
