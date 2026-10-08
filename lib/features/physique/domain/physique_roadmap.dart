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
    this.fatLossKg,
    this.leanGainKg,
  });

  final double weightKg;
  final double currentBfPercent;
  final double targetBfPercent;

  /// Net scale change (lean gain minus fat loss). Steers the direction rule.
  final double plannedWeightChangeKg;
  final int estimatedMonths;
  final int? ageYears;
  final AssessmentConfidence confidence;
  final double? bfRangeMin;
  final double? bfRangeMax;
  final bool prefersWeightLoss;
  final int maintenanceKcal;

  /// Gross fat the analysis expects to lose. Sizes a cut; null falls back to
  /// the net change and then to the BF gap.
  final double? fatLossKg;

  /// Lean mass the analysis expects to gain. Decides whether the build phase
  /// after a cut must be a bulk rather than a maingain.
  final double? leanGainKg;
}

class PhysiqueRoadmapProposal {
  const PhysiqueRoadmapProposal({
    required this.phases,
    required this.eligibility,
    required this.requestedDirection,
    required this.wasCoerced,
    this.horizonWeeks = 0,
  });

  final List<RoadmapPhaseDraft> phases;
  final PhaseEligibility eligibility;

  /// What the direction rule asked for before eligibility; null when the data
  /// was unusable.
  final DietPhase? requestedDirection;
  final bool wasCoerced;

  /// Weeks the analysis asked the roadmap to cover.
  final int horizonWeeks;

  int get totalWeeks => phases.fold(0, (sum, p) => sum + p.plannedWeeks);

  /// True when the safe pace needs noticeably longer than the analysis said.
  bool get extendedBeyondEstimate => totalWeeks > horizonWeeks + 1;

  /// Where the last phase ends; null when no phase carries a weight.
  double? get finalWeightKg {
    for (final p in phases.reversed) {
      final kg = p.targetWeightKg;
      if (kg != null) return kg;
    }
    return null;
  }
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

