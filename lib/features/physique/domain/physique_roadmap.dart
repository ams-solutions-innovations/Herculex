import 'dart:math' as math;

import 'package:herculex/features/nutrition/domain/diet_phase.dart';
import 'package:herculex/features/nutrition/domain/phase_eligibility.dart';
import 'package:herculex/features/physique/domain/physique_direction.dart';
import 'package:herculex/features/physique/domain/physique_guardrails.dart';
import 'package:herculex/features/physique/domain/physique_tempo_policy.dart';
import 'package:herculex/features/physique/domain/physique_tuning.dart';

/// One editable phase in a proposed roadmap.
class RoadmapPhaseDraft {
  const RoadmapPhaseDraft({
    required this.phase,
    required this.plannedWeeks,
    this.targetWeightKg,
    this.targetBfPercent,
    this.weeklyRateKg,
    this.tempoCapped = false,
  });

  final DietPhase phase;
  final int plannedWeeks;
  final double? targetWeightKg;
  final double? targetBfPercent;
  final double? weeklyRateKg;
  final bool tempoCapped;

  RoadmapPhaseDraft copyWith({
    DietPhase? phase,
    int? plannedWeeks,
    double? targetWeightKg,
    double? targetBfPercent,
    double? weeklyRateKg,
    bool? tempoCapped,
  }) => RoadmapPhaseDraft(
    phase: phase ?? this.phase,
    plannedWeeks: plannedWeeks ?? this.plannedWeeks,
    targetWeightKg: targetWeightKg ?? this.targetWeightKg,
    targetBfPercent: targetBfPercent ?? this.targetBfPercent,
    weeklyRateKg: weeklyRateKg ?? this.weeklyRateKg,
    tempoCapped: tempoCapped ?? this.tempoCapped,
  );

  @override
  bool operator ==(Object other) =>
      other is RoadmapPhaseDraft &&
      other.phase == phase &&
      other.plannedWeeks == plannedWeeks &&
      other.targetWeightKg == targetWeightKg &&
      other.targetBfPercent == targetBfPercent &&
      other.weeklyRateKg == weeklyRateKg &&
      other.tempoCapped == tempoCapped;

  @override
  int get hashCode => Object.hash(
    phase,
    plannedWeeks,
    targetWeightKg,
    targetBfPercent,
    weeklyRateKg,
    tempoCapped,
  );

  @override
  String toString() =>
      'RoadmapPhaseDraft($phase, ${plannedWeeks}w, kg: $targetWeightKg, '
      'bf: $targetBfPercent, rate: $weeklyRateKg, capped: $tempoCapped)';
}

/// Plain inputs for the generator; no data-layer types.
class PhysiqueRoadmapInput {
  const PhysiqueRoadmapInput({
    required this.weightKg,
    required this.currentBfPercent,
    required this.targetBfPercent,
    required this.plannedWeightChangeKg,
    required this.estimatedMonths,
    this.ageYears,
    this.confidence = AssessmentConfidence.unknown,
    this.bfRangeMin,
    this.bfRangeMax,
    this.prefersWeightLoss = false,
    this.maintenanceKcal = PhysiqueTuning.defaultMaintenanceKcal,
  });

  final double weightKg;
  final double currentBfPercent;
  final double targetBfPercent;
  final double plannedWeightChangeKg;
  final int estimatedMonths;
  final int? ageYears;
  final AssessmentConfidence confidence;
  final double? bfRangeMin;
  final double? bfRangeMax;
  final bool prefersWeightLoss;
  final int maintenanceKcal;
}

class PhysiqueRoadmapProposal {
  const PhysiqueRoadmapProposal({
    required this.phases,
    required this.eligibility,
    required this.requestedDirection,
    required this.wasCoerced,
  });

  final List<RoadmapPhaseDraft> phases;
  final PhaseEligibility eligibility;

  /// What the direction rule asked for before eligibility; null when the data
  /// was unusable.
  final DietPhase? requestedDirection;
  final bool wasCoerced;
}

/// Deterministic multi-phase roadmap proposal (D-01). The user edits the
/// result with `RoadmapDraftEditor`.
abstract final class PhysiqueRoadmapGenerator {
  static const _maintainFollowOnWeeks = 2;
  static const _maintainOnlyWeeks = 4;
  static const _holdPhaseMinWeeks = 8;
  static const _cutFollowOnThresholdWeeks = 12;
  static const _bulkFollowOnThresholdWeeks = 16;
  static const _defaultBulkShare = 0.05;

  static double _round1(double v) => (v * 10).round() / 10;

  static int _weeks(int v) => math.min(
    PhysiqueTuning.maxPhaseWeeks,
    math.max(PhysiqueTuning.minPhaseWeeks, v),
  );

  static int _holdWeeks(int v) =>
      math.min(PhysiqueTuning.maxPhaseWeeks, math.max(_holdPhaseMinWeeks, v));

