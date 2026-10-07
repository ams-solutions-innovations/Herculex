import 'package:flutter_test/flutter_test.dart';
import 'package:herculex/features/programs/domain/exercise_scorer.dart';
import 'package:herculex/features/programs/domain/rotation_policy.dart';
import 'package:herculex/features/programs/domain/slot_role.dart';

const _policy = RotationPolicy(everyWeeks: 2, minGapWeeks: 3, minPoolSize: 3);

ScorerCandidate _candidate(
  int id,
  String name, {
  String pattern = 'horizontal_push',
  String modality = 'barbell',
  String? slug,
  String mechanics = 'compound',
  int cnsScore = 6,
  int recoveryImpact = 3,
  int? eligibleRoles,
  int affinity = 0,
  int? weeksSinceLastPerformed = 4,
  int loggedSessions = 10,
  int flatExposures = 0,
  bool equipmentAvailable = true,
  bool isAnchor = false,
}) {
  return ScorerCandidate(
    exerciseId: id,
    name: name,
    fingerprint: MovementFingerprint(
      pattern: pattern,
      force: 'push',
      plane: 'horizontal',
      modality: modality,
      slug: slug,
    ),
    mechanics: mechanics,
    cnsScore: cnsScore,
    recoveryImpact: recoveryImpact,
    eligibleRoles: eligibleRoles ?? SlotRoleEligibility.all,
    affinity: affinity,
    weeksSinceLastPerformed: weeksSinceLastPerformed,
    loggedSessions: loggedSessions,
    flatExposures: flatExposures,
    equipmentAvailable: equipmentAvailable,
    isAnchor: isAnchor,
  );
}

SlotScoringContext _context({
  SlotRole role = SlotRole.main,
  int weekIndex = 4,
  RotationPolicy policy = _policy,
  Map<String, double> recovery = const {},
  double cnsBudgetRemaining = 1.0,
  List<MovementFingerprint> recentPicks = const [],
  Map<int, int> weekLastAssigned = const {},
  int seed = 7,
}) {
  return SlotScoringContext(
    role: role,
    muscleGroup: 'Chest',
    weekIndex: weekIndex,
    policy: policy,
    recoveryByGroup: recovery,
    cnsBudgetRemaining: cnsBudgetRemaining,
    recentPicks: recentPicks,
    weekLastAssigned: weekLastAssigned,
    seed: seed,
  );
}

