import 'package:drift/drift.dart';

import '../../../data/local/database.dart';

/// A slot in the shared Gym Buddy choreography mapping a stable remote [slotId]
/// to either a local [workoutExerciseId] or an unresolved placeholder.
class BuddySlot {
  BuddySlot({
    required this.buddySessionId,
    required this.slotId,
    this.workoutExerciseId,
    this.unresolvedUuid,
    this.unresolvedSlug,
    this.placeholderLabel,
    required this.orderIndex,
  }) : assert(
         (workoutExerciseId != null) ^
             (unresolvedUuid != null || unresolvedSlug != null),
         'BuddySlot must be either materialised or a placeholder (got workoutExerciseId=$workoutExerciseId, unresolvedUuid=$unresolvedUuid, unresolvedSlug=$unresolvedSlug)',
       );

  final String buddySessionId;
  final String slotId;
  final int? workoutExerciseId;
  final String? unresolvedUuid;
  final String? unresolvedSlug;
  final String? placeholderLabel;
  final int orderIndex;

  bool get isPlaceholder => workoutExerciseId == null;
}

/// CRUD store over [BuddyChoreographySlots] scoped to one [buddySessionId].
class BuddySlotStore {
  BuddySlotStore(this._db, this.buddySessionId);

  final AppDatabase _db;
  final String buddySessionId;

  BuddySlot _fromData(BuddyChoreographySlotData row) {
    return BuddySlot(
      buddySessionId: row.buddySessionId,
      slotId: row.slotId,
      workoutExerciseId: row.workoutExerciseId,
      unresolvedUuid: row.unresolvedUuid,
      unresolvedSlug: row.unresolvedSlug,
      placeholderLabel: row.placeholderLabel,
      orderIndex: row.orderIndex,
    );
  }

  Future<BuddySlot?> bySlotId(String slotId) async {
    final row = await (_db.select(_db.buddyChoreographySlots)..where(
          (t) =>
              t.buddySessionId.equals(buddySessionId) & t.slotId.equals(slotId),
        ))
        .getSingleOrNull();
    return row == null ? null : _fromData(row);
  }

  Future<BuddySlot?> byWorkoutExerciseId(int id) async {
    final row = await (_db.select(_db.buddyChoreographySlots)..where(
          (t) =>
              t.buddySessionId.equals(buddySessionId) &
              t.workoutExerciseId.equals(id),
        ))
        .getSingleOrNull();
    return row == null ? null : _fromData(row);
  }

  Future<List<BuddySlot>> all() async {
    final rows =
        await (_db.select(_db.buddyChoreographySlots)
              ..where((t) => t.buddySessionId.equals(buddySessionId))
              ..orderBy([(t) => OrderingTerm(expression: t.orderIndex)]))
            .get();
    return rows.map(_fromData).toList();
  }

  Future<void> upsert(BuddySlot slot) async {
    await _db.into(_db.buddyChoreographySlots).insertOnConflictUpdate(
      BuddyChoreographySlotsCompanion(
        buddySessionId: Value(buddySessionId),
        slotId: Value(slot.slotId),
        workoutExerciseId: Value(slot.workoutExerciseId),
        unresolvedUuid: Value(slot.unresolvedUuid),
        unresolvedSlug: Value(slot.unresolvedSlug),
        placeholderLabel: Value(slot.placeholderLabel),
        orderIndex: Value(slot.orderIndex),
      ),
    );
  }

  Future<void> unlink(String slotId) async {
    await (_db.delete(_db.buddyChoreographySlots)..where(
          (t) =>
              t.buddySessionId.equals(buddySessionId) & t.slotId.equals(slotId),
        ))
        .go();
  }

  Future<void> deleteSlot(String slotId) async {
    await unlink(slotId);
  }
}
