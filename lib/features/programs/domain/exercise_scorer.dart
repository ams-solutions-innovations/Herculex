import 'dart:math' as math;

import 'rotation_policy.dart';
import 'slot_role.dart';

/// The attributes that make two exercises feel different. Used by the variety
/// term — rotating Barbell Bench → Dumbbell Bench is a real change for a
/// max-effort slot and barely a change for an accessory slot.
class MovementFingerprint {
  const MovementFingerprint({
    this.pattern,
    this.force = 'push',
    this.plane = 'none',
    this.modality = 'barbell',
    this.slug,
  });

  final String? pattern;
  final String force;
  final String plane;
  final String modality;

  /// `ExerciseCatalog.movementSlug` — every equipment variant of one movement
  /// shares it.
  final String? slug;
}

/// One exercise the scorer may choose, flattened out of the catalog, the
/// preference table and the user's history so the engine stays pure Dart and
/// unit-testable without a database.
class ScorerCandidate {
  const ScorerCandidate({
    required this.exerciseId,
    required this.name,
    required this.fingerprint,
    this.mechanics = 'compound',
    this.cnsScore = 3,
    this.recoveryImpact = 3,
    this.eligibleRoles = SlotRoleEligibility.all,
    this.affinity = 0,
    this.weeksSinceLastPerformed,
    this.loggedSessions = 0,
    this.flatExposures = 0,
    this.equipmentAvailable = true,
    this.isAnchor = false,
  });

  final int exerciseId;
  final String name;
  final MovementFingerprint fingerprint;

  /// `compound` | `isolation`.
  final String mechanics;

  /// 1–10, from the catalog.
  final int cnsScore;

  /// 1–5, from the catalog.
  final int recoveryImpact;

  /// [SlotRoleEligibility] bitmask.
  final int eligibleRoles;

  /// -1 never · 0 ok · 1 like · 2 core lift.
  final int affinity;

  /// Null when the user has never performed it.
  final int? weeksSinceLastPerformed;

  /// Lifetime logged sessions — you cannot max a lift you have never done.
  final int loggedSessions;

  /// Consecutive recent exposures with no estimated-1RM improvement.
  final int flatExposures;

  /// False when the exercise needs equipment the program's gym does not have.
  final bool equipmentAvailable;

  /// The pool's default exercise. Realization phases lock onto it.
  final bool isAnchor;
}

/// Everything about the slot and the moment that the scorer needs.
class SlotScoringContext {
  const SlotScoringContext({
    required this.role,
    required this.muscleGroup,
    required this.weekIndex,
    required this.policy,
    this.recoveryByGroup = const {},
    this.cnsBudgetRemaining = 1.0,
    this.recentPicks = const [],
    this.weekLastAssigned = const {},
    this.seed = 0,
  });

  final SlotRole role;

  /// One of the 19 recovery groups.
  final String muscleGroup;
  final int weekIndex;
  final RotationPolicy policy;

  /// Muscle group → recovery fraction, 1.0 = fully recovered.
  final Map<String, double> recoveryByGroup;

  /// 1.0 = the week's CNS budget is untouched, 0.0 = spent.
  final double cnsBudgetRemaining;

  /// Fingerprints of what this slot most recently ran, newest first.
  final List<MovementFingerprint> recentPicks;

  /// exerciseId → the last program week this slot assigned it. Drives the
  /// minimum re-exposure gap.
  final Map<int, int> weekLastAssigned;

  /// Makes ties reproducible: the preview and the calendar must agree.
  final int seed;
}

/// Relative importance of each scoring term. Kept in one place so the engine
/// is tunable without hunting through the maths.
class ScorerWeights {
  const ScorerWeights({
    this.stagnation = 3.0,
    this.staleness = 1.5,
    this.recovery = 1.2,
    this.cns = 1.2,
    this.affinity = 1.0,
    this.variety = 1.0,
    this.tierFit = 1.0,
    this.novelty = 0.8,
  });

  final double stagnation;
  final double staleness;
  final double recovery;
  final double cns;
  final double affinity;
  final double variety;
  final double tierFit;
  final double novelty;

  static const standard = ScorerWeights();
}

/// A candidate with its score and the sentence explaining it.
class ScoredExercise {
  const ScoredExercise({
    required this.candidate,
    required this.score,
    required this.why,
    required this.breakdown,
  });

  final ScorerCandidate candidate;
  final double score;

