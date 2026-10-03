import 'package:flutter_test/flutter_test.dart';
import 'package:herculex/data/local/database.dart';
import 'package:herculex/features/analytics/domain/training_snapshot.dart';
import 'package:herculex/features/weekly_report/domain/iso_week.dart';
import 'package:herculex/features/weekly_report/domain/nutrition_section_calculator.dart';
import 'package:herculex/features/weekly_report/domain/training_section_calculator.dart';
import 'package:herculex/features/workouts/domain/set_type.dart';

var _nextId = 1;

/// A completed set of [exerciseId] in [sessionId], built over the drift data
/// classes directly (no database needed; ResolvedSet is plain Dart).
ResolvedSet _set({
  required DateTime? at,
  int sessionId = 1,
  bool sessionEnded = true,
  int exerciseId = 10,
  String exerciseName = 'Bench Press',
  String metric = 'weight_reps',
  double weightKg = 100,
  int reps = 5,
}) {
  final id = _nextId++;
  return ResolvedSet(
    session: WorkoutSessionData(
      id: sessionId,
      startedAt: DateTime(2026, 9, 28),
      endedAt: sessionEnded ? DateTime(2026, 9, 28, 1) : null,
    ),
    workoutExercise: WorkoutExerciseData(
      id: id,
      sessionId: sessionId,
      exerciseId: exerciseId,
      orderIndex: 0,
      plannedAllowsAdvancedTechniques: false,
    ),
    exercise: ExerciseCatalogData(
      id: exerciseId,
      name: exerciseName,
      primaryMuscle: 'Chest',
      equipment: 'Barbell',
      mechanics: 'compound',
      force: 'push',
      plane: 'horizontal',
      defaultRestSeconds: 120,
      isCustom: false,
      category: 'strength',
      modality: 'barbell',
      cnsScore: 4,
      recoveryImpact: 2,
      loggingMetric: metric,
      supportsWeightedBodyweight: false,
      isReviewed: true,
    ),
    set: SetEntryData(
      id: id,
      workoutExerciseId: id,
      setIndex: 1,
      weightKg: weightKg,
      reps: reps,
      isWarmup: false,
      isCompleted: true,
      completedAt: at,
      setType: 'standard',
    ),
    setType: SetType.standard,
    bands: const [],
    accessoryNames: const [],
    forearmMultiplier: 1.0,
  );
}

