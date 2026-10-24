import 'package:flutter_test/flutter_test.dart';
import 'package:herculex/core/utils/units.dart';
import 'package:herculex/data/local/database.dart';
import 'package:herculex/features/analytics/domain/training_snapshot.dart';
import 'package:herculex/features/gamification/domain/fun_facts/fun_fact_generator.dart';
import 'package:herculex/features/gamification/domain/fun_facts/weight_equivalents.dart';
import 'package:herculex/features/recovery/domain/training_suggestion.dart';
import 'package:herculex/features/workouts/domain/set_type.dart';

ExerciseCatalogData _ex(int id, String name, String muscle) =>
    ExerciseCatalogData(
      id: id,
      name: name,
      primaryMuscle: muscle,
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

final _squat = _ex(1, 'Back Squat', 'Quads');
final _bench = _ex(2, 'Bench Press', 'Chest');

var _nextId = 0;

/// [count] sets of [kg] Ã— [reps] on [ex] at [at].
List<ResolvedSet> _sets(
  ExerciseCatalogData ex,
  DateTime at, {
  double kg = 100,
  int reps = 10,
  int count = 1,
}) {
  final id = ++_nextId;
  final session = WorkoutSessionData(id: id, startedAt: at, name: 'S$id');
  final we = WorkoutExerciseData(
    id: id,
    sessionId: id,
    exerciseId: ex.id,
    orderIndex: 0,
    plannedAllowsAdvancedTechniques: false,
  );
  return [
    for (var i = 0; i < count; i++)
      ResolvedSet(
        session: session,
        workoutExercise: we,
        exercise: ex,
        set: SetEntryData(
          id: id * 100 + i,
          workoutExerciseId: id,
          setIndex: i,
          weightKg: kg,
          reps: reps,
          isWarmup: false,
          isCompleted: true,
          completedAt: at,
          setType: 'standard',
        ),
        setType: SetType.standard,
        bands: const [],
        accessoryNames: const [],
        forearmMultiplier: 1,
      ),
  ];
}

TrainingSnapshot _snap(List<ResolvedSet> sets) =>
    TrainingSnapshot(sets: sets, exerciseMuscles: const []);

void main() {
  const gen = FunFactGenerator();
  // Thursday.
  final now = DateTime(2026, 10, 8, 20);

  group('WeightComparison.pick', () {
    test('takes the heaviest object covered at least once', () {
      final c = WeightComparison.pick(4500, tonnageEquivalents)!;
      expect(c.equivalent.plural, 'rhinos');
      expect(c.phrase, '2 rhinos');
    });

    test('a Boeing 747 needs 180 t', () {
      final c = WeightComparison.pick(185000, tonnageEquivalents)!;
      expect(c.equivalent.plural, 'empty Boeing 747s');
      expect(c.phrase, 'an empty Boeing 747');
    });

    test('null below the lightest object', () {
      expect(WeightComparison.pick(50, tonnageEquivalents), isNull);
      expect(WeightComparison.pick(double.nan, tonnageEquivalents), isNull);
    });
  });

  group('FunFactGenerator', () {
    test('null with no history', () {
      expect(gen.generate(snapshot: _snap(const []), asOf: now), isNull);
    });

    test("today's news beats this week and lifetime", () {
      final sets = [
        // 5 Ã— 100 Ã— 10 = 5 t of squats today.
        ..._sets(_squat, now.subtract(const Duration(hours: 2)), count: 5),
        // Plenty of bench earlier in the week.
        ..._sets(_bench, now.subtract(const Duration(days: 2)), count: 20),
      ];
      final fact = gen.generate(snapshot: _snap(sets), asOf: now)!;
      expect(
        fact.kind,
        anyOf(FunFactKind.todayExercise, FunFactKind.todayHeaviestSet),
      );
    });

    test('falls back to the week when nothing happened today', () {
      final sets = _sets(
        _bench,
        now.subtract(const Duration(days: 2)),
        count: 6,
      );
      final fact = gen.generate(snapshot: _snap(sets), asOf: now)!;
      expect(fact.kind, anyOf(FunFactKind.weekCategory, FunFactKind.weekTotal));
      if (fact.kind == FunFactKind.weekCategory) {
        expect(fact.category, MuscleCategory.push);
      }
      expect(fact.kg, 6000);
    });

    test('falls back to lifetime for an old history', () {
      final sets = _sets(
        _squat,
        now.subtract(const Duration(days: 40)),
        count: 3,
      );
      final fact = gen.generate(snapshot: _snap(sets), asOf: now)!;
      expect(fact.kind, FunFactKind.lifetime);
      // 3 t: a rhino (2.3 t) is the heaviest object it covers.
      expect(fact.comparison.phrase, '1.3 rhinos');
    });

    test('stable within a day, rotates across days', () {
      final sets = _sets(
        _bench,
        now.subtract(const Duration(days: 1)),
        count: 6,
      );
      final a = gen.generate(snapshot: _snap(sets), asOf: now)!;
      final b = gen.generate(
        snapshot: _snap(sets),
        asOf: now.subtract(const Duration(hours: 3)),
      )!;
      expect(a.kind, b.kind);

      final kinds = {
        for (var d = 0; d < 3; d++)
          gen
              .generate(
                snapshot: _snap(sets),
                asOf: now.add(Duration(days: d)),
              )!
              .kind,
      };
      // Bench Wed; Thu/Fri/Sat are all in the same week with two candidates.
      expect(kinds.length, 2);
    });

    test('ignores sets after asOf', () {
      final sets = _sets(_squat, now.add(const Duration(days: 1)), count: 5);
      expect(gen.generate(snapshot: _snap(sets), asOf: now), isNull);
    });
  });

  group('funFactSentence', () {
    test('words a weekly push fact in the user unit', () {
      final fact = FunFact(
        kind: FunFactKind.weekCategory,
        kg: 185000,
        comparison: WeightComparison.pick(185000, tonnageEquivalents)!,
        category: MuscleCategory.push,
      );
      expect(
        funFactSentence(fact, const WeightFormat(MeasurementUnit.metric)),
        "This week your push work moved 185.0 t. That's an empty Boeing 747.",
      );
    });
  });
}