  /// One sentence, shown on tap. Composed from the terms that actually moved
  /// the number. If a pick cannot produce this, the rule behind it is wrong.
  final String why;

  /// Term name → signed contribution, for debugging and for the "why" builder.
  final Map<String, double> breakdown;
}

/// Why a candidate was excluded before scoring.
enum FilterReason {
  blacklisted('Marked never'),
  roleIneligible('Not suitable for this slot'),
  equipmentMissing('Not available at this gym'),
  tooSoon('Performed too recently'),
  notAnchor('Realization phase uses the main lift only');

  const FilterReason(this.label);
  final String label;
}

/// How much the hard filters had to be loosened to produce a result.
enum Relaxation {
  /// Everything held.
  none,

  /// The minimum re-exposure gap was ignored — the pool is too small.
  gap,

  /// Equipment availability was ignored — flag the session.
  equipment,

  /// Nothing survived; the pool anchor was used.
  anchor,
}

class ScorerResult {
  const ScorerResult({
    required this.ranked,
    required this.relaxation,
    this.excluded = const {},
  });

  /// Best first. Empty only when the pool itself was empty.
  final List<ScoredExercise> ranked;
  final Relaxation relaxation;

  /// exerciseId → why it never got scored.
  final Map<int, FilterReason> excluded;

  ScoredExercise? get top => ranked.isEmpty ? null : ranked.first;

  /// The alternates offered behind a "Swap" tap.
  List<ScoredExercise> alternates({int count = 3}) =>
      ranked.skip(1).take(count).toList(growable: false);
}

/// Smart Exercise Rotation. Replaces the blind round-robin
/// `(weekIndex ~/ every) % memberCount`.
///
/// Hard filters remove candidates outright; the survivors are scored and the
/// best one wins. Ties break on a program-stable seed, so the preview shown in
/// the builder is byte-identical to what lands on the calendar.
abstract final class ExerciseScorer {
  /// Exposures with no estimated-1RM gain at which stagnation is fully counted.
  static const _stagnationCap = 4;

  /// Weeks after which an exercise counts as maximally stale.
  static const _stalenessCap = 8;

  /// Sessions below which a heavy slot treats an exercise as untested.
  static const _noveltyFloor = 2;

  static ScorerResult rank({
    required List<ScorerCandidate> pool,
    required SlotScoringContext context,
    ScorerWeights weights = ScorerWeights.standard,
  }) {
    if (pool.isEmpty) {
      return const ScorerResult(ranked: [], relaxation: Relaxation.none);
    }

    for (final relaxation in Relaxation.values) {
      final excluded = <int, FilterReason>{};
      final survivors = <ScorerCandidate>[];

      for (final c in pool) {
        final reason = _reject(c, context, relaxation);
        if (reason == null) {
          survivors.add(c);
        } else {
          excluded[c.exerciseId] = reason;
        }
      }

      if (survivors.isEmpty) continue;

      final scored = [
        for (final c in survivors) _score(c, context, weights),
      ]..sort((a, b) => b.score.compareTo(a.score));

      return ScorerResult(
        ranked: scored,
        relaxation: relaxation,
        excluded: excluded,
      );
    }

    // Nothing survived even the loosest filter: fall back to the anchor, or the
    // first pool member. Never return null — an empty slot is worse than an
    // imperfect one.
    final anchor = pool.firstWhere((c) => c.isAnchor, orElse: () => pool.first);
    return ScorerResult(
      ranked: [
        ScoredExercise(
          candidate: anchor,
          score: 0,
          why: 'Every alternative was filtered out, so the pool default was '
              'used.',
          breakdown: const {},
        ),
      ],
      relaxation: Relaxation.anchor,
    );
  }

  /// The single pick for this slot and week.
  static ScoredExercise? pick({
    required List<ScorerCandidate> pool,
    required SlotScoringContext context,
    ScorerWeights weights = ScorerWeights.standard,
  }) =>
      rank(pool: pool, context: context, weights: weights).top;

  // ── Hard filters ───────────────────────────────────────────────────────────

