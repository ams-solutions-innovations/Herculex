import 'package:herculex/features/programs/domain/slot_role.dart';

/// A single warmup ramp step: a percentage of the working set's target
/// intensity (`%1RM`) paired with the reps performed at that percentage.
class WarmupStep {
  const WarmupStep(this.percentOf1Rm, this.reps);

  final double percentOf1Rm;
  final int reps;
}

/// Computes automatic warmup ramps from target intensity and movement order
/// (Phase 18 D-08/D-09/D-10).
///
/// Fully replaces the fixed ramp tables previously hardcoded in
/// `planned_session_resolver.dart` (`_automaticWarmups`, `_maxEffortSets`) —
/// this is the single source of warmup logic going forward.
abstract final class WarmupResolver {
  /// Modalities where a barbell/dumbbell/kettlebell-style ramp makes sense.
  static const _eligibleModalities = {'barbell', 'dumbbell', 'kettlebell'};

  /// Density table keyed on target `%1RM` (D-08): higher intensity targets
  /// get denser (more-stepped) ramps.
  static const List<(double, int)> _denseRamp = [
    (0.40, 8),
    (0.55, 5),
    (0.65, 3),
    (0.75, 2),
    (0.85, 1),
  ];
  static const List<(double, int)> _moderatelyDenseRamp = [
    (0.40, 8),
    (0.55, 5),
    (0.70, 2),
    (0.80, 1),
  ];
  static const List<(double, int)> _moderateRamp = [
    (0.40, 8),
    (0.60, 4),
    (0.70, 2),
  ];
  static const List<(double, int)> _lightRamp = [(0.40, 8), (0.60, 4)];

  /// Computes the warmup ramp for a slot, or an empty list when the slot is
  /// not eligible for automatic warmups.
  static List<WarmupStep> resolve({
    required SlotRole role,
    required String mechanics,
    required String modality,
    double? targetPercentOf1Rm,
    required bool isFirstHeavyLiftInSession,
  }) {
    final eligible =
        role.isHeavy &&
        mechanics == 'compound' &&
        _eligibleModalities.contains(modality);
    if (!eligible) return const [];

    final fullRamp = _rampFor(targetPercentOf1Rm);
    final steps = [
      for (final (percent, reps) in fullRamp) WarmupStep(percent, reps),
    ];

    if (isFirstHeavyLiftInSession) return steps;

    // D-09: subsequent heavy lifts in the same session get an abbreviated
    // ramp — the top-most/heaviest steps only, since general warmth already
    // carries over from earlier heavy work in the session.
    final abbreviatedLength = (steps.length / 2).ceil().clamp(1, steps.length);
    return steps.sublist(steps.length - abbreviatedLength);
  }

  static List<(double, int)> _rampFor(double? targetPercentOf1Rm) {
    final target = targetPercentOf1Rm;
    if (target == null) return _lightRamp;
    if (target >= 0.90) return _denseRamp;
    if (target >= 0.80) return _moderatelyDenseRamp;
    if (target >= 0.70) return _moderateRamp;
    return _lightRamp;
  }
}
