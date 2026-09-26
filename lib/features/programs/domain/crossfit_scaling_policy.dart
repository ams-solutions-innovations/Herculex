/// CrossFit/GPP level-policy domain service (D-06 of 21-CONTEXT.md).
///
/// Pure, DB-free, and testable — mirrors [ExerciseScalingResolver]'s "never
/// silently relax, always return an explicit rationale" contract. Three
/// independent axes live here:
///
///   * [timeCapFor] — per-level time caps for AMRAP/EMOM/For Time.
///   * [complexityCheck] / [movementCeilingFor] — per-level movement-count
///     ceiling and advanced-movement stacking guard.
///   * [recoveryReserveWarning] — back-to-back CrossFit/GPP day-spacing
///     warnings (advisory only, weekly-mode schedules only).
library;

import 'package:herculex/features/programs/domain/programming_models.dart';
import 'package:herculex/features/workouts/domain/set_type.dart';

/// Result of [CrossfitScalingPolicy.timeCapFor].
///
/// Exactly one of [capSeconds] (AMRAP/For Time) or [minutes] (EMOM) is
/// populated when [hasCap] is true; both are null when [hasCap] is false.
class CrossfitTimeCapResult {
  const CrossfitTimeCapResult.capped({
    required this.capSeconds,
    required this.rationale,
  })  : hasCap = true,
        minutes = null;

  const CrossfitTimeCapResult.emomMinutes({
    required this.minutes,
    required this.rationale,
  })  : hasCap = true,
        capSeconds = null;

  const CrossfitTimeCapResult.noCap({required this.rationale})
      : hasCap = false,
        capSeconds = null,
        minutes = null;

  final bool hasCap;
  final int? capSeconds;
  final int? minutes;
  final String rationale;
}

/// Result of [CrossfitScalingPolicy.complexityCheck].
class CrossfitComplexityResult {
  const CrossfitComplexityResult.success({required this.rationale})
      : isSafe = true;

  const CrossfitComplexityResult.exceedsCeiling({required this.rationale})
      : isSafe = false;

  final bool isSafe;
  final String rationale;
}

/// CrossFit/GPP level-policy domain service. All members are pure static
/// functions of enum/int inputs — no I/O, no drift, no catalog dependency.
class CrossfitScalingPolicy {
  const CrossfitScalingPolicy._();

  /// Base cap, in seconds, before the per-level multiplier is applied.
  /// EMOM is expressed in minutes instead — see [_baseEmomMinutes].
  static const Map<SetType, int> _baseCapSecondsByFormat = {
    SetType.amrap: 600,
    SetType.forTime: 720,
  };

  static const int _baseEmomMinutes = 12;

  static const Map<ExperienceLevel, double> _levelMultiplier = {
    ExperienceLevel.novice: 0.75,
    ExperienceLevel.intermediate: 1.0,
    ExperienceLevel.advanced: 1.25,
  };

  /// Per-level movement-count ceiling for a single metcon. Kept private —
  /// callers outside this file must go through [movementCeilingFor], never
  /// re-declare their own copy of these numbers.
  static const Map<ExperienceLevel, int> _movementCountCeiling = {
    ExperienceLevel.novice: 2,
    ExperienceLevel.intermediate: 3,
    ExperienceLevel.advanced: 4,
  };

  /// Public accessor for the per-level movement-count ceiling. This is the
  /// value `complexityCheck` enforces internally; other Phase 21 files
  /// (`crossfit_program_planner.dart`, Plan 21-04) must read the ceiling via
  /// this method rather than maintaining a second, potentially-drifting copy.
  static int movementCeilingFor(ExperienceLevel level) =>
      _movementCountCeiling[level]!;

  /// Time cap for a metcon [format] at a given experience [level].
  ///
  /// AMRAP/For Time results are seconds; EMOM results are whole minutes
  /// (rounded). Any other [format] has no CrossFit-level time cap and
  /// returns an explicit `.noCap` result — never a silent zero/null.
  ///
  /// Note: for For Time, [CrossfitTimeCapResult.capSeconds] is a conservative
  /// upper bound used for session time-budgeting, not a predicted completion
  /// time for the athlete.
  static CrossfitTimeCapResult timeCapFor({
    required SetType format,
    required ExperienceLevel level,
  }) {
    final multiplier = _levelMultiplier[level]!;

    if (format == SetType.emom) {
      final minutes = (_baseEmomMinutes * multiplier).round();
      return CrossfitTimeCapResult.emomMinutes(
        minutes: minutes,
        rationale: 'EMOM length scaled to ${level.label} '
            '(${multiplier}x base ${_baseEmomMinutes}min) = $minutes min.',
      );
    }

    final baseSeconds = _baseCapSecondsByFormat[format];
    if (baseSeconds == null) {
      return CrossfitTimeCapResult.noCap(
        rationale: '${format.label} has no CrossFit-level time cap.',
      );
    }

    final capSeconds = (baseSeconds * multiplier).round();
    final boundNote = format == SetType.forTime
        ? ' This is a conservative time-budget upper bound, not a predicted '
            'completion time.'
        : '';
    return CrossfitTimeCapResult.capped(
      capSeconds: capSeconds,
      rationale: '${format.label} time cap scaled to ${level.label} '
          '(${multiplier}x base ${baseSeconds}s) = ${capSeconds}s.$boundNote',
    );
  }

  /// Checks whether a metcon's movement count and advanced-movement stacking
  /// stay within [level]'s ceiling.
  ///
  /// Stacking two or more advanced/just-unlocked movements in a single
  /// metcon ([advancedMovementCount] >= 2) is never allowed, regardless of
  /// [level] — this is a hard rule, not a scaled one.
  static CrossfitComplexityResult complexityCheck({
    required int movementCount,
    bool hasAdvancedMovement = false,
    int advancedMovementCount = 0,
    required ExperienceLevel level,
  }) {
    if (advancedMovementCount >= 2) {
      return CrossfitComplexityResult.exceedsCeiling(
        rationale: 'Stacking $advancedMovementCount advanced/just-unlocked '
            'movements in one metcon is never allowed, regardless of level.',
      );
    }

    final ceiling = movementCeilingFor(level);
    if (movementCount > ceiling) {
      return CrossfitComplexityResult.exceedsCeiling(
        rationale: 'Metcon has $movementCount movements, exceeding the '
            '${level.label} ceiling of $ceiling.',
      );
    }

    return CrossfitComplexityResult.success(
      rationale: 'Metcon has $movementCount movements within the '
          '${level.label} ceiling of $ceiling.',
    );
  }
}