void main() {
  group('hard filters', () {
    test('a blacklisted exercise is never scored', () {
      final result = ExerciseScorer.rank(
        pool: [
          _candidate(1, 'Hated Press', affinity: -1),
          _candidate(2, 'Floor Press'),
        ],
        context: _context(),
      );
      expect(result.top!.candidate.exerciseId, 2);
      expect(result.excluded[1], FilterReason.blacklisted);
    });

    test('an isolation exercise cannot fill a main slot', () {
      final result = ExerciseScorer.rank(
        pool: [
          _candidate(
            1,
            'Cable Fly',
            mechanics: 'isolation',
            eligibleRoles: SlotRoleEligibility.of([
              SlotRole.accessory,
              SlotRole.isolation,
            ]),
          ),
          _candidate(2, 'Close-Grip Bench'),
        ],
        context: _context(role: SlotRole.main),
      );
      expect(result.top!.candidate.exerciseId, 2);
      expect(result.excluded[1], FilterReason.roleIneligible);
    });

    test('the minimum re-exposure gap keeps a recent lift out', () {
      final result = ExerciseScorer.rank(
        pool: [_candidate(1, 'Floor Press'), _candidate(2, 'Board Press')],
        context: _context(weekIndex: 4, weekLastAssigned: {1: 3}),
      );
      expect(result.top!.candidate.exerciseId, 2);
      expect(result.excluded[1], FilterReason.tooSoon);
      expect(result.relaxation, Relaxation.none);
    });

    test('the gap is relaxed rather than leaving the slot empty', () {
      final result = ExerciseScorer.rank(
        pool: [_candidate(1, 'Floor Press')],
        context: _context(weekIndex: 4, weekLastAssigned: {1: 3}),
      );
      expect(result.top!.candidate.exerciseId, 1);
      expect(result.relaxation, Relaxation.gap);
    });

    test('missing equipment is relaxed only after the gap', () {
      final result = ExerciseScorer.rank(
        pool: [_candidate(1, 'Safety Bar Squat', equipmentAvailable: false)],
        context: _context(),
      );
      expect(result.top!.candidate.exerciseId, 1);
      expect(result.relaxation, Relaxation.equipment);
    });

    test('realization pins a heavy slot to the anchor lift', () {
      final result = ExerciseScorer.rank(
        pool: [
          _candidate(1, 'Floor Press'),
          _candidate(2, 'Competition Bench', isAnchor: true),
        ],
        context: _context(
          policy: const RotationPolicy(
            everyWeeks: 0,
            minGapWeeks: 0,
            minPoolSize: 2,
            tier: PoolTier.exactMain,
            lockedInPhase: true,
          ),
        ),
      );
      expect(result.top!.candidate.exerciseId, 2);
      expect(result.excluded[1], FilterReason.notAnchor);
    });

    test('an empty pool yields no pick rather than throwing', () {
      final result = ExerciseScorer.rank(pool: [], context: _context());
      expect(result.top, isNull);
      expect(result.ranked, isEmpty);
    });

    test('an all-blacklisted pool still returns something usable', () {
      final result = ExerciseScorer.rank(
        pool: [
          _candidate(1, 'A', affinity: -1),
          _candidate(2, 'B', affinity: -1, isAnchor: true),
        ],
        context: _context(),
      );
      expect(result.relaxation, Relaxation.anchor);
      expect(result.top!.candidate.exerciseId, 2);
    });
  });

  group('scoring', () {
    test('a stalled lift loses to a fresh one — the accommodation law', () {
      final result = ExerciseScorer.rank(
        pool: [
          _candidate(1, 'Close-Grip Bench', flatExposures: 4),
          _candidate(2, 'Floor Press'),
        ],
        context: _context(),
      );
      expect(result.top!.candidate.exerciseId, 2);
      expect(result.top!.why, contains('Floor Press'));
    });

    test('stagnation matters far less for pump work', () {
      final heavy = ExerciseScorer.rank(
        pool: [_candidate(1, 'Bench', flatExposures: 4)],
        context: _context(role: SlotRole.main),
      ).top!;
      final light = ExerciseScorer.rank(
        pool: [_candidate(1, 'Bench', flatExposures: 4)],
        context: _context(role: SlotRole.accessory),
      ).top!;
      expect(
        heavy.breakdown['stagnation']!.abs(),
        greaterThan(light.breakdown['stagnation']!.abs()),
      );
    });

    test('a longer layoff wins all else being equal', () {
      final result = ExerciseScorer.rank(
        pool: [
          _candidate(1, 'Recent', weeksSinceLastPerformed: 1),
          _candidate(2, 'Stale', weeksSinceLastPerformed: 8),
        ],
        context: _context(
          policy: const RotationPolicy(
            everyWeeks: 2,
            minGapWeeks: 0,
            minPoolSize: 1,
          ),
        ),
      );
      expect(result.top!.candidate.exerciseId, 2);
    });

    test('a favourite beats a neutral exercise', () {
      final result = ExerciseScorer.rank(
        pool: [_candidate(1, 'Neutral'), _candidate(2, 'Beloved', affinity: 2)],
        context: _context(),
      );
      expect(result.top!.candidate.exerciseId, 2);
      expect(result.top!.why, contains('core lift'));
    });

    test('a fatigued muscle group penalizes the most systemic option', () {
      final result = ExerciseScorer.rank(
        pool: [
          _candidate(1, 'Heavy Compound', recoveryImpact: 5),
          _candidate(2, 'Easier Variant', recoveryImpact: 1),
        ],
        context: _context(recovery: {'Chest': 0.2}),
      );
      expect(result.top!.candidate.exerciseId, 2);
    });

    test('a heavy slot avoids a movement with almost no history', () {
      final result = ExerciseScorer.rank(
        pool: [
          _candidate(
            1,
            'Barely Done',
            loggedSessions: 0,
            weeksSinceLastPerformed: null,
          ),
          _candidate(
            2,
            'Well Known',
            loggedSessions: 20,
            weeksSinceLastPerformed: 6,
          ),
        ],
        context: _context(role: SlotRole.main),
      );
      expect(result.top!.candidate.exerciseId, 2);
    });

    test('swapping the handle is not variety for accessory work', () {
      const recent = MovementFingerprint(
        pattern: 'horizontal_push',
        force: 'push',
        plane: 'horizontal',
        modality: 'cable',
        slug: 'fly-isolation',
      );
      final result = ExerciseScorer.rank(
        pool: [
          _candidate(
            1,
            'Pec Deck',
            modality: 'machine_selectorized',
            slug: 'fly-isolation',
            mechanics: 'isolation',
          ),
          _candidate(
            2,
            'Dumbbell Press',
            modality: 'dumbbell',
            slug: 'bench-press',
          ),
        ],
        context: _context(
          role: SlotRole.accessory,
          recentPicks: const [recent],
        ),
      );
      expect(result.top!.candidate.exerciseId, 2);
    });

    test('a modality change inside one movement counts for a heavy slot '
        'but not for pump work', () {
      const recent = MovementFingerprint(
        pattern: 'horizontal_push',
        force: 'push',
        plane: 'horizontal',
        modality: 'barbell',
        slug: 'bench-press',
      );
      ScorerCandidate sameFamily() => _candidate(
        1,
        'Dumbbell Floor Press',
        modality: 'dumbbell',
        slug: 'bench-press',
      );

      final heavy = ExerciseScorer.rank(
        pool: [sameFamily()],
        context: _context(role: SlotRole.main, recentPicks: const [recent]),
      ).top!;
      final pump = ExerciseScorer.rank(
        pool: [sameFamily()],
        context: _context(
          role: SlotRole.accessory,
          recentPicks: const [recent],
        ),
      ).top!;

      // Barbell bench -> dumbbell floor press is real accommodation for a max
      // effort slot; for accessory work it is just a different handle.
      expect(
        heavy.breakdown['variety'],
        greaterThan(pump.breakdown['variety']!),
      );
    });

    test('a like-for-like repeat scores the worst variety there is', () {
      const recent = MovementFingerprint(
        pattern: 'horizontal_push',
        force: 'push',
        plane: 'horizontal',
        modality: 'barbell',
        slug: 'bench-press',
      );
      final repeat = ExerciseScorer.rank(
        pool: [
          _candidate(
            1,
            'Barbell Bench',
            modality: 'barbell',
            slug: 'bench-press',
          ),
        ],
        context: _context(role: SlotRole.main, recentPicks: const [recent]),
      ).top!;
      expect(repeat.breakdown['variety'], -1.0);
    });

    test('block phase tier steers accumulation toward machines', () {
      final result = ExerciseScorer.rank(
        pool: [
          _candidate(1, 'Barbell Bench', modality: 'barbell'),
          _candidate(2, 'Machine Press', modality: 'machine_selectorized'),
        ],
        context: _context(
          role: SlotRole.accessory,
          policy: const RotationPolicy(
            everyWeeks: 3,
            minGapWeeks: 0,
            minPoolSize: 1,
            tier: PoolTier.volumeFriendly,
          ),
        ),
      );
      expect(result.top!.candidate.exerciseId, 2);
    });
  });

  group('determinism', () {
    test('the same seed always produces the same order', () {
      final pool = [_candidate(1, 'A'), _candidate(2, 'B'), _candidate(3, 'C')];
      final first = ExerciseScorer.rank(
        pool: pool,
        context: _context(seed: 42),
      );
      final second = ExerciseScorer.rank(
        pool: pool,
        context: _context(seed: 42),
      );
      expect(
        first.ranked.map((e) => e.candidate.exerciseId),
        second.ranked.map((e) => e.candidate.exerciseId),
      );
    });

    test('identical candidates are separated only by the seed', () {
      final pool = [_candidate(1, 'A'), _candidate(2, 'B')];
      final seeds = <int>{};
      for (var s = 0; s < 40; s++) {
        seeds.add(
          ExerciseScorer.rank(
            pool: pool,
            context: _context(seed: s),
          ).top!.candidate.exerciseId,
        );
      }
      // Re-rolling must actually be able to change the answer.
      expect(seeds.length, 2);
    });

    test('the jitter never overturns a real difference', () {
      final result = ExerciseScorer.rank(
        pool: [
          _candidate(1, 'Stalled', flatExposures: 4),
          _candidate(2, 'Fresh'),
        ],
        context: _context(seed: 999),
      );
      expect(result.top!.candidate.exerciseId, 2);
    });
  });

  group('why', () {
    test('every pick carries an explanation naming the exercise', () {
      final result = ExerciseScorer.rank(
        pool: [_candidate(1, 'Floor Press', weeksSinceLastPerformed: 5)],
        context: _context(),
      );
      expect(result.top!.why, startsWith('Floor Press'));
      expect(result.top!.why, endsWith('.'));
    });
  });

  group('alternates', () {
    test('the swap sheet gets the runners-up, not the winner', () {
      final result = ExerciseScorer.rank(
        pool: [
          _candidate(1, 'A', affinity: 2),
          _candidate(2, 'B', affinity: 1),
          _candidate(3, 'C'),
        ],
        context: _context(
          policy: const RotationPolicy(
            everyWeeks: 2,
            minGapWeeks: 0,
            minPoolSize: 1,
          ),
        ),
      );
      final alternates = result.alternates();
      expect(alternates, hasLength(2));
      expect(
        alternates.map((a) => a.candidate.exerciseId),
        isNot(contains(result.top!.candidate.exerciseId)),
      );
    });
  });
}
