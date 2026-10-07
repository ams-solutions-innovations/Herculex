import 'package:herculex/features/nutrition/domain/diet_phase.dart';
import 'package:herculex/features/nutrition/domain/phase_eligibility.dart';
import 'package:herculex/features/physique/domain/physique_tuning.dart';

/// How much the visual body-fat assessment can be trusted.
enum AssessmentConfidence {
  low,
  medium,
  high,
  unknown;

  String get wireValue => name;

  static AssessmentConfidence fromWire(Object? value) {
    for (final c in AssessmentConfidence.values) {
      if (c != AssessmentConfidence.unknown && c.name == value) return c;
    }
    return AssessmentConfidence.unknown;
  }
}

/// Eligibility rules for aggressive phases (D-05, D-06). Lives in the domain so
/// no widget can bypass it.
abstract final class PhysiqueGuardrails {
  static const _safePhases = {
    DietPhase.maintain,
    DietPhase.recomp,
    DietPhase.maingain,
  };

  /// Under 18 or unknown age: no cut or bulk, maingain capped (D-05).
  static PhaseEligibility ageEligibility(int? ageYears) {
    if (ageYears != null && ageYears >= PhysiqueTuning.adultAgeYears) {
      return const PhaseEligibility.unrestricted();
    }
    return PhaseEligibility(
      allowedPhases: _safePhases,
      maxMaingainDeltaKcal: PhysiqueTuning.minorMaingainCapKcal,
      reasons: {
        ageYears == null
            ? PhaseRestrictionReason.ageMissing
            : PhaseRestrictionReason.under18,
      },
    );
  }

  static bool isLowConfidence({
    AssessmentConfidence confidence = AssessmentConfidence.unknown,
    double? bfRangeMin,
    double? bfRangeMax,
  }) {
    if (confidence == AssessmentConfidence.low) return true;
    if (confidence == AssessmentConfidence.unknown &&
        PhysiqueTuning.unknownConfidenceRestricts) {
      return true;
    }
    if (bfRangeMin != null && bfRangeMax != null) {
      return bfRangeMax - bfRangeMin > PhysiqueTuning.maxBfBandWidthPct;
    }
    return false;
  }

  static PhaseEligibility confidenceEligibility({
    AssessmentConfidence confidence = AssessmentConfidence.unknown,
    double? bfRangeMin,
    double? bfRangeMax,
  }) {
    if (!isLowConfidence(
      confidence: confidence,
      bfRangeMin: bfRangeMin,
      bfRangeMax: bfRangeMax,
    )) {
      return const PhaseEligibility.unrestricted();
    }
    return const PhaseEligibility(
      allowedPhases: {DietPhase.maintain, DietPhase.recomp},
      reasons: {PhaseRestrictionReason.lowConfidence},
    );
  }

  static PhaseEligibility evaluate({
    int? ageYears,
    AssessmentConfidence confidence = AssessmentConfidence.unknown,
    double? bfRangeMin,
    double? bfRangeMax,
  }) => ageEligibility(ageYears).intersect(
    confidenceEligibility(
      confidence: confidence,
      bfRangeMin: bfRangeMin,
      bfRangeMax: bfRangeMax,
    ),
  );
}
