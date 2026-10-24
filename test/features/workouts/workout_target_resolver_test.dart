import 'package:flutter_test/flutter_test.dart';
import 'package:herculex/features/workouts/domain/progression_engine.dart';
import 'package:herculex/features/workouts/domain/workout_target_resolver.dart';

WorkoutTargetSet work(
  int id, {
  double? planned = 100,
  double weight = 0,
  int reps = 0,
  int? rpe,
  bool done = false,
  int min = 5,
  int? max,
  int? targetRpe = 80,
  String type = 'standard',
  double? bodyweight,
}) => WorkoutTargetSet(
  id: id,
  plannedWeightKg: planned,
  weightKg: weight,
  reps: reps,
  rpeX10: rpe,
  completed: done,
  repsMin: min,
  repsMax: max ?? min,
  targetRpeX10: targetRpe,
  type: type,
  bodyweightKg: bodyweight,
);

void main() {
  List<WorkoutTarget> resolve(
    List<WorkoutTargetSet> sets, {
    List<WorkoutTargetSet> history = const [],
    WorkoutTargetSettings settings = const WorkoutTargetSettings(),
  }) => WorkoutTargetResolver.resolve(
    sets: sets,
    history: history,
    equipment: 'barbell',
    settings: settings,
  );

  test(
    '3x5: four reps at RPE9.5 lowers remaining weight and retains prescription',
    () {
      final sets = [
        work(1, weight: 100, reps: 4, rpe: 95, done: true),
        work(2),
        work(3),
      ];
      final targets = resolve(sets);
      expect(targets[1].weightKg, 92.5);
      expect(targets[2].weightKg, 92.5);
      expect(targets[1].reps, 5);
      expect(targets[1].rpeX10, 80);
      expect(targets[1].source, WorkoutTargetSource.adaptation);
      expect(
        resolve(sets)[1].weightKg,
        92.5,
        reason: 'Rebuilds cannot compound reductions',
      );
      expect(sets[1].plannedWeightKg, 100);
      expect(sets[1].rpeX10, isNull);
    },
  );

  test('missing RPE uses five percent reduction on missed reps only', () {
    expect(
      resolve([work(1, weight: 100, reps: 4, done: true), work(2)])[1].weightKg,
      95,
    );
    expect(
      resolve([work(1, weight: 100, reps: 5, done: true), work(2)])[1].weightKg,
      100,
    );
  });

  test('late RPE and undo recompute from actual work', () {
    expect(
      resolve([work(1, weight: 100, reps: 4, done: true), work(2)])[1].weightKg,
      95,
    );
    expect(
      resolve([
        work(1, weight: 100, reps: 4, rpe: 95, done: true),
        work(2),
      ])[1].weightKg,
      92.5,
    );
    expect(
      resolve([work(1, weight: 100, reps: 4, rpe: 95), work(2)])[1].weightKg,
      100,
    );
  });

  test('easy set never increases today\'s load', () {
    expect(
      resolve([
        work(1, weight: 100, reps: 5, rpe: 60, done: true),
        work(2),
      ])[1].weightKg,
      100,
    );
  });

  test('first-ever workout adapts from manually logged actual weight', () {
    expect(
      resolve([
        work(1, planned: null, weight: 80, reps: 4, done: true),
        work(2, planned: null),
      ])[1].weightKg,
      75,
    );
  });

  test('manual values are inputs and never changed by recommendations', () {
    final typed = work(2, weight: 110, reps: 5);
    final target = resolve([
      work(1, weight: 100, reps: 4, done: true),
      typed,
    ])[1];
    expect(target.weightKg, 95);
    expect(typed.weightKg, 110);
  });

  test('program percent resolves from comparable estimated capacity', () {
    final targets = resolve(
      [const WorkoutTargetSet(id: 1, repsMin: 5, percentOf1Rm: .8)],
      history: [work(9, weight: 100, reps: 5, rpe: 80, done: true)],
    );
    expect(targets.single.weightKg, 97.5);
    expect(targets.single.source, WorkoutTargetSource.percentage);
    expect(
      resolve(
        [work(1, planned: 70)],
        history: [work(9, weight: 100, reps: 5, done: true)],
      ).single.weightKg,
      70,
    );
  });

  test('no history means no fabricated load for a percent prescription', () {
    expect(
      resolve([
        const WorkoutTargetSet(id: 1, repsMin: 5, percentOf1Rm: .8),
      ]).single.weightKg,
      isNull,
    );
  });

  test(
    'warmup, down sets and differing assistance cannot qualify overload',
    () {
      final targets = resolve(
        [work(1, planned: null)],
        history: [
          const WorkoutTargetSet(
            id: 9,
            weightKg: 100,
            reps: 10,
            warmup: true,
            completed: true,
          ),
          work(10, weight: 150, reps: 10, done: true, type: 'down_sets'),
          const WorkoutTargetSet(
            id: 11,
            weightKg: 150,
            reps: 10,
            completed: true,
            assistance: 'other-band',
          ),
        ],
      );
      expect(targets.single.weightKg, isNull);
    },
  );

  test('program range overrides the profile range and requires all sets', () {
    final sets = [
      work(1, planned: null),
      work(2, planned: null),
      work(3, planned: null),
    ];
    final history = [
      work(11, weight: 100, reps: 5, done: true),
      work(12, weight: 100, reps: 5, done: true),
      work(13, weight: 100, reps: 5, done: true),
    ];
    expect(resolve(sets, history: history).last.weightKg, 102.5);
    expect(
      resolve(
        sets,
        history: [
          history[0],
          history[1],
          work(13, weight: 100, reps: 4, done: true),
        ],
      ).first.weightKg,
      100,
    );
    expect(
      resolve(
        sets,
        history: [
          history[0],
          history[1],
          work(13, weight: 110, reps: 5, done: true),
        ],
      ).first.weightKg,
      100,
    );
  });

  test('load still progresses when the program moves to a new rep range', () {
    // Last wave: 3 × 8–10 hit at the top. This wave prescribes 6–8, so the
    // old ranges no longer match — the load must still go up, not freeze.
    final sets = [
      for (var i = 1; i <= 3; i++) work(i, planned: null, min: 6, max: 8),
    ];
    final history = [
      for (var i = 11; i <= 13; i++)
        work(i, weight: 60, reps: 10, done: true, min: 8, max: 10),
    ];
    final targets = resolve(sets, history: history);
    expect(targets.first.weightKg, 62.5);
    expect(targets.first.reps, 6);
  });

  test('a new rep range still holds the load when last wave fell short', () {
    final sets = [
      for (var i = 1; i <= 3; i++) work(i, planned: null, min: 6, max: 8),
    ];
    final history = [
      work(11, weight: 60, reps: 8, done: true, min: 8, max: 10),
      work(12, weight: 60, reps: 7, done: true, min: 8, max: 10),
      work(13, weight: 60, reps: 7, done: true, min: 8, max: 10),
    ];
    expect(resolve(sets, history: history).first.weightKg, 60);
  });

  test('next workout uses actual manually increased or decreased weight', () {
    for (final weight in [80.0, 110.0]) {
      final targets = resolve(
        [work(1, planned: null)],
        history: [work(9, weight: weight, reps: 4, done: true)],
      );
      expect(targets.single.weightKg, weight);
    }
  });

  test('assisted progression reduces help; failure increases help', () {
    const settings = WorkoutTargetSettings(assisted: true, stepKg: 2.5);
    expect(
      resolve(
        [work(1, planned: null)],
        history: [work(9, weight: 20, reps: 5, done: true)],
        settings: settings,
      ).single.weightKg,
      17.5,
    );
    expect(
      resolve([
        work(1, planned: 20, weight: 20, reps: 4, done: true),
        work(2, planned: 20),
      ], settings: settings).last.weightKg,
      22.5,
    );
    expect(
      resolve([
        work(1, planned: 20, weight: 20, reps: 5, rpe: 95, done: true),
        work(2, planned: 20),
      ], settings: settings).last.weightKg,
      22.5,
    );
  });

  test('automatic warmups stay below first work load and omit duplicates', () {
    final targets = resolve([
      for (final p in [.4, .55, .7, .8])
        WorkoutTargetSet(
          id: (p * 100).toInt(),
          warmup: true,
          automaticWarmup: true,
          percentOf1Rm: p,
          repsMin: 5,
        ),
      const WorkoutTargetSet(
        id: 99,
        repsMin: 5,
        plannedWeightKg: 10,
        percentOf1Rm: .7,
      ),
    ]);
    final warmups = targets.take(4).where((s) => s.weightKg != null).toList();
    expect(warmups.map((s) => s.weightKg), [5.0, 7.5]);
    expect(warmups.every((s) => s.weightKg! < 10), isTrue);
    expect(warmups.every((s) => s.rpeX10 == null), isTrue);
  });

  test('manual warmup keeps explicit RPE and load', () {
    final result = resolve([
      const WorkoutTargetSet(
        id: 1,
        warmup: true,
        plannedWeightKg: 40,
        targetRpeX10: 60,
        repsMin: 5,
      ),
      work(2),
    ]).first;
    expect(result.weightKg, 40);
    expect(result.rpeX10, 60);
  });

  test('special methods do not receive ordinary overload or reductions', () {
    for (final method in ['max_effort', 'dynamic_effort']) {
      final result = resolve([
        work(1, weight: 100, reps: 4, rpe: 95, done: true),
        work(2),
      ], settings: WorkoutTargetSettings(method: method));
      expect(result.last.weightKg, 100);
    }
  });

  test('RPE capacity is bounded and does not invent missing effort', () {
    expect(WorkoutTargetResolver.capacity(100, 5, null), isNull);
    expect(WorkoutTargetResolver.capacity(100, 5, 50), isNull);
    expect(WorkoutTargetResolver.capacity(100, 12, 80), isNull);
    expect(WorkoutTargetResolver.capacity(100, 4, 95), closeTo(115, .001));
  });

  test('linear engine honours explicitly supplied repetition bounds', () {
    final target = ProgressionEngine.suggestNext(
      lastWeightKg: 100,
      lastReps: 5,
      goal: ProgressionGoal.muscleGain,
      equipmentVariant: 'barbell',
      targetRepsMin: 3,
      targetRepsMax: 5,
    );
    expect(target.reps, 3);
    expect(target.weightKg, greaterThan(100));
  });
}
