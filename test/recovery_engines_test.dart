import 'package:flutter_test/flutter_test.dart';
import 'package:health/health.dart';
import 'package:herculex/data/local/database.dart';
import 'package:herculex/features/analytics/domain/cns_trends.dart';
import 'package:herculex/features/analytics/domain/muscle_recovery_v3.dart';
import 'package:herculex/features/analytics/domain/muscle_volume_trend.dart';
import 'package:herculex/features/analytics/domain/training_snapshot.dart';
import 'package:herculex/features/analytics/domain/weekly_muscle_volume.dart';
import 'package:herculex/features/recovery/domain/deload_urgency.dart';
import 'package:herculex/features/recovery/domain/joint_stress_advisor.dart';
import 'package:herculex/features/recovery/domain/muscle_deload_advisor.dart';
import 'package:herculex/features/recovery/domain/training_suggestion.dart';
import 'package:herculex/features/workouts/domain/set_type.dart';

// ── Factories (same shape as test/phase3_engines_test.dart — Dart's
// per-file privacy means these can't be shared without a new public helper
// module, so this mirrors that file's own convention rather than inventing
// one) ───────────────────────────────────────────────────────────────────

ExerciseCatalogData _ex(
  int id, {
  String name = 'Exercise',
  String primaryMuscle = 'Chest',
  String modality = 'barbell',
  int cns = 5,
  int recoveryImpact = 3,
  bool weightedBw = false,
}) =>
    ExerciseCatalogData(
      id: id,
      name: name,
      primaryMuscle: primaryMuscle,
      equipment: 'Barbell',
      mechanics: 'compound',
      force: 'push',
      plane: 'horizontal',
      defaultRestSeconds: 120,
      isCustom: false,
      category: 'strength',
      modality: modality,
      cnsScore: cns,
      recoveryImpact: recoveryImpact,
      loggingMetric: 'weight_reps',
      supportsWeightedBodyweight: weightedBw,
      isReviewed: true,
    );

WorkoutSessionData _session(int id, DateTime startedAt, {int? gymId}) =>
    WorkoutSessionData(id: id, startedAt: startedAt, gymId: gymId);

WorkoutExerciseData _we(int id, int exerciseId, {int sessionId = 1, String? variant}) =>
    WorkoutExerciseData(
      id: id,
      sessionId: sessionId,
      exerciseId: exerciseId,
      orderIndex: 0,
      equipmentVariant: variant,
    );

SetEntryData _set(
  int id,
  int weId, {
  double weightKg = 100,
  int reps = 5,
  int? rpeX10 = 80,
  DateTime? completedAt,
  String setType = 'standard',
}) =>
    SetEntryData(
      id: id,
      workoutExerciseId: weId,
      setIndex: 0,
      weightKg: weightKg,
      reps: reps,
      rpeX10: rpeX10,
      isWarmup: false,
      isCompleted: true,
      completedAt: completedAt ?? DateTime(2026, 6, 12, 10),
      setType: setType,
    );

ResolvedSet _resolved({
  required SetEntryData set,
  required WorkoutExerciseData we,
  required ExerciseCatalogData ex,
  WorkoutSessionData? session,
}) =>
    ResolvedSet(
      set: set,
      workoutExercise: we,
      session: session ?? _session(we.sessionId, DateTime(2026, 6, 12, 9)),
      exercise: ex,
      setType: SetType.fromId(set.setType),
      bands: const [],
      accessoryNames: const [],
      forearmMultiplier: 1.0,
    );

ExerciseMuscleData _muscle(int id, int exId, String muscle, String role) =>
    ExerciseMuscleData(id: id, exerciseId: exId, muscle: muscle, role: role, contribution: 1);

