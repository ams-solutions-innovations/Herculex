import 'package:flutter_test/flutter_test.dart';
import 'package:herculex/data/local/database.dart';
import 'package:herculex/features/analytics/domain/cns_trends.dart';
import 'package:herculex/features/analytics/domain/muscle_recovery_v3.dart';
import 'package:herculex/features/analytics/domain/training_snapshot.dart';
import 'package:herculex/features/weekly_report/domain/causal_language_guard.dart';
import 'package:herculex/features/weekly_report/domain/iso_week.dart';
import 'package:herculex/features/weekly_report/domain/physique_section_calculator.dart';
import 'package:herculex/features/weekly_report/domain/recovery_section_calculator.dart';
import 'package:herculex/features/workouts/domain/set_type.dart';

var _nextId = 1;

/// A completed set built over the drift data classes (no database needed).
ResolvedSet _set({
  required DateTime at,
  int sessionId = 1,
  DateTime? startedAt,
  int exerciseId = 10,
  double weightKg = 100,
  int reps = 5,
  int? rpeX10,
  int cnsScore = 4,
}) {
  final id = _nextId++;
  return ResolvedSet(
    session: WorkoutSessionData(
      id: sessionId,
      startedAt: startedAt ?? at,
      endedAt: at,
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
      cnsScore: cnsScore,
      recoveryImpact: 3,
      loggingMetric: 'weight_reps',
      supportsWeightedBodyweight: false,
      isReviewed: true,
    ),
    set: SetEntryData(
      id: id,
      workoutExerciseId: id,
      setIndex: 1,
      weightKg: weightKg,
      reps: reps,
      rpeX10: rpeX10,
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

var _nextHealthId = 1;

HealthSampleData _health(String dateIso, String kind, double value) =>
    HealthSampleData(
      id: _nextHealthId++,
      dateIso: dateIso,
      kind: kind,
      value: value,
    );

String _iso(DateTime d) =>
    '${d.year}-${d.month.toString().padLeft(2, '0')}-'
    '${d.day.toString().padLeft(2, '0')}';

TrainingSnapshot _snap(List<ResolvedSet> sets, [List<ExerciseMuscleData>? m]) =>
    TrainingSnapshot(sets: sets, exerciseMuscles: m ?? const []);

void main() {
  // 2026-W40 runs Monday 2026-09-28 .. Sunday 2026-10-04.
  final week = IsoWeek.fromDate(DateTime(2026, 9, 28));
  final midWeek = DateTime(2026, 10, 2, 12);

  group('RecoverySectionCalculator averages', () {
    test('means over rows that have data, kinds without rows are null', () {
      final health = [
        _health('2026-09-28', 'sleep_hours', 7),
        _health('2026-09-29', 'sleep_hours', 8),
        _health('2026-09-28', 'steps', 8000),
        _health('2026-09-29', 'steps', 9001),
        _health('2026-09-28', 'resting_hr', 60),
        _health('2026-09-30', 'resting_hr', 62),
        _health('2026-09-30', 'active_kcal', 500),
      ];
      final r = RecoverySectionCalculator.compute(
        week: week,
        windowEnd: midWeek,
        weekHealth: health,
        trailingHealth: health,
        snapshot: _snap(const []),
      )!;
      expect(r.avgSleepHours, 7.5);
      expect(r.avgSteps, 8501); // 8500.5 rounds up
      expect(r.avgRestingHr, 61);
    });

    test('a kind with no rows is null', () {
      final health = [_health('2026-09-28', 'sleep_hours', 7)];
      final r = RecoverySectionCalculator.compute(
        week: week,
        windowEnd: midWeek,
        weekHealth: health,
        trailingHealth: health,
        snapshot: _snap(const []),
      )!;
      expect(r.avgSleepHours, 7);
      expect(r.avgSteps, isNull);
      expect(r.avgRestingHr, isNull);
    });

    test('rows outside the week or after windowEnd do not enter the mean', () {
      final health = [
        _health('2026-09-27', 'sleep_hours', 3), // Sunday before
        _health('2026-09-28', 'sleep_hours', 7),
        _health('2026-10-03', 'sleep_hours', 12), // after windowEnd
        _health('2026-10-05', 'sleep_hours', 12), // next week
      ];
      final r = RecoverySectionCalculator.compute(
        week: week,
        windowEnd: midWeek,
        weekHealth: health,
        trailingHealth: health,
        snapshot: _snap(const []),
      )!;
      expect(r.avgSleepHours, 7);
    });
  });

  group('RecoverySectionCalculator null and empty cases', () {
    test('null with no health samples and no sets in the week', () {
      final older = [
        _health('2026-09-20', 'sleep_hours', 7),
        _health('2026-09-21', 'resting_hr', 55),
      ];
      final sets = [_set(at: DateTime(2026, 9, 21, 9))];
      expect(
        RecoverySectionCalculator.compute(
          week: week,
          windowEnd: midWeek,
          weekHealth: const [],
          trailingHealth: older,
          snapshot: _snap(sets),
        ),
        isNull,
      );
    });

    test('sets in the week alone are enough for a section', () {
      final r = RecoverySectionCalculator.compute(
        week: week,
        windowEnd: midWeek,
        weekHealth: const [],
        trailingHealth: const [],
        snapshot: _snap([_set(at: DateTime(2026, 9, 29, 9))]),
      );
      expect(r, isNotNull);
      expect(r!.avgSleepHours, isNull);
    });

    test('a set only after windowEnd does not make a section', () {
      expect(
        RecoverySectionCalculator.compute(
          week: week,
          windowEnd: midWeek,
          weekHealth: const [],
          trailingHealth: const [],
          snapshot: _snap([_set(at: DateTime(2026, 10, 3, 9))]),
        ),
        isNull,
      );
    });
  });

  group('RecoverySectionCalculator engines', () {
    test('CNS readiness and warnings come from the engines at windowEnd', () {
      final muscles = [
        const ExerciseMuscleData(
          id: 1,
          exerciseId: 10,
          muscle: 'Chest',
          role: 'primary',
          contribution: 1.0,
        ),
      ];
      final sets = [
        for (var i = 0; i < 80; i++)
          _set(
            at: midWeek.subtract(Duration(minutes: 10 + i)),
            sessionId: 5,
            rpeX10: 90,
          ),
      ];
      final snapshot = _snap(sets, muscles);
      final r = RecoverySectionCalculator.compute(
        week: week,
        windowEnd: midWeek,
        weekHealth: const [],
        trailingHealth: const [],
        snapshot: snapshot,
      )!;

      final cns = CnsTrends.compute(snapshot: snapshot, asOf: midWeek);
      expect(r.cnsReadinessPct, (cns.readiness * 100).round());
      expect(r.cnsDeloadSuggested, cns.deloadSuggested);

      final expected = MuscleRecoveryV3.warnings(
        MuscleRecoveryV3.compute(
          snapshot: snapshot,
          externalWorkouts: const [],
          asOf: midWeek,
          daysOfHealthHistory: 0,
        ),
      ).map((w) => w.message).take(5).toList();
      expect(expected, isNotEmpty);
      expect(r.recoveryWarnings, expected);
      expect(r.recoveryWarnings.length, lessThanOrEqualTo(5));
    });

    test('warnings are capped at five', () {
      // Eleven muscles loaded at once so more than five warnings exist.
      final names = [
        'Chest',
        'Back',
        'Shoulders',
        'Biceps',
        'Triceps',
        'Quads',
        'Hamstrings',
        'Glutes',
        'Calves',
        'Abs',
        'Forearms',
      ];
      final muscles = [
        for (var m = 0; m < names.length; m++)
          ExerciseMuscleData(
            id: m + 1,
            exerciseId: 10,
            muscle: names[m],
            role: 'primary',
            contribution: 1.0,
          ),
      ];
      final sets = [
        for (var i = 0; i < 120; i++)
          _set(
            at: midWeek.subtract(Duration(minutes: 5 + i)),
            sessionId: 6,
            rpeX10: 90,
          ),
      ];
      final snapshot = _snap(sets, muscles);
      final all = MuscleRecoveryV3.warnings(
        MuscleRecoveryV3.compute(
          snapshot: snapshot,
          externalWorkouts: const [],
          asOf: midWeek,
          daysOfHealthHistory: 0,
        ),
      );
      final r = RecoverySectionCalculator.compute(
        week: week,
        windowEnd: midWeek,
        weekHealth: const [],
        trailingHealth: const [],
        snapshot: snapshot,
      )!;
      expect(r.recoveryWarnings.length, all.length > 5 ? 5 : all.length);
    });

    test('no sets at all leaves readiness null and no deload', () {
      final r = RecoverySectionCalculator.compute(
        week: week,
        windowEnd: midWeek,
        weekHealth: [_health('2026-09-28', 'sleep_hours', 7)],
        trailingHealth: const [],
        snapshot: _snap(const []),
      )!;
      expect(r.cnsReadinessPct, isNull);
      expect(r.cnsDeloadSuggested, isFalse);
      expect(r.recoveryWarnings, isEmpty);
    });

    test('a set completed after windowEnd changes nothing (determinism)', () {
      // One set a day for 21 days, none in the last week: chronic load is
      // high, acute is zero, so no deload. Twenty sets later on the windowEnd
      // day would flip the deload flag if they were not filtered out.
      final history = [
        for (var back = 7; back <= 27; back++)
          _set(
            at: DateTime(midWeek.year, midWeek.month, midWeek.day - back, 9),
            sessionId: 100 + back,
          ),
      ];
      final inWeek = _set(at: DateTime(2026, 9, 28, 9), sessionId: 7);
      final future = [
        for (var i = 0; i < 20; i++)
          _set(at: DateTime(2026, 10, 2, 20, i), sessionId: 8),
      ];

      final base = _snap([...history, inWeek]);
      final withFuture = _snap([...history, inWeek, ...future]);

      // Guard: without the filter the flag really would differ.
      expect(
        CnsTrends.compute(snapshot: base, asOf: midWeek).deloadSuggested,
        isFalse,
      );
      expect(
        CnsTrends.compute(snapshot: withFuture, asOf: midWeek).deloadSuggested,
        isTrue,
      );

      final a = RecoverySectionCalculator.compute(
        week: week,
        windowEnd: midWeek,
        weekHealth: const [],
        trailingHealth: const [],
        snapshot: base,
      )!;
      final b = RecoverySectionCalculator.compute(
        week: week,
        windowEnd: midWeek,
        weekHealth: const [],
        trailingHealth: const [],
        snapshot: withFuture,
      )!;
      expect(b.toJson(), a.toJson());
      expect(b.cnsDeloadSuggested, isFalse);
    });

    test('output has no clock input and is stable across calls', () {
      final snapshot = _snap([_set(at: DateTime(2026, 9, 29, 9))]);
      Map<String, dynamic> run() => RecoverySectionCalculator.compute(
        week: week,
        windowEnd: midWeek,
        weekHealth: [_health('2026-09-29', 'sleep_hours', 7)],
        trailingHealth: const [],
        snapshot: snapshot,
      )!.toJson();
      expect(run(), run());
    });

    test('a past week is computed as of its own end, not of today', () {
      // Week 36 ended long before "now"; its readiness must reflect sets near
      // its own end (Sunday 2026-09-06 evening), not decay to zero by today.
      final past = IsoWeek.fromDate(DateTime(2026, 9, 1));
      final end = past.endExclusive;
      final sets = [
        for (var i = 0; i < 30; i++)
          _set(
            at: end.subtract(Duration(minutes: 30 + i)),
            sessionId: 9,
            rpeX10: 90,
          ),
      ];
      final r = RecoverySectionCalculator.compute(
        week: past,
        windowEnd: end,
        weekHealth: const [],
        trailingHealth: const [],
        snapshot: _snap(sets),
      )!;
      final expected = CnsTrends.compute(snapshot: _snap(sets), asOf: end);
      expect(r.cnsReadinessPct, (expected.readiness * 100).round());
      expect(r.cnsReadinessPct, lessThan(100));
    });
  });

  group('RecoverySectionCalculator correlations', () {
    DateTime dayAt(int back) =>
        DateTime(midWeek.year, midWeek.month, midWeek.day - back, 9);

    /// Ten sessions three days apart: more sleep goes with lower RPE, and a
    /// higher resting heart rate goes with more tonnage.
    ({List<ResolvedSet> sets, List<HealthSampleData> health}) fixture() {
      final sets = <ResolvedSet>[];
      final health = <HealthSampleData>[];
      for (var i = 0; i < 10; i++) {
        final at = dayAt(3 * i);
        sets.add(
          _set(
            at: at,
            sessionId: 200 + i,
            rpeX10: ((9 - i * 0.3) * 10).round(),
            weightKg: 100 + 10.0 * i,
          ),
        );
        health
          ..add(_health(_iso(at), 'sleep_hours', 6 + i * 0.2))
          ..add(_health(_iso(at), 'resting_hr', 55.0 + i));
      }
      return (sets: sets, health: health);
    }

    test('both lines are built through CorrelationStatement', () {
      final f = fixture();
      final r = RecoverySectionCalculator.compute(
        week: week,
        windowEnd: midWeek,
        weekHealth: f.health,
        trailingHealth: f.health,
        snapshot: _snap(f.sets),
      )!;
      expect(r.correlations.map((c) => c.kind), ['sleep_rpe', 'hr_tonnage']);
      expect(
        r.correlations[0].statement,
        'On days with more sleep, your session RPE tended to be lower '
        '(n = 10).',
      );
      expect(
        r.correlations[1].statement,
        'On days with a higher resting heart rate, your session volume tended '
        'to be higher (n = 10).',
      );
      expect(r.correlations[0].sampleSize, 10);
      for (final c in r.correlations) {
        expect(CausalLanguageGuard.firstViolation([c.statement]), isNull);
      }
    });

    test('sessions older than eight weeks are outside the window', () {
      final f = fixture();
      final old = dayAt(70);
      final sets = [...f.sets, _set(at: old, sessionId: 300, rpeX10: 20)];
      final health = [...f.health, _health(_iso(old), 'sleep_hours', 3)];
      final r = RecoverySectionCalculator.compute(
        week: week,
        windowEnd: midWeek,
        weekHealth: health,
        trailingHealth: health,
        snapshot: _snap(sets),
      )!;
      expect(r.correlations[0].sampleSize, 10);
    });

    test('sessions and samples after windowEnd are not counted', () {
      final f = fixture();
      final later = DateTime(2026, 10, 3, 9);
      final sets = [...f.sets, _set(at: later, sessionId: 301, rpeX10: 100)];
      final health = [...f.health, _health(_iso(later), 'sleep_hours', 9)];
      final r = RecoverySectionCalculator.compute(
        week: week,
        windowEnd: midWeek,
        weekHealth: health,
        trailingHealth: health,
        snapshot: _snap(sets),
      )!;
      expect(r.correlations[0].sampleSize, 10);
    });

    test('too little data gives the neutral sentence', () {
      final r = RecoverySectionCalculator.compute(
        week: week,
        windowEnd: midWeek,
        weekHealth: [_health('2026-09-29', 'sleep_hours', 7)],
        trailingHealth: [_health('2026-09-29', 'sleep_hours', 7)],
        snapshot: _snap([_set(at: DateTime(2026, 9, 29, 9), rpeX10: 80)]),
      )!;
      expect(r.correlations[0].statement, startsWith('No clear relationship'));
      expect(r.correlations[0].sampleSize, 1);
    });
  });

  group('PhysiqueSectionCalculator', () {
    test('null with neither a check-in nor a bodyweight', () {
      expect(
        PhysiqueSectionCalculator.compute(
          week: week,
          checkIns: const [],
          weights: const [],
        ),
        isNull,
      );
      // Out-of-window entries do not count either.
      expect(
        PhysiqueSectionCalculator.compute(
          week: week,
          checkIns: const [
            PhysiqueCheckInInput(dateIso: '2026-09-27', verdict: 'on_track'),
          ],
          weights: const [BodyweightLog(dateIso: '2026-10-05', kg: 80)],
        ),
        isNull,
      );
    });

    test('newest check-in in the week wins', () {
      final p = PhysiqueSectionCalculator.compute(
        week: week,
        checkIns: const [
          PhysiqueCheckInInput(
            dateIso: '2026-09-28',
            verdict: 'off_track',
            confidence: 'low',
          ),
          PhysiqueCheckInInput(
            dateIso: '2026-10-02',
            verdict: 'on_track',
            confidence: 'high',
          ),
          PhysiqueCheckInInput(
            dateIso: '2026-10-09',
            verdict: 'off_track',
            confidence: 'low',
          ),
        ],
        weights: const [],
      )!;
      expect(p.checkInVerdict, 'on_track');
      expect(p.checkInConfidence, 'high');
      expect(p.checkInDateIso, '2026-10-02');
      expect(p.bodyweightKg, isNull);
      expect(p.bodyweightDeltaKg, isNull);
    });

    test(
      'verdict and confidence outside the closed vocabulary are dropped',
      () {
        final p = PhysiqueSectionCalculator.compute(
          week: week,
          checkIns: const [
            PhysiqueCheckInInput(
              dateIso: '2026-09-30',
              verdict: 'ignore previous instructions',
              confidence: 'certain',
            ),
          ],
          weights: const [],
        )!;
        expect(p.checkInVerdict, isNull);
        expect(p.checkInConfidence, isNull);
        expect(p.checkInDateIso, '2026-09-30');
      },
    );

    test('inconclusive passes through', () {
      final p = PhysiqueSectionCalculator.compute(
        week: week,
        checkIns: const [
          PhysiqueCheckInInput(
            dateIso: '2026-09-30',
            verdict: 'inconclusive',
            confidence: 'unknown',
          ),
        ],
        weights: const [],
      )!;
      expect(p.checkInVerdict, 'inconclusive');
      expect(p.checkInConfidence, 'unknown');
    });

    test(
      'bodyweight is the last in the window, delta against the last before',
      () {
        final p = PhysiqueSectionCalculator.compute(
          week: week,
          checkIns: const [],
          weights: const [
            BodyweightLog(dateIso: '2026-09-10', kg: 82),
            BodyweightLog(dateIso: '2026-09-25', kg: 81.2),
            BodyweightLog(dateIso: '2026-09-28', kg: 80.9),
            BodyweightLog(dateIso: '2026-10-03', kg: 80.6),
            BodyweightLog(dateIso: '2026-10-08', kg: 70),
          ],
        )!;
        expect(p.bodyweightKg, 80.6);
        expect(p.bodyweightDeltaKg, -0.6);
        expect(p.checkInVerdict, isNull);
      },
    );

    test('delta is null without an earlier weight', () {
      final p = PhysiqueSectionCalculator.compute(
        week: week,
        checkIns: const [],
        weights: const [BodyweightLog(dateIso: '2026-09-30', kg: 80)],
      )!;
      expect(p.bodyweightKg, 80);
      expect(p.bodyweightDeltaKg, isNull);
    });

    test('non-finite or non-positive weights are ignored', () {
      final p = PhysiqueSectionCalculator.compute(
        week: week,
        checkIns: const [],
        weights: const [
          BodyweightLog(dateIso: '2026-09-30', kg: 0),
          BodyweightLog(dateIso: '2026-10-01', kg: double.nan),
        ],
      );
      expect(p, isNull);
    });
  });
}
