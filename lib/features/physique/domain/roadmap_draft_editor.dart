import 'dart:math' as math;

import 'package:herculex/features/nutrition/domain/diet_phase.dart';
import 'package:herculex/features/nutrition/domain/phase_eligibility.dart';
import 'package:herculex/features/physique/domain/physique_roadmap.dart';
import 'package:herculex/features/physique/domain/physique_tempo_policy.dart';
import 'package:herculex/features/physique/domain/physique_tuning.dart';

/// Pure edit operations over a roadmap draft. Every function returns a new
/// list and never mutates its input. Persistence assigns order indices.
abstract final class RoadmapDraftEditor {
  static const _defaultAddedWeeks = 8;

  static int _clampWeeks(int weeks) => math.min(
    PhysiqueTuning.maxPhaseWeeks,
    math.max(PhysiqueTuning.minPhaseWeeks, weeks),
  );

  /// [ReorderableListView] semantics: moving down passes `newIndex` one too
  /// high, so it is decremented.
  static List<RoadmapPhaseDraft> reorder(
    List<RoadmapPhaseDraft> drafts,
    int oldIndex,
    int newIndex,
  ) {
    final out = [...drafts];
    if (oldIndex < 0 || oldIndex >= out.length) return out;
    var target = newIndex;
    if (target > oldIndex) target -= 1;
    target = math.max(0, math.min(out.length - 1, target));
    final item = out.removeAt(oldIndex);
    out.insert(target, item);
    return out;
  }

  static List<RoadmapPhaseDraft> resize(
    List<RoadmapPhaseDraft> drafts,
    int index,
    int weeks,
  ) {
    final out = [...drafts];
    if (index < 0 || index >= out.length) return out;
    out[index] = out[index].copyWith(plannedWeeks: _clampWeeks(weeks));
    return out;
  }

  /// The last remaining phase cannot be removed.
  static List<RoadmapPhaseDraft> remove(
    List<RoadmapPhaseDraft> drafts,
    int index,
  ) {
    final out = [...drafts];
    if (out.length <= 1 || index < 0 || index >= out.length) return out;
    out.removeAt(index);
    return out;
  }

  static bool canAdd(PhaseEligibility eligibility, DietPhase phase) =>
      eligibility.allows(phase);

  static List<RoadmapPhaseDraft> add(
    List<RoadmapPhaseDraft> drafts,
    DietPhase phase,
    PhaseEligibility eligibility, {
    int weeks = _defaultAddedWeeks,
  }) {
    final out = [...drafts];
    if (!canAdd(eligibility, phase)) return out;
    out.add(RoadmapPhaseDraft(phase: phase, plannedWeeks: _clampWeeks(weeks)));
    return out;
  }

  /// Recomputes pace, cap flag and chained target weight for every phase.
  /// Cut subtracts, bulk and maingain add, others carry the weight forward.
  /// The BF target is kept only on cut and recomp.
  static List<RoadmapPhaseDraft> retarget(
    List<RoadmapPhaseDraft> drafts, {
    required double startWeightKg,
    required double? goalTargetBfPercent,
    required int maintenanceKcal,
    required PhaseEligibility eligibility,
  }) {
    var weight = startWeightKg;
    final out = <RoadmapPhaseDraft>[];
    for (final d in drafts) {
      final cap = d.phase == DietPhase.maingain
          ? eligibility.maxMaingainDeltaKcal
          : null;
      final weekly = PhysiqueTempoPolicy.weeklyKg(
        phase: d.phase,
        bodyweightKg: weight,
        maintenanceKcal: maintenanceKcal,
        maxDeltaKcalCap: cap,
      );
      final capped = PhysiqueTempoPolicy.isCapped(
        phase: d.phase,
        bodyweightKg: weight,
        maintenanceKcal: maintenanceKcal,
        maxDeltaKcalCap: cap,
      );
      final moved = weekly * d.plannedWeeks;
      final next = switch (d.phase) {
        DietPhase.cut => weight - moved,
        DietPhase.bulk || DietPhase.maingain => weight + moved,
        DietPhase.maintain || DietPhase.recomp => weight,
      };
      final rounded = (next * 10).round() / 10;
      final hasBf = d.phase == DietPhase.cut || d.phase == DietPhase.recomp;
      out.add(
        RoadmapPhaseDraft(
          phase: d.phase,
          plannedWeeks: d.plannedWeeks,
          targetWeightKg: rounded,
          targetBfPercent: hasBf ? goalTargetBfPercent : null,
          weeklyRateKg: weekly,
          tempoCapped: capped,
        ),
      );
      weight = rounded;
    }
    return out;
  }
}
