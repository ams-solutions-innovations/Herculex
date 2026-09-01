import 'periodization.dart';
import 'slot_role.dart';

/// How wide a slice of the exercise pool a slot may draw from in a given block
/// phase. Only [PeriodizationModel.block] narrows this — the other models leave
/// it [PoolTier.any].
enum PoolTier {
  /// No constraint.
  any('any'),

  /// Accumulation: higher-rep friendly variants, machines, longer ROM.
  volumeFriendly('volume_friendly'),

  /// Transmutation: competition-adjacent variants, heavier, more specific.
  competitionAdjacent('competition_adjacent'),

  /// Realization: the exact main lift. Rotation is off.
  exactMain('exact_main');

  const PoolTier(this.id);
  final String id;
}

/// The rotation rules for one slot, derived from `(model, role, phase)`.
///
/// This is the piece that makes Concurrent, Block and Max Effort mean different
/// things. Previously `rotateEveryWeeks` was a free-form user field on the
/// pool, so the three models differed only by their intensity multipliers.
class RotationPolicy {
  const RotationPolicy({
    required this.everyWeeks,
    required this.minGapWeeks,
    required this.minPoolSize,
    this.tier = PoolTier.any,
    this.lockedInPhase = false,
    this.forceOnPhaseChange = false,
  });

  /// Weeks between rotations. `0` means never rotate — the slot keeps one
  /// exercise for the whole program.
  final int everyWeeks;

  /// An exercise may not come back until this many weeks after it was last
  /// performed. Enforced as a hard filter by the scorer.
  final int minGapWeeks;

  /// Below this many pool members the slot is flagged at save time. Rotating
  /// between two lifts is alternating, not accommodation.
  final int minPoolSize;

  final PoolTier tier;

  /// Block only: the exercise may not change inside a phase.
  final bool lockedInPhase;

  /// Block only: the exercise *must* change when the phase does.
  final bool forceOnPhaseChange;

  bool get rotates => everyWeeks > 0 || forceOnPhaseChange;

  /// The policy for a slot. [blockPhase] is one of `accumulation` |
  /// `transmutation` | `realization` and is ignored for non-block models.
  static RotationPolicy forSlot({
    required PeriodizationModel model,
    required SlotRole role,
    String? blockPhase,
  }) {
    switch (model) {
      // Rotation *is* the progression: the main lift changes before the body
      // accommodates to it, and the PR is set on the new variant.
      case PeriodizationModel.maxEffort:
        return switch (role) {
          SlotRole.main => const RotationPolicy(
            everyWeeks: 2,
            minGapWeeks: 4,
            minPoolSize: 3,
          ),
          SlotRole.supplemental => const RotationPolicy(
            everyWeeks: 3,
            minGapWeeks: 3,
            minPoolSize: 2,
          ),
          SlotRole.accessory || SlotRole.isolation => const RotationPolicy(
            everyWeeks: 4,
            minGapWeeks: 2,
            minPoolSize: 1,
          ),
          SlotRole.conditioning => const RotationPolicy(
            everyWeeks: 2,
            minGapWeeks: 1,
            minPoolSize: 1,
          ),
        };

      // You need the same lift long enough to read the heavy/medium/light wave,
      // so the main slot rotates slowly.
      case PeriodizationModel.concurrent:
        return switch (role) {
          SlotRole.main => const RotationPolicy(
            everyWeeks: 4,
            minGapWeeks: 4,
            minPoolSize: 2,
          ),
          SlotRole.supplemental => const RotationPolicy(
            everyWeeks: 3,
            minGapWeeks: 3,
            minPoolSize: 2,
          ),
          SlotRole.accessory || SlotRole.isolation => const RotationPolicy(
            everyWeeks: 3,
            minGapWeeks: 2,
            minPoolSize: 1,
          ),
          SlotRole.conditioning => const RotationPolicy(
            everyWeeks: 2,
            minGapWeeks: 1,
            minPoolSize: 1,
          ),
        };

      // Locked inside a phase, forced at every phase boundary. The phase also
      // narrows which pool members are eligible.
      case PeriodizationModel.block:
        final tier = poolTierForPhase(blockPhase);
        final realization = tier == PoolTier.exactMain;
        return switch (role) {
          SlotRole.main => RotationPolicy(
            everyWeeks: 0,
            minGapWeeks: 3,
            minPoolSize: 2,
            tier: tier,
            lockedInPhase: true,
            forceOnPhaseChange: !realization,
          ),
          SlotRole.supplemental => RotationPolicy(
            everyWeeks: 0,
            minGapWeeks: 2,
            minPoolSize: 2,
            tier: tier,
            lockedInPhase: true,
            forceOnPhaseChange: true,
          ),
          SlotRole.accessory ||
          SlotRole.isolation ||
          SlotRole.conditioning => RotationPolicy(
            everyWeeks: 3,
            minGapWeeks: 2,
            minPoolSize: 1,
            tier: tier,
          ),
        };

      // The whole point is adding load to one lift, so the main slot is fixed.
      case PeriodizationModel.linear:
        return switch (role) {
          SlotRole.main => const RotationPolicy(
            everyWeeks: 0,
            minGapWeeks: 0,
            minPoolSize: 1,
          ),
          SlotRole.supplemental => const RotationPolicy(
            everyWeeks: 4,
            minGapWeeks: 4,
            minPoolSize: 1,
          ),
          SlotRole.accessory || SlotRole.isolation || SlotRole.conditioning =>
            const RotationPolicy(everyWeeks: 4, minGapWeeks: 2, minPoolSize: 1),
        };

      case PeriodizationModel.none:
        return switch (role) {
          SlotRole.main || SlotRole.supplemental => const RotationPolicy(
            everyWeeks: 2,
            minGapWeeks: 2,
            minPoolSize: 1,
          ),
          SlotRole.accessory || SlotRole.isolation || SlotRole.conditioning =>
            const RotationPolicy(everyWeeks: 2, minGapWeeks: 1, minPoolSize: 1),
        };
    }
  }

  static PoolTier poolTierForPhase(String? phase) => switch (phase) {
    'accumulation' => PoolTier.volumeFriendly,
    'transmutation' => PoolTier.competitionAdjacent,
    'realization' => PoolTier.exactMain,
    _ => PoolTier.any,
  };

  /// The rotation epoch for [weekIndex]: a counter that increments exactly when
  /// a fresh exercise is due. Two weeks sharing an epoch must resolve to the
  /// same exercise, which is what keeps the calendar stable.
  ///
  /// [phases] is the per-week block phase, as produced by
  /// [Periodization.plan]; it is only consulted when the policy is phase-bound.
  int epochFor(int weekIndex, {List<String?> phases = const []}) {
    if (lockedInPhase || forceOnPhaseChange) {
      if (phases.isEmpty) return 0;
      final upTo = weekIndex.clamp(0, phases.length - 1);
      // Epoch = how many phase changes have happened up to this week.
      var epoch = 0;
      for (var w = 1; w <= upTo; w++) {
        if (phases[w] != phases[w - 1]) epoch++;
      }
      return epoch;
    }
    if (everyWeeks <= 0) return 0;
    return weekIndex ~/ everyWeeks;
  }

  /// Convenience: the phase labels for a whole program under [model].
  static List<String?> phasesFor(PeriodizationModel model, int weeks) => [
    for (final p in Periodization.plan(model, weeks)) p.blockPhase,
  ];
}
