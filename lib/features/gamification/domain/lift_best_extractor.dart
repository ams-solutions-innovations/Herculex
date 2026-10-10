import 'dart:math' as math;

import 'package:herculex/features/analytics/domain/training_snapshot.dart';
import 'package:herculex/features/gamification/domain/strength_standards.dart';
import 'package:herculex/features/gamification/domain/strength_survey.dart';
import 'package:herculex/features/gamification/domain/strength_tier_evaluator.dart';
import 'package:herculex/features/workouts/domain/one_rep_max.dart';

/// The parts of a logged set the strength standards need.
class LiftSetSample {
  const LiftSetSample({
    required this.lift,
    required this.loadKg,
    required this.reps,
    this.bodyweightKg,
    this.assisted = false,
  });

  final StrengthLift lift;

  /// Effective bar load for barbell lifts; unused for calisthenics.
  final double loadKg;
  final int reps;

  /// Bodyweight stored on the set, when the logger captured one.
  final double? bodyweightKg;

  /// Band- or machine-assisted, or a negative logged weight.
  final bool assisted;

  /// Null when the set is not one of the benchmark lifts.
  static LiftSetSample? fromResolved(ResolvedSet set) {
    final slug = set.exercise.slug;
    final lift = slug == null ? null : StrengthLift.forSlug(slug);
    if (lift == null) return null;
    return LiftSetSample(
      lift: lift,
      loadKg: set.effectiveKg,
      reps: set.set.reps,
      bodyweightKg: set.set.bodyweightKg,
      assisted:
          set.equipmentVariant == 'band' ||
          set.set.weightKg < 0 ||
          set.bands.any((b) => !b.isResistance),
    );
  }
}

/// Reduces logged sets and the onboarding survey to one [LiftBest] per lift.
class LiftBestExtractor {
  const LiftBestExtractor();

  Map<StrengthLift, LiftBest> extract({
    required Iterable<LiftSetSample> samples,
    required double? profileBodyweightKg,
    StrengthSurvey? survey,
  }) {
    final logged = <StrengthLift, double>{};
    for (final sample in samples) {
      final value = _loggedValue(sample, profileBodyweightKg);
      if (value == null) continue;
      logged[sample.lift] = math.max(logged[sample.lift] ?? 0, value);
    }

    final reported = <StrengthLift, double>{};
    survey?.lifts.forEach((lift, entry) {
      final value = _reportedValue(lift, entry, profileBodyweightKg);
      if (value != null) reported[lift] = value;
    });

    return {
      for (final lift in {...logged.keys, ...reported.keys})
        lift: LiftBest(
          lift: lift,
          logged: logged[lift],
          reported: reported[lift],
        ),
    };
  }

  double? _loggedValue(LiftSetSample sample, double? profileBodyweightKg) {
    if (sample.reps < 1) return null;
    switch (sample.lift.measure) {
      case StrengthMeasure.reps:
        return sample.assisted ? null : sample.reps.toDouble();
      case StrengthMeasure.bodyweightRatio:
        return _ratio(
          sample.loadKg,
          sample.reps,
          sample.bodyweightKg ?? profileBodyweightKg,
        );
    }
  }

  double? _reportedValue(
    StrengthLift lift,
    SurveyLiftEntry entry,
    double? bodyweightKg,
  ) {
    if (entry.reps < 1) return null;
    return switch (lift.measure) {
      StrengthMeasure.reps => entry.reps.toDouble(),
      StrengthMeasure.bodyweightRatio => _ratio(
        entry.weightKg ?? 0,
        entry.reps,
        bodyweightKg,
      ),
    };
  }

  double? _ratio(double loadKg, int reps, double? bodyweightKg) {
    if (bodyweightKg == null || bodyweightKg <= 0) return null;
    final oneRm = OneRepMax.estimate(weightKg: loadKg, reps: reps);
    return oneRm == null ? null : oneRm / bodyweightKg;
  }
}