HealthDataPoint _workout(
  HealthWorkoutActivityType type,
  DateTime from,
  DateTime to, {
  int? totalDistance,
}) =>
    HealthDataPoint(
      uuid: 'test-${from.millisecondsSinceEpoch}-${to.millisecondsSinceEpoch}',
      value: WorkoutHealthValue(
        workoutActivityType: type,
        totalDistance: totalDistance,
        totalDistanceUnit: totalDistance == null ? null : HealthDataUnit.METER,
      ),
      type: HealthDataType.WORKOUT,
      unit: HealthDataUnit.NO_UNIT,
      dateFrom: from,
      dateTo: to,
      sourcePlatform: HealthPlatformType.appleHealth,
      sourceDeviceId: 'test-device',
      sourceId: 'test-source',
      sourceName: 'test',
    );

const _noCnsDeload = CnsTrendsResult(
  daily: [],
  currentLoad: 0,
  deloadSuggested: false,
  acuteWeeklyLoad: 0,
  chronicWeeklyLoad: 0,
);

final _asOf = DateTime(2026, 6, 12, 12);

void main() {
  group('MuscleRecoveryV3.recoveryEtaHours', () {
    test('every muscle is already recovered on an empty snapshot', () {
      final eta = MuscleRecoveryV3.recoveryEtaHours(
        snapshot: const TrainingSnapshot(sets: [], exerciseMuscles: []),
        asOf: _asOf,
      );
      expect(eta, hasLength(19));
      expect(eta.values.every((h) => h == null), isTrue);
    });

    test('a fresh heavy set produces a positive, bounded ETA and agrees with compute()', () {
      final squat = _ex(1, primaryMuscle: 'Quads', recoveryImpact: 5);
      final muscles = [_muscle(1, 1, 'Quads', 'primary')];
      final snapshot = TrainingSnapshot(
        sets: [_resolved(set: _set(1, 1, rpeX10: 95, completedAt: _asOf), we: _we(1, 1), ex: squat)],
        exerciseMuscles: muscles,
      );

      final score = MuscleRecoveryV3.compute(snapshot: snapshot, asOf: _asOf)
          .singleWhere((r) => r.muscle == 'Quads')
          .recoveryScore;
      final eta = MuscleRecoveryV3.recoveryEtaHours(snapshot: snapshot, asOf: _asOf)['Quads'];

      expect(score, lessThan(MuscleRecoveryV3.recoveredScoreThreshold));
      expect(eta, isNotNull);
      expect(eta!, greaterThan(0));
      expect(eta, lessThan(MuscleRecoveryV3.maxEtaHorizonHours));
    });

    test('ETA decreases by ~1 hour when asOf advances by 1 hour', () {
      final squat = _ex(1, primaryMuscle: 'Quads', recoveryImpact: 5);
      final muscles = [_muscle(1, 1, 'Quads', 'primary')];
      final completedAt = DateTime(2026, 6, 10, 8);
      final sets = [
        for (var i = 0; i < 8; i++)
          _resolved(set: _set(i, 1, rpeX10: 95, completedAt: completedAt), we: _we(1, 1), ex: squat),
      ];
      final snapshot = TrainingSnapshot(sets: sets, exerciseMuscles: muscles);

      final etaAtT = MuscleRecoveryV3.recoveryEtaHours(
        snapshot: snapshot,
        asOf: completedAt.add(const Duration(hours: 2)),
      )['Quads'];
      final etaAtTPlus1 = MuscleRecoveryV3.recoveryEtaHours(
        snapshot: snapshot,
        asOf: completedAt.add(const Duration(hours: 3)),
      )['Quads'];

      expect(etaAtT, isNotNull);
      expect(etaAtTPlus1, isNotNull);
      expect(etaAtT! - etaAtTPlus1!, closeTo(1.0, 0.05));
    });

    test('caps at maxEtaHorizonHours for a pathological stacked-fatigue case', () {
      final squat = _ex(1, primaryMuscle: 'Quads', recoveryImpact: 5);
      final muscles = [_muscle(1, 1, 'Quads', 'primary')];
      final sets = [
        for (var i = 0; i < 40; i++)
          _resolved(set: _set(i, 1, rpeX10: 95, completedAt: _asOf), we: _we(1, 1), ex: squat),
      ];
      final eta = MuscleRecoveryV3.recoveryEtaHours(
        snapshot: TrainingSnapshot(sets: sets, exerciseMuscles: muscles),
        asOf: _asOf,
      );
      expect(eta['Quads'], MuscleRecoveryV3.maxEtaHorizonHours);
    });

    test('sorts computed results from least recovered (lowest score) to most recovered (highest score)', () {
      final squat = _ex(1, primaryMuscle: 'Quads', recoveryImpact: 5);
      final bench = _ex(2, primaryMuscle: 'Chest', recoveryImpact: 2);
      final muscles = [
        _muscle(1, 1, 'Quads', 'primary'),
        _muscle(2, 2, 'Chest', 'primary'),
      ];
      final snapshot = TrainingSnapshot(
        sets: [
          // Heavy quad sets -> low quad recovery score (~30)
          for (var i = 0; i < 5; i++)
            _resolved(set: _set(i, 1, rpeX10: 95, completedAt: _asOf), we: _we(1, 1), ex: squat),
          // Light chest set -> higher chest recovery score (~80)
          _resolved(set: _set(10, 2, rpeX10: 60, completedAt: _asOf), we: _we(2, 2), ex: bench),
        ],
        exerciseMuscles: muscles,
      );

      final results = MuscleRecoveryV3.compute(snapshot: snapshot, asOf: _asOf);

      for (var i = 0; i < results.length - 1; i++) {
        expect(
          results[i].recoveryScore,
          lessThanOrEqualTo(results[i + 1].recoveryScore),
          reason: 'Item $i (${results[i].muscle}: ${results[i].recoveryScore}) should be <= Item ${i + 1} (${results[i + 1].muscle}: ${results[i + 1].recoveryScore})',
        );
      }
      expect(results.first.muscle, 'Quads');
    });
  });

  group('MuscleVolumeTrends', () {
    test('zero-fills weeks with no training and averages correctly', () {
      final bench = _ex(1, primaryMuscle: 'Chest');
      final muscles = [_muscle(1, 1, 'Chest', 'primary')];
      final sets = [
        for (var i = 0; i < 4; i++)
          _resolved(
            set: _set(i, 1, completedAt: _asOf.subtract(const Duration(hours: 2))),
            we: _we(1, 1),
            ex: bench,
          ),
      ];
      final trends = MuscleVolumeTrends.compute(
        snapshot: TrainingSnapshot(sets: sets, exerciseMuscles: muscles),
        asOf: _asOf,
        weekCount: 4,
      );
      final chest = trends['Chest']!;

      expect(chest.weeks, hasLength(4));
      expect(chest.weeks.take(3).every((w) => w.sets == 0), isTrue);
      expect(chest.weeks.last.sets, 4);
      expect(chest.averageWeeklySets, 1.0);
    });

    test('trend slope is positive when ramping and negative when tapering', () {
      final bench = _ex(1, primaryMuscle: 'Chest');
      final muscles = [_muscle(1, 1, 'Chest', 'primary')];
      final firstWeekStart = WeeklyMuscleVolume.weekStartOf(_asOf).subtract(const Duration(days: 21));

      List<ResolvedSet> setsFor(List<int> weeklyCounts) {
        final sets = <ResolvedSet>[];
        var id = 0;
        for (var week = 0; week < weeklyCounts.length; week++) {
          final at = firstWeekStart.add(Duration(days: 7 * week + 1, hours: 10));
          for (var i = 0; i < weeklyCounts[week]; i++) {
            sets.add(_resolved(set: _set(id++, 1, completedAt: at), we: _we(1, 1), ex: bench));
          }
        }
        return sets;
      }

      final ramping = MuscleVolumeTrends.compute(
        snapshot: TrainingSnapshot(sets: setsFor([2, 4, 6, 8]), exerciseMuscles: muscles),
        asOf: _asOf,
        weekCount: 4,
      );
      expect(ramping['Chest']!.trendSlopePerWeek, greaterThan(0));

      final tapering = MuscleVolumeTrends.compute(
        snapshot: TrainingSnapshot(sets: setsFor([8, 6, 4, 2]), exerciseMuscles: muscles),
        asOf: _asOf,
        weekCount: 4,
      );
      expect(tapering['Chest']!.trendSlopePerWeek, lessThan(0));
    });
  });

  group('MuscleDeloadAdvisor', () {
    test('recommended when a muscle chronically breaches MRV and stays fatigued', () {
      final squat = _ex(1, primaryMuscle: 'Quads', recoveryImpact: 5);
      final muscles = [_muscle(1, 1, 'Quads', 'primary')];
      // 4 heavy sets every day for 30 days: >20 sets/week (Quads' MRV) in
      // every trailing week, and dense enough that the 96h fatigue window
      // always has recent sets, so recovery never climbs back above 30.
      final sets = [
        for (var day = 0; day < 30; day++)
          for (var i = 0; i < 4; i++)
            _resolved(
              set: _set(
                day * 10 + i,
                1,
                rpeX10: 95,
                completedAt: _asOf.subtract(Duration(days: day, hours: 8)),
              ),
              we: _we(1, 1),
              ex: squat,
            ),
      ];
      final snapshot = TrainingSnapshot(sets: sets, exerciseMuscles: muscles);
      final signals = MuscleDeloadAdvisor.compute(
        snapshot: snapshot,
        externalWorkouts: const [],
        asOf: _asOf,
        cnsTrends: _noCnsDeload, // proves the recommendation isn't riding on CNS corroboration
      );

      final quads = signals.singleWhere((s) => s.muscle == 'Quads');
      expect(quads.chronicMrvBreach, isTrue);
      expect(quads.sustainedLowRecovery, isTrue);
      expect(quads.urgency, DeloadUrgency.recommended);

      final chest = signals.singleWhere((s) => s.muscle == 'Chest');
      expect(chest.urgency, DeloadUrgency.none);
    });

    test('watch tier when volume breaches MRV but recovery isn\'t sustained-low, with CNS corroboration', () {
      final squat = _ex(1, primaryMuscle: 'Quads', recoveryImpact: 1);
      final muscles = [_muscle(1, 1, 'Quads', 'primary')];
      // One low-RPE, low-impact 45-set session per week (fast-decaying, so
      // recovery bounces back well above 30 within about a day) — set count
      // still clears the 20/week MRV, but fatigue doesn't linger.
      final sets = [
        for (var week = 0; week < 5; week++)
          for (var i = 0; i < 45; i++)
            _resolved(
              set: _set(
                week * 100 + i,
                1,
                rpeX10: 60,
                completedAt: _asOf.subtract(Duration(days: 7 * week, hours: 10)),
              ),
              we: _we(1, 1),
              ex: squat,
            ),
      ];
      final signals = MuscleDeloadAdvisor.compute(
        snapshot: TrainingSnapshot(sets: sets, exerciseMuscles: muscles),
        externalWorkouts: const [],
        asOf: _asOf,
        cnsTrends: const CnsTrendsResult(
          daily: [],
          currentLoad: 0,
          deloadSuggested: true,
          acuteWeeklyLoad: 0,
          chronicWeeklyLoad: 0,
        ),
      );

      final quads = signals.singleWhere((s) => s.muscle == 'Quads');
      expect(quads.chronicMrvBreach, isTrue);
      expect(quads.sustainedLowRecovery, isFalse);
      expect(quads.corroboratedByCns, isTrue);
      expect(quads.urgency, DeloadUrgency.watch);
    });
  });

  group('JointStressAdvisor', () {
    List<ResolvedSet> heavyQuadsSets(int setsPerWeek, int weeks) {
      final squat = _ex(1, primaryMuscle: 'Quads', recoveryImpact: 5);
      return [
        for (var week = 0; week < weeks; week++)
          for (var i = 0; i < setsPerWeek; i++)
            _resolved(
              set: _set(
                week * 1000 + i,
                1,
                rpeX10: 90,
                completedAt: _asOf.subtract(Duration(days: 7 * week + 1)),
              ),
              we: _we(1, 1),
              ex: squat,
            ),
      ];
    }

    final quadsMuscleRow = [_muscle(1, 1, 'Quads', 'primary')];

    test('never recommends an unflagged joint regardless of load', () {
      final snapshot = TrainingSnapshot(
        sets: heavyQuadsSets(45, 8),
        exerciseMuscles: quadsMuscleRow,
      );
      final result = JointStressAdvisor.evaluate(
        joint: 'Knee',
        flaggedSince: null,
        snapshot: snapshot,
        wideExternalWorkouts: const [],
        asOf: _asOf,
      );
      expect(result.isFlagged, isFalse);
      expect(result.urgency, DeloadUrgency.none);
    });

    test('a flagged joint with elevated muscle volume surfaces its top contributing muscle', () {
      final snapshot = TrainingSnapshot(
        sets: heavyQuadsSets(45, 8),
        exerciseMuscles: quadsMuscleRow,
      );
      final result = JointStressAdvisor.evaluate(
        joint: 'Knee',
        flaggedSince: _asOf.subtract(const Duration(days: 3)),
        snapshot: snapshot,
        wideExternalWorkouts: const [],
        asOf: _asOf,
      );
      expect(result.isFlagged, isTrue);
      expect(result.urgency, isNot(DeloadUrgency.none));
      expect(result.topContributingMuscles, contains('Quads'));
    });

    test('cardio distance raises the knee load index even with no gym training', () {
      const snapshot = TrainingSnapshot(sets: [], exerciseMuscles: []);
      final withoutCardio = JointStressAdvisor.evaluate(
        joint: 'Knee',
        flaggedSince: _asOf,
        snapshot: snapshot,
        wideExternalWorkouts: const [],
        asOf: _asOf,
      );

      final runs = [
        for (var week = 0; week < 8; week++)
          _workout(
            HealthWorkoutActivityType.RUNNING,
            _asOf.subtract(Duration(days: 7 * week, hours: 2)),
            _asOf.subtract(Duration(days: 7 * week, hours: 1)),
            totalDistance: 10000,
          ),
      ];
      final withCardio = JointStressAdvisor.evaluate(
        joint: 'Knee',
        flaggedSince: _asOf,
        snapshot: snapshot,
        wideExternalWorkouts: runs,
        asOf: _asOf,
      );

      expect(withoutCardio.relativeLoadIndex, 0);
      expect(withCardio.cardioContributed, isTrue);
      expect(withCardio.relativeLoadIndex, greaterThan(withoutCardio.relativeLoadIndex));
      expect(withCardio.cardioDistanceKm, closeTo(80.0, 0.01));
    });
  });

  group('TrainingSuggestionEngine', () {
    List<MuscleGroupRecovery> recoveryWhere(bool Function(String muscle) inCategory,
        {int high = 90, int low = 20}) {
      return [
        for (final m in MuscleRecoveryV3.groups)
          MuscleGroupRecovery(muscle: m, recoveryScore: inCategory(m) ? high : low, weeklySets: 0),
      ];
    }

    test('suggests the category with the highest average recovery', () {
      final recovery =
          recoveryWhere((m) => MuscleCategories.byMuscle[m] == MuscleCategory.pull);
      final suggestion = TrainingSuggestionEngine.suggest(
        recovery: recovery,
        deloadSignals: const [],
        jointStress: const [],
      );
      expect(suggestion.bestCategory, MuscleCategory.pull);
      expect(suggestion.readyMuscles, isNotEmpty);
    });

    test('excludes a muscle flagged for deload even at a qualifying score', () {
      final recovery = recoveryWhere((m) => MuscleCategories.byMuscle[m] == MuscleCategory.push);
      final deloadSignals = [
        const MuscleDeloadSignal(
          muscle: 'Chest',
          urgency: DeloadUrgency.recommended,
          chronicMrvBreach: true,
          sustainedLowRecovery: true,
          corroboratedByCns: false,
        ),
      ];
      final suggestion = TrainingSuggestionEngine.suggest(
        recovery: recovery,
        deloadSignals: deloadSignals,
        jointStress: const [],
      );
      expect(suggestion.bestCategory, MuscleCategory.push);
      expect(suggestion.readyMuscles, isNot(contains('Chest')));
      expect(suggestion.excludedDeload, contains('Chest'));
    });

    test('excludes a muscle that heavily loads a flagged, over-threshold joint', () {
      final recovery = recoveryWhere((m) => MuscleCategories.byMuscle[m] == MuscleCategory.legs);
      final jointStress = [
        const JointStressResult(
          joint: 'Knee',
          isFlagged: true,
          flaggedSince: null,
          topContributingMuscles: ['Quads'],
          relativeLoadIndex: 1.2,
          cardioContributed: false,
          cardioDistanceKm: 0,
          urgency: DeloadUrgency.recommended,
          explanation: 'test',
        ),
      ];
      final suggestion = TrainingSuggestionEngine.suggest(
        recovery: recovery,
        deloadSignals: const [],
        jointStress: jointStress,
      );
      expect(suggestion.readyMuscles, isNot(contains('Quads')));
      expect(suggestion.excludedJointPain, contains('Quads'));
    });
  });

  group('Personalized Recovery & Deload Refinements', () {
    test('Hip Flexors exercise damps Quads fatigue contribution to 0.25x', () {
      final ex = _ex(101, name: 'Hanging Leg Raise', primaryMuscle: 'Abs');
      final we = _we(1, 101);
      final set = _set(1, 1, rpeX10: null, completedAt: DateTime(2026, 6, 12, 10));
      final resolved = _resolved(set: set, we: we, ex: ex);

      final muscles = [
        _muscle(1, 101, 'Abs', 'primary'),
        _muscle(2, 101, 'Hip Flexors', 'primary'),
      ];

      final snapshot = TrainingSnapshot(
        sets: [resolved],
        exerciseMuscles: muscles,
      );

      final result = MuscleRecoveryV3.compute(
        snapshot: snapshot,
        asOf: DateTime(2026, 6, 12, 10, 30),
      );

      final absRecovery = result.firstWhere((r) => r.muscle == 'Abs');
      final quadsRecovery = result.firstWhere((r) => r.muscle == 'Quads');

      // Abs takes full primary load (lower score), Quads takes dampened 0.25x load (high score > 90)
      expect(absRecovery.recoveryScore, lessThan(quadsRecovery.recoveryScore));
      expect(quadsRecovery.recoveryScore, greaterThanOrEqualTo(90));
    });

    test('Omitted RPE produces standard 1.0x fatigue without artificial penalty', () {
      final ex = _ex(102, name: 'Bench Press', primaryMuscle: 'Chest');
      final we = _we(1, 102);
      final setNoRpe = _set(1, 1, rpeX10: null, completedAt: DateTime(2026, 6, 12, 10));
      final setRpe7 = _set(2, 1, rpeX10: 70, completedAt: DateTime(2026, 6, 12, 10));
      final setRpe9 = _set(3, 1, rpeX10: 90, completedAt: DateTime(2026, 6, 12, 10));

      final snapNoRpe = TrainingSnapshot(
        sets: [_resolved(set: setNoRpe, we: we, ex: ex)],
        exerciseMuscles: const [],
      );
      final snapRpe7 = TrainingSnapshot(
        sets: [_resolved(set: setRpe7, we: we, ex: ex)],
        exerciseMuscles: const [],
      );
      final snapRpe9 = TrainingSnapshot(
        sets: [_resolved(set: setRpe9, we: we, ex: ex)],
        exerciseMuscles: const [],
      );

      final resNoRpe = MuscleRecoveryV3.compute(snapshot: snapNoRpe, asOf: DateTime(2026, 6, 12, 11));
      final resRpe7 = MuscleRecoveryV3.compute(snapshot: snapRpe7, asOf: DateTime(2026, 6, 12, 11));
      final resRpe9 = MuscleRecoveryV3.compute(snapshot: snapRpe9, asOf: DateTime(2026, 6, 12, 11));

      final chestNoRpe = resNoRpe.firstWhere((r) => r.muscle == 'Chest').recoveryScore;
      final chestRpe7 = resRpe7.firstWhere((r) => r.muscle == 'Chest').recoveryScore;
      final chestRpe9 = resRpe9.firstWhere((r) => r.muscle == 'Chest').recoveryScore;

      expect(chestNoRpe, equals(chestRpe7));
      expect(chestRpe9, lessThan(chestNoRpe));
    });

    test('Walking workout is skipped when health history is < 30 days', () {
      final walkingWorkout = _workout(
        HealthWorkoutActivityType.WALKING,
        DateTime(2026, 6, 12, 9),
        DateTime(2026, 6, 12, 10),
        totalDistance: 5000,
      );

      const emptySnapshot = TrainingSnapshot(
        sets: [],
        exerciseMuscles: [],
      );

      // With < 30 days history: walking should not fatigue Quads
      final resultNewUser = MuscleRecoveryV3.compute(
        snapshot: emptySnapshot,
        externalWorkouts: [walkingWorkout],
        asOf: DateTime(2026, 6, 12, 11),
        daysOfHealthHistory: 10,
      );

      final quadsNew = resultNewUser.firstWhere((r) => r.muscle == 'Quads');
      expect(quadsNew.recoveryScore, equals(100));

      // With >= 30 days history: walking adds calibrated light fatigue
      final resultEstablishedUser = MuscleRecoveryV3.compute(
        snapshot: emptySnapshot,
        externalWorkouts: [walkingWorkout],
        asOf: DateTime(2026, 6, 12, 11),
        daysOfHealthHistory: 35,
      );

      final quadsEstablished = resultEstablishedUser.firstWhere((r) => r.muscle == 'Quads');
      expect(quadsEstablished.recoveryScore, lessThan(100));
      expect(quadsEstablished.recoveryScore, greaterThan(80)); // Still mild, not crushing
    });

    test('CnsTrends does not falsely suggest a deload on 2 weeks of training data', () {
      final asOf = DateTime(2026, 6, 28, 12);
      final ex = _ex(103, name: 'Squat', primaryMuscle: 'Quads', cns: 7, recoveryImpact: 4);
      final we = _we(1, 103);

      // Create 4 workouts spread across the last 12 days (started 12 days ago)
      final sets = [
        _resolved(set: _set(1, 1, completedAt: asOf.subtract(const Duration(days: 12))), we: we, ex: ex),
        _resolved(set: _set(2, 1, completedAt: asOf.subtract(const Duration(days: 9))), we: we, ex: ex),
        _resolved(set: _set(3, 1, completedAt: asOf.subtract(const Duration(days: 5))), we: we, ex: ex),
        _resolved(set: _set(4, 1, completedAt: asOf.subtract(const Duration(days: 2))), we: we, ex: ex),
      ];

      final snapshot = TrainingSnapshot(
        sets: sets,
        exerciseMuscles: const [],
      );

      final cnsResult = CnsTrends.compute(snapshot: snapshot, asOf: asOf);

      // Should NOT suggest deload because user only has 12 days of history (< 21 days)
      expect(cnsResult.deloadSuggested, isFalse);
      expect(cnsResult.recommendation, isNot(contains('schedule a deload week')));
    });
  });
}
