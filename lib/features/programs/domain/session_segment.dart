/// Session-level segment tag (warmup/skill/strength/metcon/cooldown) for a
/// CrossFit/GPP training day.
///
/// This is distinct from `WorkSegment` in `slot_prescription.dart`, which is
/// a per-slot set-group concept — do not conflate the two names or classes.
library;

import 'package:collection/collection.dart';
import 'package:herculex/features/programs/domain/slot_role.dart';
import 'package:herculex/features/workouts/domain/set_type.dart';

/// The part of a CrossFit/GPP session a row belongs to. Mirrors the
/// enum-with-.id-string convention of [SetType] and [SlotRole], but unlike
/// [SlotRole.fromId], `null` is a real and common state here — most rows
/// (any non-CrossFit/GPP program) simply have no session segment — so
/// [fromId] returns `null` rather than falling back to a default value.
enum SessionSegment {
  warmup('warmup'),
  skill('skill'),
  strength('strength'),
  metcon('metcon'),
  cooldown('cooldown');

  const SessionSegment(this.id);

  final String id;

  static SessionSegment? fromId(String? id) =>
      id == null ? null : values.firstWhereOrNull((s) => s.id == id);
}

/// Shared public descriptor type returned by both `crossfit_program_planner`
/// and `gpp_program_planner` (Wave 2). Lives here — rather than in either
/// planner file — so those two plans stay file-independent and can be built
/// in parallel.
///
/// Field shape mirrors `smart_program_planner.dart`'s private `_SlotNeed`
/// (pattern/muscle/role/preferredSlugs), extended with the segment tag and
/// metcon-only fields. This type is intentionally kept separate from
/// `_SlotNeed` — a later plan maps one to the other at the `_needsFor`
/// dispatch boundary, keeping `crossfit_program_planner.dart` and
/// `gpp_program_planner.dart` free of any dependency on
/// `smart_program_planner.dart`'s private types.
class CrossfitSlotNeed {
  const CrossfitSlotNeed({
    this.pattern,
    this.muscle,
    required this.role,
    this.preferredSlugs = const {},
    required this.segment,
    this.metconGroupKey,
    this.metconFormat,
    this.metconCapSeconds,
    this.metconMinutes,
  });

  final String? pattern;
  final String? muscle;
  final SlotRole role;
  final Set<String> preferredSlugs;
  final SessionSegment segment;
  final String? metconGroupKey;
  final SetType? metconFormat;
  final int? metconCapSeconds;
  final int? metconMinutes;
}
