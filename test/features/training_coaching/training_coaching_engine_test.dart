import 'package:flutter_test/flutter_test.dart';
import 'package:herculex/features/training_coaching/domain/training_coaching.dart';

Map<String, dynamic> exercise({
  String row = 'rdl',
  String ref = 'slug:rdl',
  String muscle = 'Hamstrings',
  int planned = 4,
  int? completed,
  int order = 0,
  String variant = 'barbell',
}) => {
  'row': row,
  'exercise': ref,
  'name': ref,
  'muscle': muscle,
  'planned': planned,
  'completed': completed,
  'order': order,
  'variant': variant,
  'method': 'straight_sets',
};
final now = DateTime(2026, 10, 28, 18);
CoachingObservation observation(
  int index, {
  int completed = 2,
  String policy = 'unknown',
  List<Map<String, dynamic>>? original,
  List<Map<String, dynamic>>? actual,
  Map<String, dynamic> flags = const {},
}) => CoachingObservation({
  'session': 'session-$index',
  'program': 'program',
  'day': '1|Lower',
  'at': now.subtract(Duration(days: index * 7)).toIso8601String(),
  'known': true,
  'minutes': 35,
  'policy': policy,
  'original': original ?? [exercise()],
  'actual': actual ?? [exercise(completed: completed)],
  ...flags,
});

void main() {
  test('different gyms and periodization phases are not pooled', () {
    final list = [
      for (var i = 0; i < 4; i++)
        observation(
          i,
          flags: {
            'gym': i.isEven ? 'gym-a' : 'gym-b',
            'phase': i < 2 ? 'volume' : 'intensity',
          },
        ),
    ];
    expect(
      TrainingCoachingEngine.detect(observations: list, now: now),
      isEmpty,
    );
  });
  test(
    'repeated comparable declines can prompt a workload review even when sets are completed',
    () {
      final list = [
        for (var i = 0; i < 4; i++)
          observation(
            i,
            actual: [
              {...exercise(completed: 4), 'declined': i != 2},
            ],
          ),
      ];
      final signal = TrainingCoachingEngine.detect(
        observations: list,
        now: now,
      ).single;
      expect(signal.kind, CoachingKind.reduceSets);
      expect(signal.targetSets, 3);
      expect(signal.detail, contains('does not establish its cause'));
    },
  );
  test('three omissions among four comparable exposures trigger a review', () {
    final result = TrainingCoachingEngine.detect(
      observations: [
        for (var i = 0; i < 4; i++) observation(i, completed: i == 2 ? 4 : 2),
      ],
      now: now,
    );
    final signal = result.single;
    expect(signal.kind, CoachingKind.reduceSets);
    expect(signal.targetSets, 2);
    expect(signal.evidence.length, 4);
    expect(signal.detail, contains('do not explain the cause'));
  });
  test('two of three does not qualify as a repeated habit', () {
    expect(
      TrainingCoachingEngine.detect(
        observations: [for (var i = 0; i < 3; i++) observation(i)],
        now: now,
      ),
      isEmpty,
    );
  });
  test('late accessories omitted for time lead to an order suggestion', () {
    final result = TrainingCoachingEngine.detect(
      observations: [
        for (var i = 0; i < 4; i++)
          observation(
            i,
            policy: 'time',
            original: [
              exercise(row: 'main'),
              exercise(row: 'arms', ref: 'slug:curl', order: 1),
            ],
            actual: [exercise(row: 'main', completed: 4)],
          ),
      ],
      now: now,
    );
    expect(result.any((s) => s.kind == CoachingKind.exerciseOrder), isTrue);
  });
  test(
    'added abs align with a confirmed goal and require three distinct sessions',
    () {
      final result = TrainingCoachingEngine.detect(
        observations: [
          for (var i = 0; i < 4; i++)
            observation(
              i,
              actual: [
                exercise(completed: 4),
                if (i != 1)
                  exercise(
                    row: 'abs',
                    ref: 'slug:crunch',
                    muscle: 'Abs',
                    completed: 2,
                  ),
              ],
            ),
        ],
        now: now,
        priorityMuscles: {'Abs'},
      );
      final addition = result.singleWhere(
        (s) => s.kind == CoachingKind.goalGap,
      );
      expect(addition.detail, contains('confirmed physique priority'));
    },
  );
  test(
    'equipment substitutions are counted separately from volume omissions',
    () {
      final result = TrainingCoachingEngine.detect(
        observations: [
          for (var i = 0; i < 4; i++)
            observation(
              i,
              policy: 'equipment',
              actual: [
                exercise(
                  ref: 'slug:machine',
                  completed: 4,
                  variant: 'machine_selectorized',
                ),
              ],
            ),
        ],
        now: now,
      );
      expect(result.map((s) => s.kind), [CoachingKind.equipment]);
    },
  );
  for (final policy in [
    'unknown',
    'do_not_catch_up',
    'preference',
    'equipment',
  ]) {
    test('$policy does not produce catch-up work', () {
      expect(
        TrainingCoachingEngine.detect(
          observations: [observation(0, policy: policy)],
          now: now,
        ),
        isEmpty,
      );
    });
  }
  test('a confirmed time constraint may produce a one-time suggestion', () {
    final result = TrainingCoachingEngine.detect(
      observations: [observation(0, policy: 'time')],
      now: now,
    );
    expect(result.single.kind, CoachingKind.catchUp);
    expect(result.single.oneOff, isTrue);
  });
  for (final flag in ['corrected', 'trial', 'deload']) {
    test('$flag exposures do not teach a manual habit', () {
      expect(
        TrainingCoachingEngine.detect(
          observations: [
            for (var i = 0; i < 4; i++) observation(i, flags: {flag: true}),
          ],
          now: now,
        ),
        isEmpty,
      );
    });
  }
  test('future and unknown-prescription sessions are excluded', () {
    final list = [
      for (var i = 0; i < 4; i++) observation(i, flags: {'known': false}),
      observation(-1),
    ];
    expect(
      TrainingCoachingEngine.detect(observations: list, now: now),
      isEmpty,
    );
  });
  test('different equipment is not pooled into four comparable exposures', () {
    final list = [
      for (var i = 0; i < 4; i++)
        observation(
          i,
          original: [exercise(variant: i.isEven ? 'barbell' : 'dumbbell')],
          actual: [
            exercise(completed: 2, variant: i.isEven ? 'barbell' : 'dumbbell'),
          ],
        ),
    ];
    expect(
      TrainingCoachingEngine.detect(observations: list, now: now),
      isEmpty,
    );
  });
  test('evidence older than 84 days is excluded', () {
    expect(
      TrainingCoachingEngine.detect(
        observations: [for (var i = 13; i < 17; i++) observation(i)],
        now: now,
      ),
      isEmpty,
    );
  });
}
