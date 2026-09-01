import 'package:herculex/features/workouts/domain/set_type.dart';

/// Band attached to a set, resolved to its tension.
class BandContribution {
  final double tensionKg;
  final int count;

  /// true ⇒ resistance (adds load at top), false ⇒ assistance (removes load).
  final bool isResistance;

  const BandContribution({
    required this.tensionKg,
    this.count = 1,
    this.isResistance = true,
  });

  /// Average contribution over the range of motion. Band tension varies from
  /// ~0 (slack) to full tension (stretched), so the average is half the rated
  /// tension — positive for resistance, negative for assistance.
  double get averageKg => tensionKg * count * 0.5 * (isResistance ? 1 : -1);
}

/// Single source of truth for "how heavy was this set really" (V2 §5–§9).
/// Every engine — recovery, CNS, volume, 1RM, progression — must use this
/// instead of reading `weightKg` directly, so bands, chains, and bodyweight
/// count exactly once everywhere.
class EffectiveLoad {
  /// Effective load of one set in kg.
  ///
  /// [weightKg] is the logged external weight (added weight for weighted
  /// bodyweight movements). [bodyweightKg] is the snapshot stored on the set
  /// row; it is only included when [includesBodyweight] (i.e. the exercise
  /// has `supportsWeightedBodyweight` or is a bodyweight modality being
  /// counted by total load). [chainsKg] is the pre-averaged chain
  /// contribution stored on the set.
  static double computeKg({
    required double weightKg,
    double? bodyweightKg,
    bool includesBodyweight = false,
    double? chainsKg,
    List<BandContribution> bands = const [],
  }) {
    var load = weightKg;
    if (includesBodyweight && bodyweightKg != null) load += bodyweightKg;
    if (chainsKg != null) load += chainsKg;
    for (final b in bands) {
      load += b.averageKg;
    }
    // Heavy assistance can push the math below zero; clamp — a set never has
    // negative load.
    return load < 0 ? 0 : load;
  }

  /// Tonnage of one set: effective load × reps × the set type's volume factor.
  static double tonnageKg({
    required double effectiveKg,
    required int reps,
    SetType setType = SetType.standard,
  }) => effectiveKg * reps * setType.volumeFactor;
}
