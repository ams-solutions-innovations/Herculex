import 'dart:math' as math;

import 'package:herculex/features/gamification/domain/level_progress.dart';
import 'package:herculex/features/gamification/domain/strength_standards.dart';
import 'package:herculex/features/profile/domain/profile.dart';

/// Best known performance on one benchmark lift, split by where it came from.
/// Values are in the lift's [StrengthMeasure]: × bodyweight or reps.
class LiftBest {
  const LiftBest({required this.lift, this.logged, this.reported});

  final StrengthLift lift;

  /// From sets logged in the app.
  final double? logged;

  /// From the onboarding strength check.
  final double? reported;

  double? get best => switch ((logged, reported)) {
    (final l?, final r?) => math.max(l, r),
    (final l?, null) => l,
    (null, final r?) => r,
    _ => null,
  };
}

/// One line of "what it takes to reach the next band".
class LiftRequirement {
  const LiftRequirement({
    required this.lift,
    required this.required,
    required this.current,
    required this.met,
    required this.needsLogging,
  });

  final StrengthLift lift;
  final double required;
  final double? current;
  final bool met;

  /// Cleared only by a self-reported number; Elite wants it logged.
  final bool needsLogging;
}

class StrengthAssessment {
  const StrengthAssessment({
    required this.tier,
    required this.bests,
    required this.sex,
  });

  static const empty = StrengthAssessment(
    tier: LevelBand.novice,
    bests: {},
    sex: null,
  );

  /// The highest band the user's strength qualifies for.
  final LevelBand tier;
  final Map<StrengthLift, LiftBest> bests;
  final BiologicalSex? sex;

  /// One line per lift listed for [band], with where the user stands.
  List<LiftRequirement> requirementsFor(LevelBand band) =>
      const StrengthTierEvaluator()._requirements(band, bests, sex);
}

/// Places a user in a band from their benchmark lifts: a band is reached when
/// [liftsNeededPerBand] lifts clear its threshold. Elite only counts logged
/// lifts — a self-reported number can open Advanced at most.
class StrengthTierEvaluator {
  const StrengthTierEvaluator();

  StrengthAssessment evaluate({
    required Map<StrengthLift, LiftBest> bests,
    required BiologicalSex? sex,
  }) {
    var tier = LevelBand.novice;
    for (final band in LevelBand.values.skip(1)) {
      if (_liftsClearing(band, bests, sex) >= liftsNeededPerBand) {
        tier = band;
      } else {
        break;
      }
    }
    return StrengthAssessment(tier: tier, bests: bests, sex: sex);
  }

  int _liftsClearing(
    LevelBand band,
    Map<StrengthLift, LiftBest> bests,
    BiologicalSex? sex,
  ) {
    var count = 0;
    for (final standard in strengthStandards) {
      final threshold = standard.effectiveThreshold(band, sex);
      final value = _valueFor(band, bests[standard.lift]);
      if (threshold != null && value != null && value >= threshold) count++;
    }
    return count;
  }

  List<LiftRequirement> _requirements(
    LevelBand band,
    Map<StrengthLift, LiftBest> bests,
    BiologicalSex? sex,
  ) {
    return [
      for (final standard in strengthStandards)
        if (standard.listedThreshold(band, sex) case final threshold?)
          _requirement(band, standard.lift, threshold, bests[standard.lift]),
    ];
  }

  LiftRequirement _requirement(
    LevelBand band,
    StrengthLift lift,
    double threshold,
    LiftBest? best,
  ) {
    final counted = _valueFor(band, best);
    final met = counted != null && counted >= threshold;
    final reported = best?.reported;
    return LiftRequirement(
      lift: lift,
      required: threshold,
      current: best?.best,
      met: met,
      needsLogging: !met && reported != null && reported >= threshold,
    );
  }

  double? _valueFor(LevelBand band, LiftBest? best) =>
      band == LevelBand.elite ? best?.logged : best?.best;
}
