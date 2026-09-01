import 'dart:math' as math;

/// 1RM estimation. Epley and Brzycki diverge above ~10 reps; we average and
/// cap at 12 reps where formula confidence collapses.
class OneRepMax {
  static double? estimate({required double weightKg, required int reps}) {
    if (reps < 1 || reps > 12 || weightKg <= 0) return null;
    if (reps == 1) return weightKg;
    final epley = weightKg * (1 + reps / 30);
    final brzycki = weightKg * 36 / (37 - reps);
    return (epley + brzycki) / 2;
  }

  /// Quick lookup of estimated weight at target reps from a known 1RM.
  static double weightAt({required double oneRm, required int reps}) {
    if (reps == 1) return oneRm;
    return oneRm * (37 - reps) / 36;
  }
}

double roundToNearest(double value, double step) =>
    (value / step).round() * step;

double roundDownTo(double value, double step) => (value / step).floor() * step;

double floorPlateLoad(double targetKg, {double smallestPlatePairKg = 2.5}) =>
    math.max(20, roundDownTo(targetKg, smallestPlatePairKg));
