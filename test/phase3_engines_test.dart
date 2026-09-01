import 'package:flutter_test/flutter_test.dart';
import 'package:herculex/data/local/database.dart';
import 'package:herculex/features/analytics/domain/cns_trends.dart';
import 'package:herculex/features/analytics/domain/muscle_recovery_v3.dart';
import 'package:herculex/features/analytics/domain/training_snapshot.dart';
import 'package:herculex/features/analytics/domain/variant_performance.dart';
import 'package:herculex/features/workouts/domain/effective_load.dart';
import 'package:herculex/features/workouts/domain/progression_engine.dart';
import 'package:herculex/features/workouts/domain/set_type.dart';

// ── Factories ────────────────────────────────────────────────────────────────

ExerciseCatalogData _ex(
  int id, {
  String name = 'Exercise',
  String primaryMuscle = 'Chest',
  String modality = 'barbell',
  int cns = 5,
  int recoveryImpact = 3,
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
  modality: modality,
  cnsScore: cns,
  recoveryImpact: recoveryImpact,
  loggingMetric: 'weight_reps',
  supportsWeightedBodyweight: weightedBw,
  isReviewed: true,
);

WorkoutSessionData _session(int id, DateTime startedAt, {int? gymId}) =>
    WorkoutSessionData(id: id, startedAt: startedAt, gymId: gymId);

WorkoutExerciseData _we(
  int id,
  int exerciseId, {
  int sessionId = 1,
  String? variant,
}) => WorkoutExerciseData(
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
  double? bodyweightKg,
  double? chainsKg,
}) => SetEntryData(
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
  bodyweightKg: bodyweightKg,
  chainsKg: chainsKg,
);

ResolvedSet _resolved({
  required SetEntryData set,
  required WorkoutExerciseData we,
  required ExerciseCatalogData ex,
  WorkoutSessionData? session,
  List<BandContribution> bands = const [],
  List<String> accessories = const [],
  double forearmMultiplier = 1.0,
}) => ResolvedSet(
  set: set,
  workoutExercise: we,
  session: session ?? _session(we.sessionId, DateTime(2026, 6, 12, 9)),
  exercise: ex,
  setType: SetType.fromId(set.setType),
  bands: bands,
  accessoryNames: accessories,
  forearmMultiplier: forearmMultiplier,
);

ExerciseMuscleData _muscle(int id, int exId, String muscle, String role) =>
    ExerciseMuscleData(
      id: id,
      exerciseId: exId,
      muscle: muscle,
      role: role,
      contribution: 1,
    );

final _asOf = DateTime(2026, 6, 12, 12);

