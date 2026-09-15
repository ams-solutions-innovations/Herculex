part of '../smart_program_planner.dart';

/// Resolves which pooled exercise a given week's `RotationAssignments` row
/// should reference.
///
/// Non-`SlotRole.main` slots keep today's behavior unchanged: the pool is
/// simply indexed by the rotation epoch (`pool[epoch % pool.length]`), so a
/// supplemental/accessory/isolation slot may still legitimately vary its
/// exercise week to week per `RotationPolicy`.
///
/// `SlotRole.main` slots are anchored (D-09/D-10): once week 1 of a
/// generated block picks a specific exercise for a given `slotKey`, every
/// subsequent week in the same `_createStableSlots` call reuses that exact
/// `exerciseId` instead of rotating to a pattern-variety alternative — the
/// anchor is a specific exercise, not a movement pattern.
///
/// D-12 safety override: if the locked exercise is no longer present in the
/// current week's hard-filter-passing `pool` (e.g. a newly-discovered
/// injury/pain exclusion dropped it from the candidate list on this
/// generation run), the lock is broken — the safety hard filter wins. A
/// fresh `pool[epoch % pool.length]` pick is made and becomes the new lock
/// for any remaining weeks in this run, rather than silently keeping an
/// unsafe exercise.
ScoredExercise _resolveWeeklyAssignment({
  required SlotRole role,
  required int weekIndex,
  required int epoch,
  required List<ScoredExercise> pool,
  required Map<String, int> lockedAnchors,
  required String slotKey,
}) {
  if (role != SlotRole.main) {
    return pool[epoch % pool.length];
  }

  final lockedExerciseId = lockedAnchors[slotKey];
  if (lockedExerciseId != null) {
    for (final scored in pool) {
      if (scored.candidate.exerciseId == lockedExerciseId) {
        return scored;
      }
    }
    // D-12: the locked exercise is no longer a valid hard-filter candidate
    // this week — the lock is unsafe. Fall through to re-resolve and
    // overwrite the lock with the new, safe pick below.
  }

  final selected = pool[epoch % pool.length];
  lockedAnchors[slotKey] = selected.candidate.exerciseId;
  return selected;
}
