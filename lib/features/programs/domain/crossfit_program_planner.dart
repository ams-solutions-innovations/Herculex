/// Pure domain service that assembles a CrossFit training day's ordered
/// segment blueprint (D-01/D-02/D-03/D-04 of 21-CONTEXT.md).
///
/// This does not query the exercise catalog or the database — it returns
/// [CrossfitSlotNeed] descriptors tagged with [SessionSegment]. Candidate
/// exercise selection still runs through `smart_program_planner.dart`'s
/// existing `_createStableSlots` pipeline (equipment/style/experience/
/// prerequisites filtering), which already gates CrossFit movements once
/// Plan 21-03's metadata fixes land.
library;

import 'package:herculex/features/programs/domain/crossfit_scaling_policy.dart';
import 'package:herculex/features/programs/domain/programming_models.dart';
import 'package:herculex/features/programs/domain/session_segment.dart';
import 'package:herculex/features/programs/domain/slot_role.dart';
import 'package:herculex/features/workouts/domain/set_type.dart';

/// Builds the D-01/D-02/D-03/D-04 segment blueprint for one CrossFit
/// training day.
abstract final class CrossfitProgramPlanner {
  /// The 3 ROADMAP-named metcon formats, rotated deterministically by
  /// `variationSeed % 3` so a multi-week CrossFit program exercises all
  /// three rather than only ever producing AMRAP content.
  static const _metconFormats = [SetType.amrap, SetType.emom, SetType.forTime];

  /// Returns the ordered segment blueprint — warmup, skill, strength,
  /// metcon (1+ needs), cooldown — for one CrossFit day at [experience],
  /// rotating the metcon format deterministically via [variationSeed].
  static List<CrossfitSlotNeed> segmentNeedsFor({
    required ExperienceLevel experience,
    required int variationSeed,
  }) {
    // D-03/D-04: warmup and cooldown are lightweight structural
    // placeholders this phase — no 'warmup' discipline/content pool exists
    // in the Phase 16 catalog, and building one is content curation outside
    // this phase's architecture boundary.
    const warmup = CrossfitSlotNeed(
      role: SlotRole.accessory,
      segment: SessionSegment.warmup,
    );

    // Skill segment: candidate resolution for gymnastics/skill movements
    // happens downstream via the existing eligibility+prerequisite
    // pipeline — no pattern/muscle hint here to avoid over-constraining the
    // CrossFit-tagged pool.
    const skill = CrossfitSlotNeed(
      role: SlotRole.accessory,
      segment: SessionSegment.skill,
    );

    // D-02: strength is a separate segment before the metcon. Uses
    // SlotRole.supplemental (never .main) — one categorical step away from
    // max-effort/Dynamic-Effort eligibility (RESEARCH.md Pitfall 2).
    const strength = CrossfitSlotNeed(
      role: SlotRole.supplemental,
      segment: SessionSegment.strength,
    );

    final format = _metconFormats[variationSeed % _metconFormats.length];
    final movementCount = CrossfitScalingPolicy.movementCeilingFor(
      experience,
    );
    final capResult = CrossfitScalingPolicy.timeCapFor(
      format: format,
      level: experience,
    );
    final metconNeeds = List<CrossfitSlotNeed>.generate(
      movementCount,
      (_) => CrossfitSlotNeed(
        role: SlotRole.accessory,
        segment: SessionSegment.metcon,
        metconGroupKey: 'metcon-1',
        metconFormat: format,
        metconCapSeconds: capResult.capSeconds,
        metconMinutes: capResult.minutes,
      ),
    );

    const cooldown = CrossfitSlotNeed(
      role: SlotRole.accessory,
      segment: SessionSegment.cooldown,
    );

    return [warmup, skill, strength, ...metconNeeds, cooldown];
  }
}