void main() {
  // 2026-09-28 is a Monday: ISO week 2026-W40 runs 09-28 .. 10-04.
  final week = IsoWeek.fromDate(DateTime(2026, 9, 28));

  group('NutritionSectionCalculator', () {
    NutritionWeekInputs inputs({
      Set<String>? days,
      Map<String, double>? kcal,
      Map<String, double>? protein,
      Map<String, ({int kcal, int proteinG})>? targets,
      List<FoodEntryName>? foods,
    }) => NutritionWeekInputs(
      loggedDays: days ?? {'2026-09-28', '2026-09-29', '2026-09-30'},
      kcalByDate:
          kcal ??
          {'2026-09-28': 2400, '2026-09-29': 2600, '2026-09-30': 0},
      proteinByDate:
          protein ??
          {'2026-09-28': 150, '2026-09-29': 170, '2026-09-30': 0},
      targetByDate:
          targets ??
          {
            for (final d in ['2026-09-28', '2026-09-29', '2026-09-30'])
              d: (kcal: 2500, proteinG: 160),
          },
      foodEntries: foods ?? const [],
    );

    test('week sanity: the fixture week is 2026-W40', () {
      expect(week, const IsoWeek(2026, 40));
      expect(week.startIso, '2026-09-28');
      expect(week.endIso, '2026-10-04');
    });

    test('presence-based averages, targets and adherence', () {
      final s = NutritionSectionCalculator.compute(
        week: week,
        inputs: inputs(),
      )!;
      expect(s.daysLogged, 3);
      // A logged day with 0 kcal still counts: (2400 + 2600 + 0) / 3.
      expect(s.avgKcal, 1667);
      expect(s.avgProteinG, 107);
      expect(s.targetKcal, 2500);
      expect(s.targetProteinG, 160);
      // 2400 and 2600 are within 250 of 2500; 0 is not.
      expect(s.adherenceDays, 2);
    });

    test('adherence band is the named 10 percent constant', () {
      expect(NutritionSectionCalculator.adherenceBandFraction, 0.10);
      final onEdge = NutritionSectionCalculator.compute(
        week: week,
        inputs: inputs(
          days: {'2026-09-28', '2026-09-29'},
          kcal: {'2026-09-28': 2750, '2026-09-29': 2751},
        ),
      )!;
      expect(onEdge.adherenceDays, 1);
    });

    test('no targets -> target and adherence fields are null', () {
      final s = NutritionSectionCalculator.compute(
        week: week,
        inputs: inputs(targets: const {}),
      )!;
      expect(s.targetKcal, isNull);
      expect(s.targetProteinG, isNull);
      expect(s.adherenceDays, isNull);
      expect(s.daysLogged, 3);
    });

    test('targets are averaged over logged days that have one', () {
      final s = NutritionSectionCalculator.compute(
        week: week,
        inputs: inputs(
          targets: {
            '2026-09-28': (kcal: 2000, proteinG: 100),
            '2026-09-29': (kcal: 3000, proteinG: 200),
            // 09-30 has no target.
          },
        ),
      )!;
      expect(s.targetKcal, 2500);
      expect(s.targetProteinG, 150);
    });

    test('no logged days returns null', () {
      expect(
        NutritionSectionCalculator.compute(
          week: week,
          inputs: inputs(days: <String>{}),
        ),
        isNull,
      );
    });

    test('days outside the week are ignored', () {
      final s = NutritionSectionCalculator.compute(
        week: week,
        inputs: inputs(
          days: {'2026-09-27', '2026-09-28', '2026-10-05'},
          kcal: {'2026-09-27': 9000, '2026-09-28': 2000, '2026-10-05': 9000},
          protein: {'2026-09-27': 900, '2026-09-28': 100, '2026-10-05': 900},
          targets: {
            '2026-09-27': (kcal: 9000, proteinG: 900),
            '2026-09-28': (kcal: 2000, proteinG: 100),
          },
        ),
      )!;
      expect(s.daysLogged, 1);
      expect(s.avgKcal, 2000);
      expect(s.targetKcal, 2000);
      expect(s.adherenceDays, 1);
    });

    test('only out-of-week days logged returns null', () {
      expect(
        NutritionSectionCalculator.compute(
          week: week,
          inputs: inputs(days: {'2026-09-27'}),
        ),
        isNull,
      );
    });

    test('topFoods: count desc, name asc, max 3, trimmed, capped', () {
      final long = 'x' * 80;
      final s = NutritionSectionCalculator.compute(
        week: week,
        inputs: inputs(
          foods: [
            const FoodEntryName(key: 'a', name: 'Oats'),
            const FoodEntryName(key: 'a', name: 'Oats'),
            const FoodEntryName(key: 'b', name: '  Banana '),
            const FoodEntryName(key: 'b', name: 'Banana'),
            const FoodEntryName(key: 'c', name: 'Apple'),
            const FoodEntryName(key: 'd', name: 'Zucchini'),
            const FoodEntryName(key: 'e', name: '   '),
            const FoodEntryName(key: 'e', name: ''),
            FoodEntryName(key: 'f', name: long),
            FoodEntryName(key: 'f', name: long),
            FoodEntryName(key: 'f', name: long),
          ],
        ),
      )!;
      expect(s.topFoods.map((f) => f.name).toList(), [
        'x' * 60,
        'Banana',
        'Oats',
      ]);
      expect(s.topFoods.map((f) => f.count).toList(), [3, 2, 2]);
    });

    test('equal inputs give equal output (no clock involved)', () {
      final a = NutritionSectionCalculator.compute(
        week: week,
        inputs: inputs(),
      )!.toJson();
      final b = NutritionSectionCalculator.compute(
        week: week,
        inputs: inputs(),
      )!.toJson();
      expect(a, b);
    });

    test('copyWith replaces only targetByDate', () {
      final base = inputs(targets: const {});
      final filled = base.copyWith(
        targetByDate: {'2026-09-28': (kcal: 2500, proteinG: 160)},
      );
      expect(filled.loggedDays, base.loggedDays);
      expect(filled.kcalByDate, base.kcalByDate);
      expect(filled.targetByDate, hasLength(1));
      expect(base.copyWith().targetByDate, isEmpty);
    });
  });

  group('TrainingSectionCalculator', () {
    final weekEnd = week.endExclusive; // 2026-10-05 00:00
    final mon = DateTime(2026, 9, 28, 10);
    final tue = DateTime(2026, 9, 29, 10);
    final lastWeek = DateTime(2026, 9, 23, 10);
    final older = DateTime(2026, 9, 1, 10);

    test('sessions and tonnage come from in-window sets', () {
      final s = TrainingSectionCalculator.compute(
        week: week,
        windowEnd: weekEnd,
        sets: [
          _set(at: mon, sessionId: 1, weightKg: 100, reps: 5),
          _set(at: mon, sessionId: 1, weightKg: 100, reps: 5),
          _set(at: tue, sessionId: 2, weightKg: 60, reps: 10),
        ],
      )!;
      expect(s.sessions, 2);
      expect(s.tonnageKg, 500 + 500 + 600);
      expect(s.prevWeekTonnageKg, isNull);
    });

    test('tonnage is the sum of ResolvedSet.tonnageKg', () {
      final sets = [
        _set(at: mon, weightKg: 80, reps: 8),
        _set(at: tue, exerciseId: 11, weightKg: 50, reps: 12),
        // Timed exercise: reps are a placeholder, tonnage is zero.
        _set(at: tue, exerciseId: 12, metric: 'time', weightKg: 0, reps: 0),
      ];
      final s = TrainingSectionCalculator.compute(
        week: week,
        windowEnd: weekEnd,
        sets: sets,
      )!;
      expect(s.tonnageKg, sets.fold<double>(0, (a, r) => a + r.tonnageKg));
    });

    test('a session without endedAt is not counted as a session', () {
      final s = TrainingSectionCalculator.compute(
        week: week,
        windowEnd: weekEnd,
        sets: [
          _set(at: mon, sessionId: 1),
          _set(at: tue, sessionId: 2, sessionEnded: false),
        ],
      )!;
      expect(s.sessions, 1);
    });

    test('sets outside the window are excluded; previous week is compared', () {
      final s = TrainingSectionCalculator.compute(
        week: week,
        windowEnd: DateTime(2026, 9, 30),
        sets: [
          _set(at: mon, weightKg: 100, reps: 5), // 500, in
          _set(at: DateTime(2026, 10, 1, 9), weightKg: 999), // after windowEnd
          _set(at: weekEnd, weightKg: 999), // next week
          _set(at: lastWeek, weightKg: 100, reps: 4), // prev week 400
          _set(at: older, weightKg: 100, reps: 3), // before prev week
        ],
      )!;
      expect(s.tonnageKg, 500);
      expect(s.prevWeekTonnageKg, 400);
      expect(s.sessions, 1);
    });

    test('sets with no completedAt are ignored', () {
      final s = TrainingSectionCalculator.compute(
        week: week,
        windowEnd: weekEnd,
        sets: [_set(at: null, weightKg: 500), _set(at: mon, reps: 5)],
      )!;
      expect(s.tonnageKg, 500);
    });

    test('no in-window sets returns null', () {
      expect(
        TrainingSectionCalculator.compute(
          week: week,
          windowEnd: weekEnd,
          sets: [_set(at: lastWeek), _set(at: older)],
        ),
        isNull,
      );
      expect(
        TrainingSectionCalculator.compute(
          week: week,
          windowEnd: weekEnd,
          sets: const [],
        ),
        isNull,
      );
    });

    test('e1RM movers: improvement over prior history, top 3 by delta', () {
      // exercise 10: prior 100x5, week 110x5 -> mover.
      // exercise 11: prior 100x5, week 100x5 -> no change, not a mover.
      // exercise 12: no prior history -> not a mover.
      // exercise 13: prior 100x5, week 90x5 -> regression, not a mover.
      // exercises 14,15,16: improvements of different size.
      final sets = [
        _set(at: older, exerciseId: 10, exerciseName: 'Bench', weightKg: 100),
        _set(at: mon, exerciseId: 10, exerciseName: 'Bench', weightKg: 110),
        _set(at: older, exerciseId: 11, exerciseName: 'Row', weightKg: 100),
        _set(at: mon, exerciseId: 11, exerciseName: 'Row', weightKg: 100),
        _set(at: mon, exerciseId: 12, exerciseName: 'New', weightKg: 200),
        _set(at: older, exerciseId: 13, exerciseName: 'Dip', weightKg: 100),
        _set(at: mon, exerciseId: 13, exerciseName: 'Dip', weightKg: 90),
        _set(at: older, exerciseId: 14, exerciseName: 'Squat', weightKg: 100),
        _set(at: mon, exerciseId: 14, exerciseName: 'Squat', weightKg: 140),
        _set(at: older, exerciseId: 15, exerciseName: 'Deadlift', weightKg: 100),
        _set(at: mon, exerciseId: 15, exerciseName: 'Deadlift', weightKg: 120),
        _set(at: older, exerciseId: 16, exerciseName: 'Press', weightKg: 40),
        _set(at: mon, exerciseId: 16, exerciseName: 'Press', weightKg: 42.5),
      ];
      final s = TrainingSectionCalculator.compute(
        week: week,
        windowEnd: weekEnd,
        sets: sets,
      )!;
      expect(s.e1rmMovers.map((m) => m.exerciseName).toList(), [
        'Squat',
        'Deadlift',
        'Bench',
      ]);
      // 5 reps: (w*(1+5/30) + w*36/32) / 2 = w * 1.14583...
      final squat = s.e1rmMovers.first;
      expect(squat.e1rmKg, closeTo(140 * 1.1458333, 0.06));
      expect(squat.deltaKg, closeTo(40 * 1.1458333, 0.06));
      expect(s.e1rmMovers.every((m) => m.deltaKg > 0), isTrue);
    });

    test('e1RM uses the best set of each period', () {
      final s = TrainingSectionCalculator.compute(
        week: week,
        windowEnd: weekEnd,
        sets: [
          _set(at: older, weightKg: 100, reps: 1), // prior best 100
          _set(at: older, weightKg: 50, reps: 5),
          _set(at: mon, weightKg: 100, reps: 1), // week best 105
          _set(at: tue, weightKg: 105, reps: 1),
        ],
      )!;
      expect(s.e1rmMovers, hasLength(1));
      expect(s.e1rmMovers.single.e1rmKg, 105);
      expect(s.e1rmMovers.single.deltaKg, 5);
    });

    test('non rep-based or unloaded metrics produce no mover', () {
      final s = TrainingSectionCalculator.compute(
        week: week,
        windowEnd: weekEnd,
        sets: [
          // Reps without load (bodyweight metric): rep-based, not loaded.
          _set(at: older, exerciseId: 20, metric: 'reps', weightKg: 10),
          _set(at: mon, exerciseId: 20, metric: 'reps', weightKg: 50),
          // Timed carry: loaded but not rep-based.
          _set(at: older, exerciseId: 21, metric: 'weight_time', weightKg: 10),
          _set(at: mon, exerciseId: 21, metric: 'weight_time', weightKg: 50),
        ],
      )!;
      expect(s.e1rmMovers, isEmpty);
    });

    test('sets whose e1RM cannot be estimated are skipped', () {
      final s = TrainingSectionCalculator.compute(
        week: week,
        windowEnd: weekEnd,
        sets: [
          _set(at: older, weightKg: 100, reps: 5),
          // 20 reps is outside the estimator range -> null -> skipped.
          _set(at: mon, weightKg: 200, reps: 20),
        ],
      )!;
      expect(s.e1rmMovers, isEmpty);
    });

    test('long exercise names are capped at 60 characters', () {
      final s = TrainingSectionCalculator.compute(
        week: week,
        windowEnd: weekEnd,
        sets: [
          _set(at: older, exerciseName: '  ${'n' * 90}', weightKg: 100),
          _set(at: mon, exerciseName: '  ${'n' * 90}', weightKg: 110),
        ],
      )!;
      expect(s.e1rmMovers.single.exerciseName, 'n' * 60);
    });

    test('equal inputs give equal output (no clock involved)', () {
      List<ResolvedSet> build() => [
        _set(at: older, weightKg: 100),
        _set(at: mon, weightKg: 110),
        _set(at: lastWeek, weightKg: 90),
      ];
      final a = TrainingSectionCalculator.compute(
        week: week,
        windowEnd: weekEnd,
        sets: build(),
      )!.toJson();
      final b = TrainingSectionCalculator.compute(
        week: week,
        windowEnd: weekEnd,
        sets: build(),
      )!.toJson();
      expect(a, b);
    });
  });
}
