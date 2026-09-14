/// A per-slot, per-week outcome of the deterministic planner's exercise
/// selection: either a filled slot (an exercise was chosen) or an empty
/// slot (no safe candidate qualified), always paired with a human-readable
/// [rationale] explaining why (Phase 17, D-01).
///
/// This is the pure domain contract later planner logic constructs and
/// `ProgramSlotExplanations` (see `lib/data/local/tables.dart`) persists —
/// it has no Drift/Flutter dependency of its own.
class SelectionExplanation {
  const SelectionExplanation.filled({
    required this.exerciseId,
    required this.rationale,
  }) : status = 'filled';

  const SelectionExplanation.empty({required this.rationale})
    : exerciseId = null,
      status = 'empty';

  final int? exerciseId;
  final String status;
  final String rationale;

  bool get isFilled => status == 'filled';
}
