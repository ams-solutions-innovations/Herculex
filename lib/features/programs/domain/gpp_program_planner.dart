/// Pure domain service that formalizes the GPP conditioning day's content
/// into a segment-tagged, testable [CrossfitSlotNeed] blueprint.
///
/// This does not query the exercise catalog or the database. Candidate
/// exercise selection still runs through `smart_program_planner.dart`'s
/// existing `_createStableSlots` pipeline.
///
/// Two discretion items from 21-CONTEXT.md are resolved here, verbatim:
///
/// 1. **GPP day shape**: standalone 3rd training day, matching the
///    already-shipped `SplitType.fullBodyAbGpp` skeleton
///    (`['Full Body A', 'Full Body B', 'GPP']`, `defaultDaysPerWeek: 3`) and
///    `block_builder_view.dart`'s existing
///    `TrainingStyle.fullBody2xGpp -> SplitType.fullBodyAbGpp` wiring — not a
///    shorter addition appended to Full Body A/B.
/// 2. **GPP/Dynamic-Effort guard**: the existing `role.isHeavy`-gated
///    structural exclude in `smart_program_planner.dart`'s `_methodFor`
///    (only the two heaviest roles — see `slot_role.dart`'s `isHeavy`) is
///    the primary mechanism, already correct; this planner keeps that
///    guard closed by construction by never emitting either of those two
///    roles. `SlotRoleEligibility.derive`'s isTimed/cardio-only
///    conditioning gate is the secondary, already-sufficient content
///    restriction — no new disciplines-based filter is added here.
///
/// The 4-exercise `gpp`-tagged pool (burpee, rowing-erg, air-bike,
/// stationary-bike) ships as-is this phase per RESEARCH.md's own
/// recommendation — NOT widened to the 17-exercise `crossfit` pool (which
/// contains barbell/Olympic/gymnastics work, unsafe for a "no 8x3, no DE"
/// day). This thinness is a known, documented limitation for a future
/// content-curation follow-up, not silently expanded or silently ignored.
library;

import 'package:herculex/features/programs/domain/session_segment.dart';
import 'package:herculex/features/programs/domain/slot_role.dart';

/// Builds the segment-tagged need list for one GPP conditioning day.
abstract final class GppProgramPlanner {
  /// Returns exactly one conditioning-role, metcon-segment need — GPP
  /// content is one conventional cardio/carry slot, not an opaque
  /// high-fatigue WOD, and not a multi-segment CrossFit blueprint (no
  /// warmup/skill/strength/cooldown segments for GPP per this plan's
  /// narrow-scope decision).
  static List<CrossfitSlotNeed> segmentNeedsFor() => const [
    CrossfitSlotNeed(
      role: SlotRole.conditioning,
      segment: SessionSegment.metcon,
    ),
  ];
}