  static PhysiqueRoadmapProposal propose(PhysiqueRoadmapInput input) {
    final eligibility = PhysiqueGuardrails.evaluate(
      ageYears: input.ageYears,
      confidence: input.confidence,
      bfRangeMin: input.bfRangeMin,
      bfRangeMax: input.bfRangeMax,
    );
    final decision = PhysiqueDirectionRule.decide(
      weightKg: input.weightKg,
      currentBfPercent: input.currentBfPercent,
      targetBfPercent: input.targetBfPercent,
      plannedWeightChangeKg: input.plannedWeightChangeKg,
      prefersWeightLoss: input.prefersWeightLoss,
    );
    if (decision == null) {
      return PhysiqueRoadmapProposal(
        phases: const [
          RoadmapPhaseDraft(
            phase: DietPhase.maintain,
            plannedWeeks: _maintainOnlyWeeks,
            weeklyRateKg: 0,
          ),
        ],
        eligibility: eligibility,
        requestedDirection: null,
        wasCoerced: false,
      );
    }

    final first = eligibility.coerce(decision.phase);
    final horizon = math.max(
      4,
      (input.estimatedMonths * PhysiqueTuning.weeksPerMonth).round(),
    );
    final firstDraft = _firstPhase(first, input, eligibility, horizon);
    final phases = <RoadmapPhaseDraft>[firstDraft];

    if (first == DietPhase.cut &&
        firstDraft.plannedWeeks >= _cutFollowOnThresholdWeeks) {
      phases.add(_maintainAfter(firstDraft, input.weightKg));
      final remaining =
          horizon - firstDraft.plannedWeeks - _maintainFollowOnWeeks;
      if (remaining >= _holdPhaseMinWeeks &&
          eligibility.allows(DietPhase.maingain)) {
        final start = firstDraft.targetWeightKg ?? input.weightKg;
        final weeks = _holdWeeks(remaining);
        phases.add(_maingain(start, weeks, input, eligibility));
      }
    } else if (first == DietPhase.bulk &&
        firstDraft.plannedWeeks >= _bulkFollowOnThresholdWeeks) {
      phases.add(_maintainAfter(firstDraft, input.weightKg));
    }

    return PhysiqueRoadmapProposal(
      phases: List.unmodifiable(phases),
      eligibility: eligibility,
      requestedDirection: decision.phase,
      wasCoerced: first != decision.phase,
    );
  }

  static RoadmapPhaseDraft _maintainAfter(
    RoadmapPhaseDraft previous,
    double fallbackWeight,
  ) => RoadmapPhaseDraft(
    phase: DietPhase.maintain,
    plannedWeeks: _maintainFollowOnWeeks,
    targetWeightKg: previous.targetWeightKg ?? fallbackWeight,
    weeklyRateKg: 0,
  );

  static RoadmapPhaseDraft _maingain(
    double startWeight,
    int weeks,
    PhysiqueRoadmapInput input,
    PhaseEligibility eligibility,
  ) {
    final cap = eligibility.maxMaingainDeltaKcal;
    final weekly = PhysiqueTempoPolicy.weeklyKg(
      phase: DietPhase.maingain,
      bodyweightKg: startWeight,
      maintenanceKcal: input.maintenanceKcal,
      maxDeltaKcalCap: cap,
    );
    return RoadmapPhaseDraft(
      phase: DietPhase.maingain,
      plannedWeeks: weeks,
      targetWeightKg: _round1(startWeight + weekly * weeks),
      weeklyRateKg: weekly,
      tempoCapped: PhysiqueTempoPolicy.isCapped(
        phase: DietPhase.maingain,
        bodyweightKg: startWeight,
        maintenanceKcal: input.maintenanceKcal,
        maxDeltaKcalCap: cap,
      ),
    );
  }

  static RoadmapPhaseDraft _firstPhase(
    DietPhase phase,
    PhysiqueRoadmapInput input,
    PhaseEligibility eligibility,
    int horizon,
  ) {
    final w = input.weightKg;
    switch (phase) {
      case DietPhase.cut:
      case DietPhase.bulk:
        final isCut = phase == DietPhase.cut;
        final change = input.plannedWeightChangeKg;
        final deltaKg = isCut
            ? (change < 0
                  ? -change
                  : math.max(
                      0.0,
                      w *
                          (input.currentBfPercent - input.targetBfPercent) /
                          100,
                    ))
            : (change > 0 ? change : w * _defaultBulkShare);
        final weekly = PhysiqueTempoPolicy.weeklyKg(
          phase: phase,
          bodyweightKg: w,
          maintenanceKcal: input.maintenanceKcal,
        );
        final weeks = _weeks(
          PhysiqueTempoPolicy.plannedWeeks(deltaKg: deltaKg, weeklyKg: weekly),
        );
        final moved = math.min(deltaKg, weekly * weeks);
        return RoadmapPhaseDraft(
          phase: phase,
          plannedWeeks: weeks,
          targetWeightKg: _round1(isCut ? w - moved : w + moved),
          targetBfPercent: isCut ? input.targetBfPercent : null,
          weeklyRateKg: weekly,
          tempoCapped: PhysiqueTempoPolicy.isCapped(
            phase: phase,
            bodyweightKg: w,
            maintenanceKcal: input.maintenanceKcal,
          ),
        );
      case DietPhase.maingain:
        return _maingain(w, _holdWeeks(horizon), input, eligibility);
      case DietPhase.recomp:
        return RoadmapPhaseDraft(
          phase: DietPhase.recomp,
          plannedWeeks: _holdWeeks(horizon),
          targetBfPercent: input.targetBfPercent,
          weeklyRateKg: 0,
        );
      case DietPhase.maintain:
        return const RoadmapPhaseDraft(
          phase: DietPhase.maintain,
          plannedWeeks: _maintainOnlyWeeks,
          weeklyRateKg: 0,
        );
    }
  }
}
