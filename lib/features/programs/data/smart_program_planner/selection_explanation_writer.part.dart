part of '../smart_program_planner.dart';

/// Persists a `ProgramSlotExplanations` row for every week of a resolved
/// slot (Phase 17, PLAN-04) — whether that slot was filled with a real
/// exercise or left genuinely empty after every hard filter (and the D-03
/// scaling-ladder regression) was exhausted.
///
/// The empty case ([emptyExplanation] non-null) writes the SAME rationale
/// for every week, since `_resolveEmptyCandidatePool`'s decision is made
/// once per slot before any week-specific resolution happens — the slot is
/// empty for the whole generation run, not just some weeks.
///
/// The filled case (default) looks up each week's already-persisted
/// `RotationAssignmentData` (populated by the anchor-lock-aware week loop in
/// `_createStableSlots`) and reuses its `reason` string verbatim as the
/// `rationale` — this is the same per-week selection rationale already
/// written to `RotationAssignments.reason`, not a second, newly invented
/// string for the same fact.
Future<void> _writeSlotExplanations({
  required AppDatabase db,
  required int slotId,
  required List<ProgramWeekData> weeks,
  required Map<int, RotationAssignmentData> assignments,
  SelectionExplanation? emptyExplanation,
}) async {
  for (final week in weeks) {
    if (emptyExplanation != null) {
      await db
          .into(db.programSlotExplanations)
          .insert(
            ProgramSlotExplanationsCompanion.insert(
              slotId: slotId,
              weekIndex: week.weekIndex,
              chosenExerciseId: const Value(null),
              status: 'empty',
              rationale: emptyExplanation.rationale,
            ),
          );
      continue;
    }
    final assignment = assignments[week.weekIndex]!;
    await db
        .into(db.programSlotExplanations)
        .insert(
          ProgramSlotExplanationsCompanion.insert(
            slotId: slotId,
            weekIndex: week.weekIndex,
            chosenExerciseId: Value(assignment.exerciseId),
            status: 'filled',
            rationale: assignment.reason,
          ),
        );
  }
}
