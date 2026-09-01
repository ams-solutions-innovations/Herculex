import 'package:drift/drift.dart';

import '../../../data/local/database.dart';
import '../../../data/sync/sync_id_resolver.dart';
import '../../workouts/data/workouts_repository.dart';
import '../domain/buddy_event.dart';
import 'buddy_slot_store.dart';

enum BuddyApplyOutcome {
  applied,
  ignoredDuplicate,
  keptLocalWork,
  placeholderCreated,
  unknownKind,
}

/// Applies inbound [BuddyEvent]s into the local database, managing slot
/// identities, placeholders for unresolvable exercises, and preserving local
/// work under BUD-06 when exercises are removed remotely.
class BuddyChoreographyApplier {
  BuddyChoreographyApplier({
    required AppDatabase db,
    required WorkoutsRepository workouts,
    required SyncIdResolver resolver,
    required BuddySlotStore slots,
    required int localWorkoutSessionId,
    this.onNotice,
  }) : _db = db,
       _workouts = workouts,
       _resolver = resolver,
       _slots = slots,
       _localWorkoutSessionId = localWorkoutSessionId;

  final AppDatabase _db;
  final WorkoutsRepository _workouts;
  final SyncIdResolver _resolver;
  final BuddySlotStore _slots;
  final int _localWorkoutSessionId;
  final void Function(BuddyApplyOutcome outcome, String message)? onNotice;

  Future<BuddyApplyOutcome> apply(BuddyEvent event) async {
    switch (event.kind) {
      case BuddyEventKind.add:
        return _applyAdd(event);
      case BuddyEventKind.remove:
        return _applyRemove(event);
      case BuddyEventKind.reorder:
        return _applyReorder(event);
      case BuddyEventKind.replace:
        return _applyReplace(event);
      case BuddyEventKind.sessionEnded:
        return BuddyApplyOutcome.applied;
    }
  }

  Future<BuddyApplyOutcome> _applyAdd(BuddyEvent event) async {
    final payload = BuddyAddPayload.fromJson(event.payload);

    final existingSlot = await _slots.bySlotId(payload.slotId);
    if (existingSlot != null) {
      return BuddyApplyOutcome.ignoredDuplicate;
    }

    final resolvedId = await _resolver.resolveCatalogueRefForPull(
      localTable: 'exercise_catalog',
      naturalKeyColumn: 'slug',
      uuid: payload.ref.uuid,
      naturalKey: payload.ref.slug,
    );

    final allSlots = await _slots.all();
    int targetOrder;
    if (payload.afterSlotId != null) {
      final afterSlot = await _slots.bySlotId(payload.afterSlotId!);
      targetOrder = afterSlot != null
          ? afterSlot.orderIndex + 1
          : (allSlots.isEmpty ? 0 : allSlots.last.orderIndex + 1);
    } else {
      targetOrder = allSlots.isEmpty ? 0 : allSlots.last.orderIndex + 1;
    }

    if (resolvedId == null) {
      final placeholderSlot = BuddySlot(
        buddySessionId: _slots.buddySessionId,
        slotId: payload.slotId,
        unresolvedUuid: payload.ref.uuid,
        unresolvedSlug: payload.ref.slug,
        placeholderLabel:
            payload.ref.slug ?? payload.ref.uuid ?? 'Partner custom exercise',
        orderIndex: targetOrder,
      );
      await _slots.upsert(placeholderSlot);
      onNotice?.call(
        BuddyApplyOutcome.placeholderCreated,
        'Partner added an exercise not in this catalogue.',
      );
      return BuddyApplyOutcome.placeholderCreated;
    }

    final workoutExerciseId = await _workouts.addExerciseToSession(
      sessionId: _localWorkoutSessionId,
      exerciseId: resolvedId,
      equipmentVariant: payload.equipmentVariant,
    );

    final slot = BuddySlot(
      buddySessionId: _slots.buddySessionId,
      slotId: payload.slotId,
      workoutExerciseId: workoutExerciseId,
      orderIndex: targetOrder,
    );
    await _slots.upsert(slot);
    return BuddyApplyOutcome.applied;
  }