  static FilterReason? _reject(
    ScorerCandidate c,
    SlotScoringContext ctx,
    Relaxation relaxation,
  ) {
    if (c.affinity < 0) return FilterReason.blacklisted;
    if (!SlotRoleEligibility.allows(c.eligibleRoles, ctx.role)) {
      return FilterReason.roleIneligible;
    }
    if (ctx.policy.tier == PoolTier.exactMain &&
        ctx.role.isHeavy &&
        !c.isAnchor) {
      return FilterReason.notAnchor;
    }

    final ignoreEquipment = relaxation == Relaxation.equipment ||
        relaxation == Relaxation.anchor;
    if (!c.equipmentAvailable && !ignoreEquipment) {
      return FilterReason.equipmentMissing;
    }

    final ignoreGap = relaxation != Relaxation.none;
    if (!ignoreGap && ctx.policy.minGapWeeks > 0) {
      final last = ctx.weekLastAssigned[c.exerciseId];
      if (last != null && ctx.weekIndex - last < ctx.policy.minGapWeeks) {
        return FilterReason.tooSoon;
      }
    }

    return null;
  }

  // ── Scoring ────────────────────────────────────────────────────────────────

  static ScoredExercise _score(
    ScorerCandidate c,
    SlotScoringContext ctx,
    ScorerWeights w,
  ) {
    final breakdown = <String, double>{};

    // Stagnation. An exercise whose e1RM has been flat is a bad pick right now
    // — this is what rotates you away from a stalled lift (the accommodation
    // law) without any explicit trigger. Only meaningful where load matters.
    final stagnationRelevance = ctx.role.isHeavy ? 1.0 : 0.35;
    final stagnation =
        (c.flatExposures.clamp(0, _stagnationCap) / _stagnationCap) *
            stagnationRelevance;
    if (stagnation > 0) breakdown['stagnation'] = -w.stagnation * stagnation;

    // Staleness. Never performed counts as maximally stale.
    final weeksSince = c.weeksSinceLastPerformed;
    final staleness = weeksSince == null
        ? 1.0
        : math.min(weeksSince, _stalenessCap) / _stalenessCap;
    if (staleness > 0) breakdown['staleness'] = w.staleness * staleness;

    // Recovery of the target group. 1.0 = fully recovered.
    final recovered = ctx.recoveryByGroup[ctx.muscleGroup] ?? 1.0;
    final recoveryDebt = (1.0 - recovered).clamp(0.0, 1.0);
    if (recoveryDebt > 0) {
      // A heavy systemic exercise on a group that is still down costs more.
      final impact = c.recoveryImpact.clamp(1, 5) / 5;
      breakdown['recovery'] = -w.recovery * recoveryDebt * impact;
    }

    // CNS budget for the week.
    final cnsSpent = (1.0 - ctx.cnsBudgetRemaining).clamp(0.0, 1.0);
    if (cnsSpent > 0) {
      final cost = c.cnsScore.clamp(1, 10) / 10;
      breakdown['cns'] = -w.cns * cnsSpent * cost;
    }

    // Affinity, -1 already filtered out.
    if (c.affinity > 0) {
      breakdown['affinity'] = w.affinity * (c.affinity.clamp(0, 2) / 2);
    }

    // Variety against what this slot ran recently.
    final variety = _variety(c, ctx);
    if (variety != 0) breakdown['variety'] = w.variety * variety;

    // Block phase fit.
    final tierFit = _tierFit(c, ctx.policy.tier);
    if (tierFit != 0) breakdown['tierFit'] = w.tierFit * tierFit;

    // Novelty penalty: a heavy slot should not prescribe a maximal single on a
    // movement the user has barely done.
    if (ctx.role.isHeavy && c.loggedSessions < _noveltyFloor) {
      final shortfall = (_noveltyFloor - c.loggedSessions) / _noveltyFloor;
      breakdown['novelty'] = -w.novelty * shortfall;
    }

    var total = breakdown.values.fold(0.0, (sum, v) => sum + v);
    total += _jitter(ctx.seed, c.exerciseId);

    return ScoredExercise(
      candidate: c,
      score: total,
      why: _why(c, ctx, breakdown),
      breakdown: breakdown,
    );
  }

  /// -1 (indistinguishable from the last pick) … +1 (nothing in common).
  static double _variety(ScorerCandidate c, SlotScoringContext ctx) {
    if (ctx.recentPicks.isEmpty) return 0.0;

    var weighted = 0.0;
    var weightSum = 0.0;
    for (var i = 0; i < math.min(ctx.recentPicks.length, 2); i++) {
      final recent = ctx.recentPicks[i];
      final recency = i == 0 ? 1.0 : 0.5;
      weighted += recency * _distance(c, recent, ctx.role);
      weightSum += recency;
    }
    if (weightSum == 0) return 0.0;
    return (weighted / weightSum) * 2 - 1;
  }