  /// [ASSUMED] Lean gain above this multiple of what maingain can deliver in
  /// the time left switches the build phase to a bulk.
  static const _bulkOverMaingainRatio = 1.25;

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
        phases: [
          RoadmapPhaseDraft(
            phase: DietPhase.maintain,
            plannedWeeks: _maintainOnlyWeeks,
            targetWeightKg: input.weightKg > 0 ? _round1(input.weightKg) : null,
            weeklyRateKg: 0,
          ),
        ],
        eligibility: eligibility,
        requestedDirection: null,
        wasCoerced: false,
        horizonWeeks: _maintainOnlyWeeks,
      );
    }

    final first = eligibility.coerce(decision.phase);
    final horizon = math.max(
      4,
      (input.estimatedMonths * PhysiqueTuning.weeksPerMonth).round(),
    );
    final firstDraft = _firstPhase(first, input, eligibility, horizon);
    final phases = <RoadmapPhaseDraft>[firstDraft];
    _coverHorizon(phases, first, input, eligibility, horizon);

    return PhysiqueRoadmapProposal(
      phases: List.unmodifiable(phases),
      eligibility: eligibility,
      requestedDirection: decision.phase,
      wasCoerced: first != decision.phase,
      horizonWeeks: horizon,
    );
  }

  static int _weeksOf(List<RoadmapPhaseDraft> phases) =>
      phases.fold(0, (sum, p) => sum + p.plannedWeeks);

  /// Appends follow-on phases until the roadmap spans [horizon] weeks.
  ///
  /// A cut or bulk is followed by a short maintain, then by a build phase
  /// (maingain, or a bulk when the lean gain is too big for maingain pace)
  /// for the rest of the time. Leftovers under a build phase become a
  /// closing maintain. The pace is never raised to fit: a goal that needs
  /// longer than the analysis said simply makes the roadmap longer.
  static void _coverHorizon(
    List<RoadmapPhaseDraft> phases,
    DietPhase first,
    PhysiqueRoadmapInput input,
    PhaseEligibility eligibility,
    int horizon,
  ) {
    final firstDraft = phases.first;
    if (first == DietPhase.maintain) return;

    if (first == DietPhase.cut || first == DietPhase.bulk) {
      final threshold = first == DietPhase.cut
          ? _cutFollowOnThresholdWeeks
          : _bulkFollowOnThresholdWeeks;
      final roomForBuild =
          horizon - firstDraft.plannedWeeks - _maintainFollowOnWeeks >=
          _holdPhaseMinWeeks;
      if (firstDraft.plannedWeeks >= threshold || roomForBuild) {
        phases.add(_maintainAfter(firstDraft, input.weightKg));
      }
    }

    var guard = 0;
    var remaining = horizon - _weeksOf(phases);
    while (remaining >= PhysiqueTuning.minPhaseWeeks && guard++ < 3) {
      final start = phases.last.targetWeightKg ?? _round1(input.weightKg);
      final RoadmapPhaseDraft next;
      if (remaining >= _holdPhaseMinWeeks) {
        next = _buildPhase(start, remaining, first, input, eligibility);
      } else if (phases.last.phase != DietPhase.maintain) {
        next = _holdAt(start, remaining);
      } else {
        // Too little left for a phase of its own, and a maintain is already
        // last: two in a row would only be noise.
        break;
      }
      phases.add(next);
      remaining -= next.plannedWeeks;
    }
  }

  static RoadmapPhaseDraft _holdAt(double weightKg, int weeks) =>
      RoadmapPhaseDraft(
        phase: DietPhase.maintain,
        plannedWeeks: _weeks(weeks),
        targetWeightKg: weightKg,
        weeklyRateKg: 0,
      );

  /// The phase that adds muscle after the first one. Maingain by default; a
  /// bulk when the expected lean gain is well above what maingain can deliver
  /// in the time left. Falls back to a maintain hold when maingain is not
  /// allowed.
  static RoadmapPhaseDraft _buildPhase(
    double startWeight,
    int remainingWeeks,
    DietPhase first,
    PhysiqueRoadmapInput input,
    PhaseEligibility eligibility,
  ) {
    final lean = input.leanGainKg;
    if (first == DietPhase.cut &&
        lean != null &&
        lean > 0 &&
        eligibility.allows(DietPhase.bulk)) {
      final maingainWeekly = PhysiqueTempoPolicy.weeklyKg(
        phase: DietPhase.maingain,
        bodyweightKg: startWeight,
        maintenanceKcal: input.maintenanceKcal,
        maxDeltaKcalCap: eligibility.maxMaingainDeltaKcal,
      );
      if (lean > maingainWeekly * remainingWeeks * _bulkOverMaingainRatio) {
        return _paced(DietPhase.bulk, startWeight, lean, input);
      }
    }
    if (eligibility.allows(DietPhase.maingain)) {
      return _maingain(
        startWeight,
        _holdWeeks(remainingWeeks),
        input,
        eligibility,
      );
    }
    return _holdAt(startWeight, _holdWeeks(remainingWeeks));
  }

  /// A cut or bulk that moves [deltaKg] at the safe pace. The recorded rate is
  /// slower than the preset when [deltaKg] does not fill a whole number of
  /// weeks, so the target lands on [deltaKg] and re-targeting leaves it alone.
  static RoadmapPhaseDraft _paced(
    DietPhase phase,
    double startWeight,
    double deltaKg,
    PhysiqueRoadmapInput input, {
    double? targetBf,
  }) {
    final isCut = phase == DietPhase.cut;
    final weekly = PhysiqueTempoPolicy.weeklyKg(
      phase: phase,
      bodyweightKg: startWeight,
      maintenanceKcal: input.maintenanceKcal,
    );
    final weeks = _weeks(
      PhysiqueTempoPolicy.plannedWeeks(deltaKg: deltaKg, weeklyKg: weekly),
    );
    final moved = math.min(deltaKg, weekly * weeks);
    final fullPace = moved >= weekly * weeks - 1e-9;
    return RoadmapPhaseDraft(
      phase: phase,
      plannedWeeks: weeks,
      targetWeightKg: _round1(
        isCut ? startWeight - moved : startWeight + moved,
      ),
      targetBfPercent: isCut ? targetBf : null,
      weeklyRateKg: fullPace ? weekly : moved / weeks,
      tempoCapped: PhysiqueTempoPolicy.isCapped(
        phase: phase,
        bodyweightKg: startWeight,
        maintenanceKcal: input.maintenanceKcal,
      ),
    );
  }

  static RoadmapPhaseDraft _maintainAfter(
    RoadmapPhaseDraft previous,
    double fallbackWeight,
  ) => RoadmapPhaseDraft(
    phase: DietPhase.maintain,
    plannedWeeks: _maintainFollowOnWeeks,
    targetWeightKg: previous.targetWeightKg ?? _round1(fallbackWeight),
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
        final fat = input.fatLossKg;
        final deltaKg = isCut
            ? (fat != null && fat > 0
                  ? fat
                  : change < 0
                  ? -change
                  : math.max(
                      0.0,
                      w *
                          (input.currentBfPercent - input.targetBfPercent) /
                          100,
                    ))
            : (change > 0 ? change : w * _defaultBulkShare);
        return _paced(
          phase,
          w,
          deltaKg,
          input,
          targetBf: input.targetBfPercent,
        );
      case DietPhase.maingain:
        return _maingain(w, _holdWeeks(horizon), input, eligibility);
      case DietPhase.recomp:
        return RoadmapPhaseDraft(
          phase: DietPhase.recomp,
          plannedWeeks: _holdWeeks(horizon),
          targetWeightKg: _round1(w),
          targetBfPercent: input.targetBfPercent,
          weeklyRateKg: 0,
        );
      case DietPhase.maintain:
        return RoadmapPhaseDraft(
          phase: DietPhase.maintain,
          plannedWeeks: _maintainOnlyWeeks,
          targetWeightKg: _round1(w),
          weeklyRateKg: 0,
        );
    }
  }
}
