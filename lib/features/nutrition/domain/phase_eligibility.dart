import 'dart:math' as math;

import 'package:herculex/features/nutrition/domain/diet_phase.dart';

/// Why a [PhaseEligibility] is narrower than "everything allowed".
enum PhaseRestrictionReason { under18, ageMissing, lowConfidence }

/// Which [DietPhase]s a member may be handed, and how hard a maingain surplus
/// may be pushed. Pure `DietPhase` terms so nutrition never imports physique.
class PhaseEligibility {
  const PhaseEligibility({
    required this.allowedPhases,
    this.maxMaingainDeltaKcal,
    this.reasons = const {},
  });

  /// All five phases, no cap, no reasons.
  const PhaseEligibility.unrestricted()
    : allowedPhases = const {
        DietPhase.maintain,
        DietPhase.maingain,
        DietPhase.cut,
        DietPhase.bulk,
        DietPhase.recomp,
      },
      maxMaingainDeltaKcal = null,
      reasons = const {};

  final Set<DietPhase> allowedPhases;
  final int? maxMaingainDeltaKcal;
  final Set<PhaseRestrictionReason> reasons;

  bool get isRestricted =>
      DietPhase.values.any((p) => !allowedPhases.contains(p)) ||
      maxMaingainDeltaKcal != null;

  bool allows(DietPhase phase) => allowedPhases.contains(phase);

  /// Clamps a calorie delta to what this eligibility permits.
  int clampDelta(DietPhase phase, int deltaKcal) {
    if (!allows(phase)) return 0;
    final cap = maxMaingainDeltaKcal;
    if (phase == DietPhase.maingain && cap != null) {
      return math.min(deltaKcal, cap);
    }
    return deltaKcal;
  }

  /// Nearest allowed phase to [requested]; an allowed phase is unchanged.
  DietPhase coerce(DietPhase requested) {
    if (allows(requested)) return requested;
    DietPhase safe() =>
        allows(DietPhase.recomp) ? DietPhase.recomp : DietPhase.maintain;
    if (requested == DietPhase.bulk && allows(DietPhase.maingain)) {
      return DietPhase.maingain;
    }
    return safe();
  }

  /// The stricter of two eligibilities.
  PhaseEligibility intersect(PhaseEligibility other) {
    final a = maxMaingainDeltaKcal;
    final b = other.maxMaingainDeltaKcal;
    return PhaseEligibility(
      allowedPhases: allowedPhases.intersection(other.allowedPhases),
      maxMaingainDeltaKcal: a == null ? b : (b == null ? a : math.min(a, b)),
      reasons: {...reasons, ...other.reasons},
    );
  }
}
