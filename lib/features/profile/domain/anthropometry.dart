import 'package:herculex/features/profile/domain/profile.dart';

enum TorsoProportion {
  short,
  average,
  long,
}

enum ArmProportion {
  short,
  average,
  long,
}

enum LegProportion {
  short,
  average,
  long,
}

class AnthropometryRatios {
  final Profile profile;

  const AnthropometryRatios(this.profile);

  bool get hasRequiredMeasurements =>
      profile.heightCm != null &&
      profile.inseamCm != null &&
      profile.armSpanCm != null &&
      profile.torsoCm != null;

  /// Ape Index (Wingspan to Height Ratio)
  /// Average is ~1.0
  double? get apeIndex {
    if (profile.armSpanCm == null || profile.heightCm == null || profile.heightCm == 0) return null;
    return profile.armSpanCm! / profile.heightCm!;
  }

  /// Leg length to height ratio (Inseam / Height)
  /// Average is ~0.45 to 0.47
  double? get legToHeightRatio {
    if (profile.inseamCm == null || profile.heightCm == null || profile.heightCm == 0) return null;
    return profile.inseamCm! / profile.heightCm!;
  }

  /// Torso to height ratio
  /// Average is ~0.33 to 0.35
  double? get torsoToHeightRatio {
    if (profile.torsoCm == null || profile.heightCm == null || profile.heightCm == 0) return null;
    return profile.torsoCm! / profile.heightCm!;
  }

  ArmProportion? get armProportion {
    final index = apeIndex;
    if (index == null) return null;
    if (index < 0.98) return ArmProportion.short;
    if (index > 1.02) return ArmProportion.long;
    return ArmProportion.average;
  }

  LegProportion? get legProportion {
    final ratio = legToHeightRatio;
    if (ratio == null) return null;
    if (ratio < 0.44) return LegProportion.short;
    if (ratio > 0.48) return LegProportion.long;
    return LegProportion.average;
  }

  TorsoProportion? get torsoProportion {
    final ratio = torsoToHeightRatio;
    if (ratio == null) return null;
    if (ratio < 0.32) return TorsoProportion.short;
    if (ratio > 0.36) return TorsoProportion.long;
    return TorsoProportion.average;
  }
}