  Future<BuddyApplyOutcome> _applyRemove(BuddyEvent event) async {
    final payload = BuddyRemovePayload.fromJson(event.payload);
    final slot = await _slots.bySlotId(payload.slotId);
    if (slot == null) {
      return BuddyApplyOutcome.ignoredDuplicate;
    }

    if (slot.isPlaceholder) {
      await _slots.deleteSlot(slot.slotId);
      return BuddyApplyOutcome.applied;
    }

    final weId = slot.workoutExerciseId!;
    return _db.transaction(() async {
      final countRow = await _db
          .customSelect(
            'SELECT COUNT(*) as c FROM set_entries WHERE workout_exercise_id = ?',
            variables: [Variable(weId)],
          )
          .getSingle();
      final count = countRow.data['c'] as int? ?? 0;

      if (count == 0) {
        await _workouts.removeWorkoutExercise(weId);
        await _slots.deleteSlot(slot.slotId);
        return BuddyApplyOutcome.applied;
      } else {
        // BUD-06 resolution: keep local work and unlink slot
        await _slots.unlink(slot.slotId);
        final exRow = await (_db.select(
          _db.workoutExercises,
        )..where((t) => t.id.equals(weId))).getSingleOrNull();
        final catalogRow = exRow != null
            ? await (_db.select(
                _db.exerciseCatalog,
              )..where((t) => t.id.equals(exRow.exerciseId))).getSingleOrNull()
            : null;
        final name = catalogRow?.name ?? 'Exercise';
        onNotice?.call(
          BuddyApplyOutcome.keptLocalWork,
          'Your partner dropped $name — yours is kept.',
        );
        return BuddyApplyOutcome.keptLocalWork;
      }
    });
  }

  Future<BuddyApplyOutcome> _applyReorder(BuddyEvent event) async {
    final payload = BuddyReorderPayload.fromJson(event.payload);

    await _db.transaction(() async {
      for (var i = 0; i < payload.order.length; i++) {
        final slotId = payload.order[i];
        final slot = await _slots.bySlotId(slotId);
        if (slot == null) continue;

        await _slots.upsert(
          BuddySlot(
            buddySessionId: slot.buddySessionId,
            slotId: slot.slotId,
            workoutExerciseId: slot.workoutExerciseId,
            unresolvedUuid: slot.unresolvedUuid,
            unresolvedSlug: slot.unresolvedSlug,
            placeholderLabel: slot.placeholderLabel,
            orderIndex: i,
          ),
        );

        if (slot.workoutExerciseId != null) {
          await (_db.update(_db.workoutExercises)
                ..where((t) => t.id.equals(slot.workoutExerciseId!)))
              .write(WorkoutExercisesCompanion(orderIndex: Value(i)));
        }
      }
    });

    return BuddyApplyOutcome.applied;
  }

  Future<BuddyApplyOutcome> _applyReplace(BuddyEvent event) async {
    final payload = BuddyReplacePayload.fromJson(event.payload);
    final slot = await _slots.bySlotId(payload.slotId);
    if (slot == null) {
      return BuddyApplyOutcome.ignoredDuplicate;
    }

    final resolvedId = await _resolver.resolveCatalogueRefForPull(
      localTable: 'exercise_catalog',
      naturalKeyColumn: 'slug',
      uuid: payload.ref.uuid,
      naturalKey: payload.ref.slug,
    );

    if (resolvedId == null) {
      await _slots.upsert(
        BuddySlot(
          buddySessionId: slot.buddySessionId,
          slotId: slot.slotId,
          unresolvedUuid: payload.ref.uuid,
          unresolvedSlug: payload.ref.slug,
          placeholderLabel:
              payload.ref.slug ?? payload.ref.uuid ?? 'Partner custom exercise',
          orderIndex: slot.orderIndex,
        ),
      );
      onNotice?.call(
        BuddyApplyOutcome.placeholderCreated,
        'Partner replaced with an exercise not in this catalogue.',
      );
      return BuddyApplyOutcome.placeholderCreated;
    }

    if (slot.workoutExerciseId != null) {
      await _workouts.substituteExercise(
        workoutExerciseId: slot.workoutExerciseId!,
        newExerciseId: resolvedId,
      );
      return BuddyApplyOutcome.applied;
    } else {
      final newWeId = await _workouts.addExerciseToSession(
        sessionId: _localWorkoutSessionId,
        exerciseId: resolvedId,
      );
      await _slots.upsert(
        BuddySlot(
          buddySessionId: slot.buddySessionId,
          slotId: slot.slotId,
          workoutExerciseId: newWeId,
          orderIndex: slot.orderIndex,
        ),
      );
      return BuddyApplyOutcome.applied;
    }
  }
}