void main() {
  group('ResolvedSet', () {
    test(
      'effective load includes bodyweight only for weighted-BW exercises',
      () {
        final pullup = _ex(1, weightedBw: true, modality: 'bodyweight');
        final rs = _resolved(
          set: _set(1, 1, weightKg: 25, bodyweightKg: 80),
          we: _we(1, 1),
          ex: pullup,
        );
        expect(rs.effectiveKg, 105);

        final bench = _ex(2);
        final rs2 = _resolved(
          set: _set(2, 2, weightKg: 100, bodyweightKg: 80),
          we: _we(2, 2),
          ex: bench,
        );
        expect(rs2.effectiveKg, 100);
      },
    );

    test('weighted bodyweight bumps CNS by +2 capped at 10', () {
      final ex = _ex(1, cns: 9, weightedBw: true);
      final rs = _resolved(
        set: _set(1, 1, weightKg: 20, bodyweightKg: 80),
        we: _we(1, 1),
        ex: ex,
      );
      expect(rs.cnsScore, 10);
      // Unweighted rep of the same movement keeps the base score.
      final rs2 = _resolved(
        set: _set(2, 1, weightKg: 0, bodyweightKg: 80),
        we: _we(1, 1),
        ex: ex,
      );
      expect(rs2.cnsScore, 9);
    });

    test('accessory combo key is sorted and Raw when empty', () {
      final ex = _ex(1);
      expect(
        _resolved(
          set: _set(1, 1),
          we: _we(1, 1),
          ex: ex,
          accessories: ['Belt', 'Knee Sleeves'],
        ).accessoryCombo,
        'Belt + Knee Sleeves',
      );
      expect(
        _resolved(set: _set(2, 1), we: _we(1, 1), ex: ex).accessoryCombo,
        'Raw',
      );
    });
  });

  group('MuscleRecoveryV3', () {
    test('reports all 19 groups, fresh when no sets', () {
      final results = MuscleRecoveryV3.compute(
        snapshot: const TrainingSnapshot(sets: [], exerciseMuscles: []),
        asOf: _asOf,
      );
      expect(results, hasLength(19));
      expect(results.every((r) => r.recoveryScore == 100), isTrue);
    });

    test('fat grips raise forearm fatigue above an identical raw session', () {
      final curl = _ex(1, primaryMuscle: 'Biceps');
      final muscles = [
        _muscle(1, 1, 'Biceps', 'primary'),
        _muscle(2, 1, 'Forearms', 'secondary'),
      ];
      List<ResolvedSet> sets({required double forearmMult}) => [
        for (var i = 0; i < 6; i++)
          _resolved(
            set: _set(
              i,
              1,
              completedAt: _asOf.subtract(const Duration(hours: 4)),
            ),
            we: _we(1, 1),
            ex: curl,
            forearmMultiplier: forearmMult,
          ),
      ];

      final raw = MuscleRecoveryV3.compute(
        snapshot: TrainingSnapshot(
          sets: sets(forearmMult: 1.0),
          exerciseMuscles: muscles,
        ),
        asOf: _asOf,
      );
      final fatGrips = MuscleRecoveryV3.compute(
        snapshot: TrainingSnapshot(
          sets: sets(forearmMult: 1.6),
          exerciseMuscles: muscles,
        ),
        asOf: _asOf,
      );

      int score(List<MuscleGroupRecovery> rs, String m) =>
          rs.singleWhere((r) => r.muscle == m).recoveryScore;

      expect(score(fatGrips, 'Forearms'), lessThan(score(raw, 'Forearms')));
      expect(score(fatGrips, 'Biceps'), score(raw, 'Biceps'));
    });

    test('MRV warning fires when weekly sets exceed the muscle ceiling', () {
      final squat = _ex(1, primaryMuscle: 'Quads', recoveryImpact: 4);
      final muscles = [_muscle(1, 1, 'Quads', 'primary')];
      final sets = [
        for (var i = 0; i < 25; i++) // MRV for quads is 20
          _resolved(
            set: _set(
              i,
              1,
              completedAt: _asOf.subtract(Duration(hours: 24 + i)),
            ),
            we: _we(1, 1),
            ex: squat,
          ),
      ];
      final results = MuscleRecoveryV3.compute(
        snapshot: TrainingSnapshot(sets: sets, exerciseMuscles: muscles),
        asOf: _asOf,
      );
      final warnings = MuscleRecoveryV3.warnings(results);
      expect(
        warnings.any((w) => w.muscle == 'Quads' && w.message.contains('MRV')),
        isTrue,
      );
    });
  });

  group('CnsTrends', () {
    test('suggests deload when acute week spikes over chronic average', () {
      final deadlift = _ex(1, cns: 9, recoveryImpact: 5);
      final sets = <ResolvedSet>[
        // Light chronic base: 1 set/day for days 28..8.
        for (var d = 8; d <= 27; d++)
          _resolved(
            set: _set(
              d,
              1,
              rpeX10: 70,
              completedAt: _asOf.subtract(Duration(days: d)),
            ),
            we: _we(1, 1),
            ex: deadlift,
          ),
        // Acute blowout: 10 hard sets/day for the last 4 days.
        for (var d = 0; d < 4; d++)
          for (var i = 0; i < 10; i++)
            _resolved(
              set: _set(
                100 + d * 10 + i,
                1,
                rpeX10: 95,
                completedAt: _asOf.subtract(Duration(days: d, hours: 2)),
              ),
              we: _we(1, 1),
              ex: deadlift,
            ),
      ];
      final result = CnsTrends.compute(
        snapshot: TrainingSnapshot(sets: sets, exerciseMuscles: const []),
        asOf: _asOf,
      );
      expect(result.deloadSuggested, isTrue);
      expect(result.recommendation, contains('deload'));
      expect(result.daily, hasLength(28));
    });

    test('no deload on an empty or steady history', () {
      final empty = CnsTrends.compute(
        snapshot: const TrainingSnapshot(sets: [], exerciseMuscles: []),
        asOf: _asOf,
      );
      expect(empty.deloadSuggested, isFalse);
      expect(empty.currentLoad, 0);
    });
  });

  group('VariantPerformance', () {
    test('groups PRs by equipment and accessory combo with effective load', () {
      final squat = _ex(1, name: 'Squat', primaryMuscle: 'Quads');
      final old = _asOf.subtract(const Duration(days: 3));
      final sets = [
        // Barbell raw 100×5
        _resolved(
          set: _set(1, 1, weightKg: 100, reps: 5, completedAt: old),
          we: _we(1, 1, variant: 'barbell'),
          ex: squat,
        ),
        // Barbell belt 120×3
        _resolved(
          set: _set(2, 1, weightKg: 120, reps: 3, completedAt: old),
          we: _we(1, 1, variant: 'barbell'),
          ex: squat,
          accessories: ['Belt'],
        ),
        // Smith 90×8
        _resolved(
          set: _set(3, 2, weightKg: 90, reps: 8, completedAt: old),
          we: _we(2, 1, variant: 'smith'),
          ex: squat,
        ),
      ];
      final snapshot = TrainingSnapshot(sets: sets, exerciseMuscles: const []);

      final byEquipment = VariantPerformance.byEquipment(snapshot, 1);
      expect(
        byEquipment.map((r) => r.label),
        containsAll(['barbell', 'smith']),
      );
      final barbell = byEquipment.singleWhere((r) => r.label == 'barbell');
      expect(barbell.bestWeightKg, 120);

      final byCombo = VariantPerformance.byAccessoryCombo(snapshot, 1);
      expect(byCombo.map((r) => r.label), containsAll(['Raw', 'Belt']));
      final belt = byCombo.singleWhere((r) => r.label == 'Belt');
      final raw = byCombo.singleWhere((r) => r.label == 'Raw');
      expect(belt.bestE1RmKg!, greaterThan(raw.bestE1RmKg!));
    });
  });

  group('ProgressionEngine', () {
    test('adds a rep below the goal rep-range ceiling', () {
      final t = ProgressionEngine.suggestNext(
        lastWeightKg: 100,
        lastReps: 9,
        goal: ProgressionGoal.muscleGain,
        equipmentVariant: 'barbell',
      );
      expect(t.weightKg, 100);
      expect(t.reps, 10);
    });

    test('at the ceiling: bumps load, plate-rounds, resets reps', () {
      final t = ProgressionEngine.suggestNext(
        lastWeightKg: 100,
        lastReps: 12,
        goal: ProgressionGoal.muscleGain, // +2.5% → 102.5, already plate-valid
        equipmentVariant: 'barbell',
      );
      expect(t.weightKg, 102.5);
      expect(t.reps, ProgressionGoal.muscleGain.repsMin);
    });

    test('barbell rounding lands on 2.5kg increments', () {
      final t = ProgressionEngine.suggestNext(
        lastWeightKg: 87.5,
        lastReps: 6,
        goal: ProgressionGoal.strength, // +2.5% → 89.69 → 90.0
        equipmentVariant: 'barbell',
      );
      expect(t.weightKg % 2.5, 0);
      expect(t.weightKg, 90);
    });

    test('tiny percentages still move the bar by one plate step', () {
      final t = ProgressionEngine.suggestNext(
        lastWeightKg: 20,
        lastReps: 20,
        goal: ProgressionGoal.endurance, // +1% of 20 = 0.2 → forces +2.5
        equipmentVariant: 'barbell',
      );
      expect(t.weightKg, 22.5);
    });

    test('user override beats the goal default', () {
      final t = ProgressionEngine.suggestNext(
        lastWeightKg: 100,
        lastReps: 6,
        goal: ProgressionGoal.strength,
        equipmentVariant: 'barbell',
        weeklyIncreasePctOverride: 5.0, // spec default
      );
      expect(t.weightKg, 105);
    });
  });
}
