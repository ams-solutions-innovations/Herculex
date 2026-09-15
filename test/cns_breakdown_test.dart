import 'package:flutter_test/flutter_test.dart';
import 'package:herculex/data/local/database.dart';
import 'package:herculex/features/analytics/domain/cns_breakdown.dart';
import 'package:herculex/features/analytics/domain/training_snapshot.dart';
import 'package:herculex/features/workouts/domain/set_type.dart';

ExerciseCatalogData _ex(
  int id, {
  String name = 'Exercise',
  String primaryMuscle = 'Chest',
  int cns = 5,
  bool weightedBw = false,
}) => ExerciseCatalogData(
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
  modality: 'barbell',
  cnsScore: cns,
  recoveryImpact: 3,
  loggingMetric: 'weight_reps',
  supportsWeightedBodyweight: weightedBw,
  isReviewed: true,
);

WorkoutSessionData _session(
  int id,
  DateTime startedAt, {
  String name = 'Leg Day',
}) => WorkoutSessionData(id: id, startedAt: startedAt, name: name);

WorkoutExerciseData _we(int id, int exerciseId, {int sessionId = 1}) =>
    WorkoutExerciseData(
      id: id,
      sessionId: sessionId,
      exerciseId: exerciseId,
      orderIndex: 0,
      plannedAllowsAdvancedTechniques: false,
    );

SetEntryData _set(
  int id,
  int weId, {
  double weightKg = 100,
  int reps = 5,
  int? rpeX10 = 80,
  DateTime? completedAt,
  String setType = 'standard',
  double? bodyweightKg,
}) => SetEntryData(
  id: id,
  workoutExerciseId: weId,
  setIndex: 0,
  weightKg: weightKg,
  bodyweightKg: bodyweightKg,
  reps: reps,
  rpeX10: rpeX10,
  isWarmup: false,
  isCompleted: true,
  completedAt: completedAt,
  setType: setType,
);

ResolvedSet _resolved({
  required SetEntryData set,
  required WorkoutExerciseData we,
  required ExerciseCatalogData ex,
  WorkoutSessionData? session,
}) => ResolvedSet(
  set: set,
  workoutExercise: we,
  session: session ?? _session(we.sessionId, DateTime(2026, 6, 12, 9)),
  exercise: ex,
  setType: SetType.fromId(set.setType),
  bands: const [],
  accessoryNames: const [],
  forearmMultiplier: 1.0,
);

