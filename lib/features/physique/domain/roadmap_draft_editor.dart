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
    // Carry the previous end weight so the new phase never shows "no target"
    // before the next retarget fills in the real one.
    out.add(
      RoadmapPhaseDraft(
        phase: phase,
        plannedWeeks: _clampWeeks(weeks),
        targetWeightKg: out.isEmpty ? null : out.last.targetWeightKg,
      ),
    );
    return out;
  }

  static double _round1(double v) => (v * 10).round() / 10;

  /// Recomputes pace, cap flag and chained target weight for every phase.
  /// Cut subtracts, bulk and maingain add, others carry the weight forward.
  /// The BF target is kept only on cut and recomp.
  ///
  /// A phase keeps its recorded pace when that is slower than the safe pace,
  /// so a generated or pinned end weight survives a re-save. The pace never
  /// goes above the safe pace.
  ///
  /// [firstPhaseElapsedWeeks] is how much of the first draft is already behind
  /// the member: the first phase then only moves for the weeks that are left,
  /// starting from [startWeightKg] (today's weight).
  static List<RoadmapPhaseDraft> retarget(
    List<RoadmapPhaseDraft> drafts, {
    required double startWeightKg,
    required double? goalTargetBfPercent,
    required int maintenanceKcal,
    required PhaseEligibility eligibility,
    int firstPhaseElapsedWeeks = 0,
  }) {
    var weight = startWeightKg;
    final out = <RoadmapPhaseDraft>[];
    for (var i = 0; i < drafts.length; i++) {
      final d = drafts[i];
      final cap = d.phase == DietPhase.maingain
          ? eligibility.maxMaingainDeltaKcal
          : null;
      final safe = PhysiqueTempoPolicy.weeklyKg(
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
      final stored = d.weeklyRateKg;
      final weekly = (stored != null && stored >= 0 && stored < safe - 1e-9)
          ? stored
          : safe;
      final weeksAhead = i == 0
          ? math.max(0, d.plannedWeeks - firstPhaseElapsedWeeks)
          : d.plannedWeeks;
      final moved = weekly * weeksAhead;
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

  /// Makes phase [index] end at [endWeightKg], moving from [fromWeightKg] at
  /// no more than the safe pace, and re-chains every later phase from there.
  /// Phases before [index] are left alone.
  ///
  /// Returns null when the end weight cannot be expressed without changing the
  /// phase itself: a hold phase, a weight on the wrong side of
  /// [fromWeightKg] for the phase direction, or a move that needs longer than
  /// one phase can last at the safe pace.
  ///
  /// [elapsedWeeks] (first phase only) is time already spent in the phase; the
  /// planned length covers it plus the weeks still needed.
  static List<RoadmapPhaseDraft>? pinPhaseEnd(
    List<RoadmapPhaseDraft> drafts,
    int index, {
    required double fromWeightKg,
    required double endWeightKg,
    required double? goalTargetBfPercent,
    required int maintenanceKcal,
    required PhaseEligibility eligibility,
    int elapsedWeeks = 0,
  }) {
    if (index < 0 || index >= drafts.length) return null;
    final d = drafts[index];
    final delta = endWeightKg - fromWeightKg;
    final rightSide = switch (d.phase) {
      DietPhase.cut => delta < 0,
      DietPhase.bulk || DietPhase.maingain => delta > 0,
      DietPhase.maintain || DietPhase.recomp => false,
    };
    if (!rightSide) return null;

    final safe = PhysiqueTempoPolicy.weeklyKg(
      phase: d.phase,
      bodyweightKg: fromWeightKg,
      maintenanceKcal: maintenanceKcal,
      maxDeltaKcalCap: d.phase == DietPhase.maingain
          ? eligibility.maxMaingainDeltaKcal
          : null,
    );
    if (safe <= 0) return null;
    final remaining = math.max(
      PhysiqueTuning.minPhaseWeeks,
      PhysiqueTempoPolicy.plannedWeeks(deltaKg: delta, weeklyKg: safe),
    );
    if (remaining > PhysiqueTuning.maxPhaseWeeks) return null;

    final end = _round1(endWeightKg);
    final pinned = d.copyWith(
      plannedWeeks: _clampWeeks((index == 0 ? elapsedWeeks : 0) + remaining),
      targetWeightKg: end,
      weeklyRateKg: delta.abs() / remaining,
    );
    final tail = retarget(
      drafts.sublist(index + 1),
      startWeightKg: end,
      goalTargetBfPercent: goalTargetBfPercent,
      maintenanceKcal: maintenanceKcal,
      eligibility: eligibility,
    );
    return [...drafts.sublist(0, index), pinned, ...tail];
  }
}