  /// 0 … 1 across pattern / force / plane / modality, with a slug rule that
  /// depends on the role.
  static double _distance(
    ScorerCandidate c,
    MovementFingerprint recent,
    SlotRole role,
  ) {
    final f = c.fingerprint;
    var differing = 0;
    if (f.pattern != recent.pattern) differing++;
    if (f.force != recent.force) differing++;
    if (f.plane != recent.plane) differing++;
    if (f.modality != recent.modality) differing++;
    var distance = differing / 4;

    final sameMovement =
        f.slug != null && recent.slug != null && f.slug == recent.slug;
    if (sameMovement) {
      if (role.isHeavy) {
        // Barbell floor press after close-grip bench is legitimate
        // accommodation: the load pattern changes even though the movement
        // family does not. Only a like-for-like repeat is uninteresting.
        if (f.modality == recent.modality) distance = 0;
      } else {
        // For pump work, swapping the handle is not variety.
        distance *= 0.25;
      }
    }
    return distance.clamp(0.0, 1.0);
  }

  /// -1 … +1 fit against a block phase's preferred pool tier.
  static double _tierFit(ScorerCandidate c, PoolTier tier) {
    const volumeFriendly = {
      'machine_selectorized',
      'machine_plate',
      'cable',
      'dumbbell',
    };
    const specific = {'barbell', 'smith'};

    return switch (tier) {
      PoolTier.any => 0.0,
      PoolTier.volumeFriendly =>
        volumeFriendly.contains(c.fingerprint.modality) ? 1.0 : -0.5,
      PoolTier.competitionAdjacent => specific.contains(c.fingerprint.modality)
          ? (c.mechanics == 'compound' ? 1.0 : 0.0)
          : -0.5,
      // Realization is enforced by the hard filter for heavy roles; for the
      // rest a nudge toward the anchor is enough.
      PoolTier.exactMain => c.isAnchor ? 1.0 : -1.0,
    };
  }

  /// Small, stable, and smaller than any real term — breaks ties without ever
  /// overturning a decision.
  static double _jitter(int seed, int exerciseId) {
    var h = 0x811c9dc5 ^ seed;
    h = (h * 16777619) & 0x7fffffff;
    h ^= exerciseId;
    h = (h * 16777619) & 0x7fffffff;
    return (h % 1000) / 1000 * 0.001;
  }

  static String _why(
    ScorerCandidate c,
    SlotScoringContext ctx,
    Map<String, double> breakdown,
  ) {
    if (breakdown.isEmpty) {
      return '${c.name} is the only option that fits this slot.';
    }

    final terms = breakdown.entries.toList()
      ..sort((a, b) => b.value.abs().compareTo(a.value.abs()));

    final parts = <String>[];
    for (final e in terms.take(2)) {
      final phrase = _phrase(e.key, e.value, c, ctx);
      if (phrase != null) parts.add(phrase);
    }
    if (parts.isEmpty) return '${c.name} scored highest for this slot.';
    return '${c.name}: ${parts.join('; ')}.';
  }

  static String? _phrase(
    String term,
    double value,
    ScorerCandidate c,
    SlotScoringContext ctx,
  ) {
    final positive = value > 0;
    switch (term) {
      case 'stagnation':
        return 'estimated 1RM flat for ${c.flatExposures} exposures';
      case 'staleness':
        final weeks = c.weeksSinceLastPerformed;
        return weeks == null
            ? 'never trained before'
            : 'not trained for $weeks ${weeks == 1 ? 'week' : 'weeks'}';
      case 'recovery':
        return '${ctx.muscleGroup} is still recovering';
      case 'cns':
        return 'high CNS cost late in the week';
      case 'affinity':
        return c.affinity >= 2 ? 'one of your core lifts' : 'a favourite';
      case 'variety':
        return positive
            ? 'a different pattern from last time'
            : 'close to what you just did';
      case 'tierFit':
        return positive ? 'suits this block phase' : 'off-phase for this block';
      case 'novelty':
        return 'only ${c.loggedSessions} logged '
            '${c.loggedSessions == 1 ? 'session' : 'sessions'}';
      default:
        return null;
    }
  }
}