void main() {
  final asOf = DateTime(2026, 6, 12, 12);

  group('CnsBreakdownEngine', () {
    test('computes fresh state with 100% readiness on empty snapshot', () {
      const snapshot = TrainingSnapshot(sets: [], exerciseMuscles: []);
      final result = CnsBreakdownEngine.compute(snapshot: snapshot, asOf: asOf);

      expect(result.readiness, 1.0);
      expect(result.currentLoad, 0.0);
      expect(result.status, 'FRESH');
      expect(result.deloadSuggested, isFalse);
      expect(result.hoursToFullRecovery, 0.0);
      expect(result.recentSessions, isEmpty);
      expect(result.topCnsExercises, isEmpty);
      expect(result.trainingGuidance, contains('fully primed'));
    });

    test('computes session-by-session impact and residual decay accurately', () {
      final deadlift = _ex(1, name: 'Deadlift', primaryMuscle: 'Back', cns: 9);
      final session1 = _session(
        10,
        asOf.subtract(const Duration(hours: 12)),
        name: 'Heavy Pull',
      );
      final we1 = _we(100, deadlift.id, sessionId: session1.id);

      final sets = [
        _resolved(
          session: session1,
          we: we1,
          ex: deadlift,
          set: _set(
            1001,
            we1.id,
            weightKg: 180,
            rpeX10: 95, // RPE 9.5 -> 1.5 multiplier
            completedAt: asOf.subtract(const Duration(hours: 12)),
            setType: 'standard',
          ),
        ),
        _resolved(
          session: session1,
          we: we1,
          ex: deadlift,
          set: _set(
            1002,
            we1.id,
            weightKg: 160,
            rpeX10: 80, // RPE 8.0 -> 1.3 multiplier
            completedAt: asOf.subtract(const Duration(hours: 12)),
            setType: 'rest_pause', // cnsFactor = 1.2
          ),
        ),
      ];

      final snapshot = TrainingSnapshot(sets: sets, exerciseMuscles: const []);
      final result = CnsBreakdownEngine.compute(snapshot: snapshot, asOf: asOf);

      expect(result.recentSessions, hasLength(1));
      final sImpact = result.recentSessions.first;
      expect(sImpact.sessionId, session1.id);
      expect(sImpact.workoutName, 'Heavy Pull');
      expect(sImpact.setCount, 2);
      expect(sImpact.hasActiveResidualFatigue, isTrue);

      // Set 1: intensity = 9/10 = 0.9, rpeFactor = 1.5, setFactor = 1.0 -> setLoad = 1.35
      // Set 2: intensity = 9/10 = 0.9, rpeFactor = 1.3, setFactor = 1.2 -> setLoad = 1.404
      // Total session load = 1.35 + 1.404 = 2.754
      expect(sImpact.totalLoad, closeTo(2.754, 0.001));

      // Residual at 12 hours: factor = exp(-12 * ln2 / 36) = 2^(-1/3) ~ 0.7937
      // residual = 0.08 * 2.754 * 0.7937 ~ 0.1748
      expect(sImpact.currentResidualFatigue, greaterThan(0.15));
      expect(sImpact.currentResidualFatigue, lessThan(0.25));

      // Top exercises
      expect(result.topCnsExercises, hasLength(1));
      expect(result.topCnsExercises.first.exerciseName, 'Deadlift');
      expect(result.topCnsExercises.first.cnsScore, 9);
      expect(
        result.topCnsExercises.first.totalLoadContribution,
        closeTo(2.754, 0.001),
      );
    });

    test('weighted bodyweight exercise applies +2 CNS bonus', () {
      final pullup = _ex(
        2,
        name: 'Weighted Pull-up',
        primaryMuscle: 'Lats',
        cns: 6,
        weightedBw: true,
      );
      final session = _session(
        20,
        asOf.subtract(const Duration(hours: 4)),
        name: 'Upper Body',
      );
      final we = _we(200, pullup.id, sessionId: session.id);

      final sets = [
        _resolved(
          session: session,
          we: we,
          ex: pullup,
          set: _set(
            2001,
            we.id,
            weightKg: 20,
            bodyweightKg: 80,
            rpeX10: 70, // RPE 7.0 -> 1.0 multiplier
            completedAt: asOf.subtract(const Duration(hours: 4)),
          ),
        ),
      ];

      final snapshot = TrainingSnapshot(sets: sets, exerciseMuscles: const []);
      final result = CnsBreakdownEngine.compute(snapshot: snapshot, asOf: asOf);

      final setImpact = result.recentSessions.first.sets.first;
      expect(setImpact.baseCnsScore, 6);
      expect(setImpact.effectiveCnsScore, 8); // 6 + 2 = 8
      expect(setImpact.hasWeightedBonus, isTrue);
      // setLoad = (8 / 10) * 1.0 * 1.0 = 0.8
      expect(setImpact.setLoad, closeTo(0.8, 0.001));
    });

    test(
      'recovers over time: older sessions beyond 96h have zero residual fatigue',
      () {
        final bench = _ex(
          3,
          name: 'Bench Press',
          primaryMuscle: 'Chest',
          cns: 7,
        );
        final oldSession = _session(
          30,
          asOf.subtract(const Duration(hours: 120)),
          name: 'Past Push Day',
        );
        final we = _we(300, bench.id, sessionId: oldSession.id);

        final sets = [
          _resolved(
            session: oldSession,
            we: we,
            ex: bench,
            set: _set(
              3001,
              we.id,
              completedAt: asOf.subtract(const Duration(hours: 120)),
            ),
          ),
        ];

        final snapshot = TrainingSnapshot(
          sets: sets,
          exerciseMuscles: const [],
        );
        final result = CnsBreakdownEngine.compute(
          snapshot: snapshot,
          asOf: asOf,
        );

        expect(result.recentSessions.first.currentResidualFatigue, 0.0);
        expect(result.recentSessions.first.hasActiveResidualFatigue, isFalse);
        expect(result.readiness, 1.0);
      },
    );

    test('computes ACWR and recovery ETA correctly', () {
      final squat = _ex(4, name: 'Squat', primaryMuscle: 'Quads', cns: 8);
      final recentSession = _session(
        40,
        asOf.subtract(const Duration(hours: 2)),
        name: 'Heavy Squats',
      );
      final we = _we(400, squat.id, sessionId: recentSession.id);

      // Add heavy volume recently (high acute load)
      final sets = [
        for (var i = 0; i < 6; i++)
          _resolved(
            session: recentSession,
            we: we,
            ex: squat,
            set: _set(
              4000 + i,
              we.id,
              weightKg: 140,
              rpeX10: 90,
              completedAt: asOf.subtract(const Duration(hours: 2)),
            ),
          ),
      ];

      final snapshot = TrainingSnapshot(sets: sets, exerciseMuscles: const []);
      final result = CnsBreakdownEngine.compute(snapshot: snapshot, asOf: asOf);

      expect(result.acuteWeeklyLoad, greaterThan(0));
      expect(result.hoursToFullRecovery, greaterThan(0));
      expect(result.currentLoad, greaterThan(0.2));
    });
  });
}
