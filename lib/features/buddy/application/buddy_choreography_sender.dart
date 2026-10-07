import 'package:herculex/data/sync/sync_id_resolver.dart';
import 'package:herculex/features/buddy/data/buddy_event_publisher.dart';
import 'package:herculex/features/buddy/data/buddy_slot_store.dart';
import 'package:herculex/features/buddy/domain/buddy_event.dart';
import 'package:herculex/features/buddy/domain/buddy_scope.dart';
import 'package:herculex/features/workouts/data/workouts_repository.dart';
import 'package:uuid/uuid.dart';

/// Sends user choreography actions to the local store and, when scope is [BuddyScope.both],
/// publishes the action to the shared [BuddyEventPublisher].
class BuddyChoreographySender {
  BuddyChoreographySender({
    required BuddyEventPublisher publisher,
    required BuddySlotStore slots,
    required WorkoutsRepository workouts,
    required SyncIdResolver resolver,
    required String buddySessionId,
    required int localWorkoutSessionId,
    String Function()? newSlotId,
  }) : _publisher = publisher,
       _slots = slots,
       _workouts = workouts,
       _resolver = resolver,
       _buddySessionId = buddySessionId,
       _localWorkoutSessionId = localWorkoutSessionId,
       _newSlotId = newSlotId ?? _defaultNewSlotId;

  final BuddyEventPublisher _publisher;
  final BuddySlotStore _slots;
  final WorkoutsRepository _workouts;
  final SyncIdResolver _resolver;
  final String _buddySessionId;
  final int _localWorkoutSessionId;
  final String Function() _newSlotId;

  static String _defaultNewSlotId() => const Uuid().v4();

  Future<void> addExercise({
    required int exerciseId,
    required BuddyScope scope,
    String? equipmentVariant,
    String? afterSlotId,
  }) async {
    if (scope == BuddyScope.mine) {
      await _workouts.addExerciseToSession(
        sessionId: _localWorkoutSessionId,
        exerciseId: exerciseId,
        equipmentVariant: equipmentVariant,
      );
      return;
    }

    final slotId = _newSlotId();
    final allSlots = await _slots.all();
    int targetOrder;
    if (afterSlotId != null) {
      final after = await _slots.bySlotId(afterSlotId);
      targetOrder = after != null
          ? after.orderIndex + 1
          : (allSlots.isEmpty ? 0 : allSlots.last.orderIndex + 1);
    } else {
      targetOrder = allSlots.isEmpty ? 0 : allSlots.last.orderIndex + 1;
    }

    final workoutExerciseId = await _workouts.addExerciseToSession(
      sessionId: _localWorkoutSessionId,
      exerciseId: exerciseId,
      equipmentVariant: equipmentVariant,
    );

    final slot = BuddySlot(
      buddySessionId: _buddySessionId,
      slotId: slotId,
      workoutExerciseId: workoutExerciseId,
      orderIndex: targetOrder,
    );
    await _slots.upsert(slot);

    final pushRef = await _resolver.resolveCatalogueRefForPush(
      localTable: 'exercise_catalog',
      localId: exerciseId,
      naturalKeyColumn: 'slug',
      isCustomColumn: 'is_custom',
    );
    final exerciseRef = BuddyExerciseRef(uuid: pushRef.$1, slug: pushRef.$2);
    final payload = BuddyAddPayload(
      slotId: slotId,
      ref: exerciseRef,
      afterSlotId: afterSlotId,
      equipmentVariant: equipmentVariant,
    );

    try {
      await _publisher.append(
        buddySessionId: _buddySessionId,
        kind: BuddyEventKind.add,
        payload: payload.toJson(),
      );
    } catch (e) {
      await _slots.deleteSlot(slotId);
      await _workouts.removeWorkoutExercise(workoutExerciseId);
      rethrow;
    }
  }

  Future<void> removeExercise({
    required int workoutExerciseId,
    required BuddyScope scope,
  }) async {
    final slot = await _slots.byWorkoutExerciseId(workoutExerciseId);

    if (scope == BuddyScope.mine || slot == null) {
      if (slot != null) {
        await _slots.unlink(slot.slotId);
      }
      await _workouts.removeWorkoutExercise(workoutExerciseId);
      return;
    }

    final payload = BuddyRemovePayload(slotId: slot.slotId);
    await _slots.deleteSlot(slot.slotId);
    await _workouts.removeWorkoutExercise(workoutExerciseId);

    await _publisher.append(
      buddySessionId: _buddySessionId,
      kind: BuddyEventKind.remove,
      payload: payload.toJson(),
    );
  }

  Future<void> reorder({
    required List<int> workoutExerciseIdsInOrder,
    required BuddyScope scope,
  }) async {
    for (var i = 0; i < workoutExerciseIdsInOrder.length; i++) {
      final weId = workoutExerciseIdsInOrder[i];
      final slot = await _slots.byWorkoutExerciseId(weId);
      if (slot != null) {
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
      }
    }

    if (scope == BuddyScope.mine) {
      return;
    }

    final orderList = <String>[];
    for (final weId in workoutExerciseIdsInOrder) {
      final slot = await _slots.byWorkoutExerciseId(weId);
      if (slot != null) {
        orderList.add(slot.slotId);
      }
    }

    if (orderList.isNotEmpty) {
      final payload = BuddyReorderPayload(order: orderList);
      await _publisher.append(
        buddySessionId: _buddySessionId,
        kind: BuddyEventKind.reorder,
        payload: payload.toJson(),
      );
    }
  }

  Future<void> replaceExercise({
    required int workoutExerciseId,
    required int newExerciseId,
    required BuddyScope scope,
  }) async {
    final slot = await _slots.byWorkoutExerciseId(workoutExerciseId);
    await _workouts.substituteExercise(
      workoutExerciseId: workoutExerciseId,
      newExerciseId: newExerciseId,
    );

    if (scope == BuddyScope.mine || slot == null) {
      return;
    }

    final pushRef = await _resolver.resolveCatalogueRefForPush(
      localTable: 'exercise_catalog',
      localId: newExerciseId,
      naturalKeyColumn: 'slug',
      isCustomColumn: 'is_custom',
    );
    final exerciseRef = BuddyExerciseRef(uuid: pushRef.$1, slug: pushRef.$2);
    final payload = BuddyReplacePayload(slotId: slot.slotId, ref: exerciseRef);

    await _publisher.append(
      buddySessionId: _buddySessionId,
      kind: BuddyEventKind.replace,
      payload: payload.toJson(),
    );
  }
}
