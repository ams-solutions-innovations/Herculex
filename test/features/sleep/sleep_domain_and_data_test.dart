import 'package:flutter_test/flutter_test.dart';
import 'package:herculex/core/utils/clock.dart';
import 'package:herculex/data/local/database.dart';
import 'package:herculex/features/analytics/domain/training_snapshot.dart';
import 'package:herculex/features/sleep/data/sleep_repository.dart';
import 'package:herculex/features/sleep/domain/sleep_lifting_correlation.dart';
import 'package:herculex/features/sleep/domain/sleep_record.dart';
import 'package:herculex/features/sleep/domain/sleep_score_engine.dart';
import 'package:herculex/features/sleep/domain/sleep_weightlifting_impact.dart';
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

  group('SleepRecord & SleepStageBreakdown', () {
    test('calculates stage breakdown metrics correctly', () {
      final breakdown = SleepStageBreakdown.fromHours(
        deepHours: 1.5,
        remHours: 1.8,
        lightHours: 4.2,
        awakeHours: 0.5,
      );

      expect(breakdown.deepMinutes, closeTo(90.0, 0.01));
      expect(breakdown.remMinutes, closeTo(108.0, 0.01));
      expect(breakdown.lightMinutes, closeTo(252.0, 0.01));
      expect(breakdown.awakeMinutes, closeTo(30.0, 0.01));

      expect(breakdown.totalSleepMinutes, closeTo(450.0, 0.01));
      expect(breakdown.totalSleepHours, closeTo(7.5, 0.01));
      expect(breakdown.totalTimeInBedHours, closeTo(8.0, 0.01));

      // Percentages of actual sleep (90/450 = 20%, 108/450 = 24%, 252/450 = 56%)
      expect(breakdown.deepPercentage, closeTo(20.0, 0.01));
      expect(breakdown.remPercentage, closeTo(24.0, 0.01));
      expect(breakdown.lightPercentage, closeTo(56.0, 0.01));

      // Awake percentage of total in bed: 30 / 480 = 6.25%
      expect(breakdown.awakePercentage, closeTo(6.25, 0.01));
    });

    test('calculates sleep debt and efficiency correctly', () {
      final bedtime = DateTime(2026, 10, 13, 23, 0);
      final wakeTime = DateTime(
        2026,
        10,
        14,
        7,
        0,
      ); // 8 hours in bed (480 mins)

      final record = SleepRecord.fromHours(
        dateIso: '2026-10-14',
        totalHours: 7.2,
        bedtime: bedtime,
        wakeTime: wakeTime,
        deepHours: 1.44,
        remHours: 1.76,
        lightHours: 4.0,
        awakeHours: 0.8,
        targetHours: 8.0,
      );

      expect(record.sleepDebtHours, closeTo(0.8, 0.01));
      // In-bed is 7.2 + 0.8 = 8.0 hours; efficiency = 7.2 / 8.0 = 0.90
      expect(record.sleepEfficiency, closeTo(0.90, 0.01));
    });

    test('handles zero debt when exceeding target', () {
      final record = SleepRecord(
        dateIso: '2026-10-14',
        totalHours: 8.5,
        targetHours: 8.0,
      );
      expect(record.sleepDebtHours, equals(0.0));
      expect(record.sleepEfficiency, equals(1.0));
    });
  });

  group('SleepScoreEngine', () {
    test('awards optimal score for healthy 8h sleep with balanced stages', () {
      final record = SleepRecord.fromHours(
        dateIso: '2026-10-14',
        totalHours: 8.0,
        deepHours: 1.6, // 20%
        remHours: 1.76, // 22%
        lightHours: 4.64,
        awakeHours: 0.3,
        targetHours: 8.0,
      );

      final result = SleepScoreEngine.calculate(record);
      expect(result.score, greaterThanOrEqualTo(90));
      expect(result.category, equals(SleepRecoveryCategory.optimal));
    });

    test('penalizes short sleep duration and debt', () {
      final record = SleepRecord.fromHours(
        dateIso: '2026-10-14',
        totalHours: 5.0,
        targetHours: 8.0, // 3h debt
      );

      final result = SleepScoreEngine.calculate(record);
      expect(result.score, lessThan(60));
      expect(
        result.category,
        isIn([SleepRecoveryCategory.deficit, SleepRecoveryCategory.critical]),
      );
    });

    test('handles 0 hours sleep with critical categorization', () {
      final record = const SleepRecord(dateIso: '2026-10-14', totalHours: 0.0);

      final result = SleepScoreEngine.calculate(record);
      expect(result.score, equals(0));
      expect(result.category, equals(SleepRecoveryCategory.critical));
    });
  });

  group('SleepWeightliftingEngine', () {
    test('evaluates peak readiness on 8h+ sleep', () {
      final impact = SleepWeightliftingEngine.evaluate(
        sleepHours: 8.2,
        sleepDebt: 0.0,
        deepSleepHours: 1.7,
      );

      expect(impact.readinessLevel, equals(LiftingReadinessLevel.peak));
      expect(impact.cnsReadinessPercent, equals(100));
      expect(impact.volumeFactor, greaterThanOrEqualTo(1.0));
      expect(impact.injuryRisk, equals(InjuryRiskLevel.low));
      expect(impact.tacticalTips, isNotEmpty);
      expect(impact.cnsExplanation, contains('motor unit'));
      expect(impact.muscleRepairExplanation, contains('HGH'));
    });

    test('evaluates cautious readiness on 6h sleep', () {
      final impact = SleepWeightliftingEngine.evaluate(
        sleepHours: 6.0,
        sleepDebt: 2.0,
      );

      expect(impact.readinessLevel, equals(LiftingReadinessLevel.cautious));
      expect(impact.cnsReadinessPercent, equals(75));
      expect(impact.volumeFactor, lessThan(1.0));
      expect(impact.injuryRisk, equals(InjuryRiskLevel.moderate));
      expect(impact.statusBadge, contains('15%'));
    });

    test('evaluates compromised readiness on <5.5h sleep', () {
      final impact = SleepWeightliftingEngine.evaluate(
        sleepHours: 4.0,
        sleepDebt: 4.0,
      );

      expect(impact.readinessLevel, equals(LiftingReadinessLevel.compromised));
      expect(impact.cnsReadinessPercent, equals(60));
      expect(impact.volumeFactor, lessThanOrEqualTo(0.75));
      expect(impact.injuryRisk, equals(InjuryRiskLevel.high));
      expect(impact.maxRecommendedRpe, lessThanOrEqualTo(7.5));
    });
  });

  group('SleepLiftingCorrelation', () {
    test('computes correlation between historical sleep and gym sessions', () {
      final samples = [
        HealthSampleData(
          id: 1,
          dateIso: '2026-10-10',
          kind: 'sleep_hours',
          value: 8.5,
        ),
        HealthSampleData(
          id: 2,
          dateIso: '2026-10-11',
          kind: 'sleep_hours',
          value: 7.0,
        ),
        HealthSampleData(
          id: 3,
          dateIso: '2026-10-12',
          kind: 'sleep_hours',
          value: 5.5,
        ),
      ];

      final exercise = ExerciseCatalogData(
        id: 1,
        name: 'Bench Press',
        primaryMuscle: 'Chest',
        equipment: 'Barbell',
        mechanics: 'compound',
        force: 'push',
        plane: 'horizontal',
        defaultRestSeconds: 120,
        isCustom: false,
        category: 'strength',
        modality: 'barbell',
        cnsScore: 5,
        recoveryImpact: 3,
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
          date: DateTime(2026, 10, 10, 10, 0),
          rpeX10: 75, // RPE 7.5 on 8.5h sleep
          weight: 100.0,
          reps: 10,
        ),
        makeSet(
          sessionId: 2,
          date: DateTime(2026, 10, 11, 10, 0),
          rpeX10: 85, // RPE 8.5 on 7.0h sleep
          weight: 95.0,
          reps: 10,
        ),
        makeSet(
          sessionId: 3,
          date: DateTime(2026, 10, 12, 10, 0),
          rpeX10: 95, // RPE 9.5 on 5.5h sleep
          weight: 85.0,
          reps: 10,
        ),
      ];

      final correlation = SleepLiftingCorrelation.compute(
        healthSamples: samples,
        resolvedSets: resolvedSets,
      );

      expect(correlation.sleepVsRpePoints.length, equals(3));
      expect(correlation.sleepVsTonnagePoints.length, equals(3));
      expect(correlation.r2Rpe, greaterThan(0.9)); // Near-perfect linear fit
      expect(correlation.rpeInsight, contains('R²'));
      expect(correlation.tonnageInsight, isNotEmpty);
    });
  });

  group('SleepRepository database operations', () {
    test('saves and retrieves manual sleep record with stages', () async {
      final db = await openTestDatabase();
      addTearDown(db.close);

      final fixedTime = DateTime(2026, 10, 14, 9, 30);
      final clock = _FakeClock(fixedTime);
      final repo = SleepRepository(db, clock);

      final bedtime = DateTime(2026, 10, 13, 23, 15);
      final wakeTime = DateTime(2026, 10, 14, 7, 15);

      await repo.saveManualSleep(
        dateIso: '2026-10-14',
        totalHours: 7.75,
        bedtime: bedtime,
        wakeTime: wakeTime,
        deepHours: 1.6,
        remHours: 1.8,
        lightHours: 4.35,
        awakeHours: 0.25,
        restingHr: 54.0,
      );

      final record = await repo.getSleepForDate('2026-10-14');
      expect(record, isNotNull);
      expect(record!.dateIso, equals('2026-10-14'));
      expect(record.totalHours, closeTo(7.75, 0.01));
      expect(record.restingHr, equals(54.0));
      expect(record.stages, isNotNull);
      expect(record.stages!.deepMinutes, closeTo(96.0, 0.01));
      expect(record.bedtime, equals(bedtime));
      expect(record.wakeTime, equals(wakeTime));

      // Test history query
      final history = await repo.getSleepHistory(7);
      expect(history.length, equals(1));
      expect(history.first.dateIso, equals('2026-10-14'));

      // Test delete
      await repo.deleteSleepForDate('2026-10-14');
      final afterDelete = await repo.getSleepForDate('2026-10-14');
      expect(afterDelete, isNull);
    });
  });
}
