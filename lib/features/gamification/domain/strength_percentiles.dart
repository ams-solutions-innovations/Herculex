import 'package:herculex/features/gamification/domain/strength_standards.dart';
import 'package:herculex/features/gamification/domain/strength_tier_evaluator.dart';
import 'package:herculex/features/profile/domain/profile.dart';

/// Where one logged lift sits, as "top X %". Smaller is better.
class LiftPercentile {
  const LiftPercentile({
    required this.lift,
    required this.value,
    required this.lifterTopPct,
    required this.worldTopPct,
  });

  final StrengthLift lift;

  /// In the lift's [StrengthMeasure]: × bodyweight or reps.
  final double value;

  /// Among people who train.
  final double lifterTopPct;

  /// Among all adults — a rougher estimate, see [StrengthPercentiles].
  final double worldTopPct;
}

/// Turns benchmark lifts into "top X %" numbers for the Level section.
///
/// These are estimates for fun, like the rank standards they are built on.
/// The lifter curve is anchored to [strengthStandards] so a rank and a
/// percentile can never contradict each other: Intermediate is the median
/// lifter (top 50 %), Advanced the top 20 %, Elite the top 5 %. Between
/// anchors the curve is linear.
///
/// The world number assumes everyone outside the trained population would
/// rank below the weakest lifter, so `world = lifter × share`, where share is
/// a rough guess at the fraction of adults who train the lift at all.
abstract final class StrengthPercentiles {
  /// Top-% at each band threshold: Intermediate, Advanced, Elite.
  static const _bandTopPct = [50.0, 20.0, 5.0];

  /// A beginner anchor below Intermediate so the bottom of the curve is not a
  /// straight line from zero.
  static const _beginnerFraction = 0.6;
  static const _beginnerTopPct = 85.0;

  /// Beyond Elite the curve keeps going to this multiple of the Elite value.
  static const _ceilingFraction = 1.4;
  static const _ceilingTopPct = 0.5;

  /// The floor shown, so nobody reads "top 0 %".
  static const minTopPct = 0.1;

  /// Rough fraction of adults who train each lift at all.
  static const worldShare = <StrengthLift, double>{
    StrengthLift.squat: 0.15,
    StrengthLift.bench: 0.15,
    StrengthLift.deadlift: 0.12,
    StrengthLift.overheadPress: 0.10,
    StrengthLift.pullUp: 0.20,
    StrengthLift.dip: 0.25,
    StrengthLift.pushUp: 0.50,
    StrengthLift.muscleUp: 0.05,
  };

  /// Top-% among lifters for [value] on [lift].
  static double lifterTopPct(
    StrengthLift lift,
    double value,
    BiologicalSex? sex,
  ) {
    final standard = strengthStandards.firstWhere((s) => s.lift == lift);
    final row = sex == BiologicalSex.female ? standard.female : standard.male;

    // (value, top %) anchors, ascending by value.
    final points = <(double, double)>[(0, 100)];
    final first = row.firstWhere((v) => v != null)!;
    // A lift that is not listed for Intermediate (the muscle-up) starts hard:
    // its first rep already is the Advanced anchor.
    if (row.first != null) {
      points.add((first * _beginnerFraction, _beginnerTopPct));
    }
    for (var i = 0; i < row.length; i++) {
      final v = row[i];
      if (v != null) points.add((v, _bandTopPct[i]));
    }
    final elite = row.last!;
    points.add((elite * _ceilingFraction, _ceilingTopPct));

    if (value <= 0) return 100;
    for (var i = 1; i < points.length; i++) {
      final (x1, y1) = points[i];
      if (value <= x1) {
        final (x0, y0) = points[i - 1];
        return y0 + (y1 - y0) * (value - x0) / (x1 - x0);
      }
    }
    return _ceilingTopPct;
  }

  /// One entry per lift with a logged value, best (smallest top-%) first.
  /// Self-reported survey numbers are left out: the point is that the number
  /// moves when you log a better set.
  static List<LiftPercentile> evaluate(StrengthAssessment assessment) {
    final out = <LiftPercentile>[];
    for (final MapEntry(key: lift, value: best) in assessment.bests.entries) {
      final value = best.logged;
      if (value == null || value <= 0) continue;
      final lifter = lifterTopPct(lift, value, assessment.sex);
      final world = lifter * (worldShare[lift] ?? 0.1);
      out.add(
        LiftPercentile(
          lift: lift,
          value: value,
          lifterTopPct: _floor(lifter),
          worldTopPct: _floor(world),
        ),
      );
    }
    out.sort((a, b) {
      final byPct = a.lifterTopPct.compareTo(b.lifterTopPct);
      return byPct != 0 ? byPct : a.lift.index.compareTo(b.lift.index);
    });
    return out;
  }

  /// The lift to feature on [day]: rotates daily through the lifts that are in
  /// the top half of lifters, or shows the best one when none are.
  static LiftPercentile? highlight(List<LiftPercentile> all, DateTime day) {
    if (all.isEmpty) return null;
    final strong = all.where((p) => p.lifterTopPct <= 50).toList();
    if (strong.isEmpty) return all.first;
    final dayIndex = DateTime(
      day.year,
      day.month,
      day.day,
    ).difference(DateTime(2000)).inDays;
    return strong[dayIndex % strong.length];
  }

  static double _floor(double pct) => pct < minTopPct ? minTopPct : pct;
}

/// "10%", "3%", "0.5%" — whole numbers from 1 % up.
String formatTopPct(double pct) =>
    pct >= 1 ? '${pct.round()}%' : '${pct.toStringAsFixed(1)}%';
