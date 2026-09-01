import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:flutter_test/flutter_test.dart';
import 'package:herculex/core/clock.dart';
import 'package:herculex/data/local/database.dart';
import 'package:herculex/data/sync/sync_id_resolver.dart';
import 'package:herculex/features/buddy/data/buddy_choreography_applier.dart';
import 'package:herculex/features/buddy/data/buddy_slot_store.dart';
import 'package:herculex/features/buddy/domain/buddy_event.dart';
import 'package:herculex/features/workouts/data/workouts_repository.dart';

import '../support/test_database.dart';

void main() {
  late AppDatabase db;
  late WorkoutsRepository workouts;
  late SyncIdResolver resolver;
  late BuddySlotStore slotStore;
  late BuddyChoreographyApplier applier;
  late int sessionId;
  late int benchPressId;
  late int squatId;
  const buddySessionId = 'buddy-session-1';

  setUp(() async {
    db = await openTestDatabase();
    workouts = WorkoutsRepository(db, const SystemClock());
    resolver = SyncIdResolver(db);
    slotStore = BuddySlotStore(db, buddySessionId);

    sessionId = await db
        .into(db.workoutSessions)
        .insert(
          WorkoutSessionsCompanion.insert(startedAt: DateTime(2026, 8, 1)),
        );

    benchPressId = await db
        .into(db.exerciseCatalog)
        .insert(
          ExerciseCatalogCompanion.insert(
            name: 'Bench Press',
            primaryMuscle: 'Chest',
            equipment: 'Barbell',
            mechanics: 'compound',
            force: 'push',
            plane: 'horizontal',
            slug: const Value('bench-press'),
          ),
        );

    squatId = await db
        .into(db.exerciseCatalog)
        .insert(
          ExerciseCatalogCompanion.insert(
            name: 'Squat',
            primaryMuscle: 'Quads',
            equipment: 'Barbell',
            mechanics: 'compound',
            force: 'push',
            plane: 'vertical',
            slug: const Value('squat'),
          ),
        );

    applier = BuddyChoreographyApplier(
      db: db,
      workouts: workouts,
      resolver: resolver,
      slots: slotStore,
      localWorkoutSessionId: sessionId,
    );
  });

  tearDown(() async {
    await db.close();
  });

  BuddyEvent makeAddEvent(String slotId, String slug, {String? afterSlotId}) {
    return BuddyEvent(
      buddySessionId: buddySessionId,
      seq: 1,
      actorUserId: 'user-1',
      kind: BuddyEventKind.add,
      payload: {
        'slotId': slotId,
        'ref': {'slug': slug, 'uuid': null},
        'afterSlotId': afterSlotId,
      },
    );
  }

  test(
    'add with resolvable ref creates local exercise and slot mapping',
    () async {
      final outcome = await applier.apply(
        makeAddEvent('slot-1', 'bench-press'),
      );

      expect(outcome, BuddyApplyOutcome.applied);
      final slots = await slotStore.all();
      expect(slots, hasLength(1));
      expect(slots.single.slotId, 'slot-1');
      expect(slots.single.isPlaceholder, isFalse);

      final we = await (db.select(
        db.workoutExercises,
      )..where((t) => t.sessionId.equals(sessionId))).get();
      expect(we, hasLength(1));
      expect(we.single.exerciseId, benchPressId);
    },
  );

  test(
    'unresolvable ref creates placeholder slot and does not add workout exercise',
    () async {
      final event = makeAddEvent('slot-missing', 'unknown-exercise-slug');
      final outcome = await applier.apply(event);

      expect(outcome, BuddyApplyOutcome.placeholderCreated);

      final slots = await slotStore.all();
      expect(slots, hasLength(1));
      expect(slots.single.isPlaceholder, isTrue);
      expect(slots.single.unresolvedSlug, 'unknown-exercise-slug');

      final we = await (db.select(
        db.workoutExercises,
      )..where((t) => t.sessionId.equals(sessionId))).get();
      expect(we, isEmpty);
    },
  );

  test(
    'duplicate add is ignored and does not create duplicate exercises',
    () async {
      await applier.apply(makeAddEvent('slot-1', 'bench-press'));
      final outcome2 = await applier.apply(
        makeAddEvent('slot-1', 'bench-press'),
      );

      expect(outcome2, BuddyApplyOutcome.ignoredDuplicate);
      final we = await (db.select(
        db.workoutExercises,
      )..where((t) => t.sessionId.equals(sessionId))).get();
      expect(we, hasLength(1));
    },
  );

  test(
    'reorder updates absolute orderIndex of slots and workout exercises',
    () async {
      await applier.apply(makeAddEvent('slot-1', 'bench-press'));
      await applier.apply(makeAddEvent('slot-2', 'squat'));

      final reorderEvent = BuddyEvent(
        buddySessionId: buddySessionId,
        seq: 3,
        actorUserId: 'user-1',
        kind: BuddyEventKind.reorder,
        payload: {
          'order': ['slot-2', 'slot-1'],
        },
      );

      final outcome = await applier.apply(reorderEvent);
      expect(outcome, BuddyApplyOutcome.applied);

      final slot1 = await slotStore.bySlotId('slot-1');
      final slot2 = await slotStore.bySlotId('slot-2');
      expect(slot2!.orderIndex, 0);
      expect(slot1!.orderIndex, 1);

      final weSquat = await (db.select(
        db.workoutExercises,
      )..where((t) => t.id.equals(slot2.workoutExerciseId!))).getSingle();
      final weBench = await (db.select(
        db.workoutExercises,
      )..where((t) => t.id.equals(slot1.workoutExerciseId!))).getSingle();
      expect(weSquat.orderIndex, 0);
      expect(weBench.orderIndex, 1);
    },
  );

  test('replace substitutes exercise on existing slot', () async {
    await applier.apply(makeAddEvent('slot-1', 'bench-press'));

    final replaceEvent = BuddyEvent(
      buddySessionId: buddySessionId,
      seq: 2,
      actorUserId: 'user-1',
      kind: BuddyEventKind.replace,
      payload: {
        'slotId': 'slot-1',
        'ref': {'slug': 'squat', 'uuid': null},
      },
    );

    final outcome = await applier.apply(replaceEvent);
    expect(outcome, BuddyApplyOutcome.applied);

    final slot = await slotStore.bySlotId('slot-1');
    final we = await (db.select(
      db.workoutExercises,
    )..where((t) => t.id.equals(slot!.workoutExerciseId!))).getSingle();
    expect(we.exerciseId, squatId);
  });

  group('remove', () {
    test('remove with zero sets deletes the exercise and slot', () async {
      await applier.apply(makeAddEvent('slot-1', 'bench-press'));
      final slotBefore = await slotStore.bySlotId('slot-1');
      expect(slotBefore, isNotNull);

      // Delete the default initial blank set to simulate 0 sets
      await (db.delete(db.setEntries)..where(
            (t) => t.workoutExerciseId.equals(slotBefore!.workoutExerciseId!),
          ))
          .go();

      final removeEvent = BuddyEvent(
        buddySessionId: buddySessionId,
        seq: 2,
        actorUserId: 'user-1',
        kind: BuddyEventKind.remove,
        payload: {'slotId': 'slot-1'},
      );

      final outcome = await applier.apply(removeEvent);
      expect(outcome, BuddyApplyOutcome.applied);

      final slotAfter = await slotStore.bySlotId('slot-1');
      expect(slotAfter, isNull);

      final we =
          await (db.select(db.workoutExercises)
                ..where((t) => t.id.equals(slotBefore!.workoutExerciseId!)))
              .getSingleOrNull();
      expect(we, isNull);
    });

    test('remove never discards logged sets', () async {
      await applier.apply(makeAddEvent('slot-1', 'bench-press'));
      final slotBefore = await slotStore.bySlotId('slot-1');
      final weId = slotBefore!.workoutExerciseId!;

      // Log a completed set with distinctive values
      await db
          .into(db.setEntries)
          .insert(
            SetEntriesCompanion.insert(
              workoutExerciseId: weId,
              setIndex: 1,
              weightKg: 105.0,
              reps: 8,
              isCompleted: const Value(true),
            ),
          );

      var noticeEmitted = false;
      final noticingApplier = BuddyChoreographyApplier(
        db: db,
        workouts: workouts,
        resolver: resolver,
        slots: slotStore,
        localWorkoutSessionId: sessionId,
        onNotice: (outcome, msg) {
          if (outcome == BuddyApplyOutcome.keptLocalWork) {
            noticeEmitted = true;
          }
        },
      );

      final removeEvent = BuddyEvent(
        buddySessionId: buddySessionId,
        seq: 2,
        actorUserId: 'user-1',
        kind: BuddyEventKind.remove,
        payload: {'slotId': 'slot-1'},
      );

      final outcome = await noticingApplier.apply(removeEvent);
      expect(outcome, BuddyApplyOutcome.keptLocalWork);
      expect(noticeEmitted, isTrue);

      // Slot mapping is removed / unlinked
      final slotAfter = await slotStore.bySlotId('slot-1');
      expect(slotAfter, isNull);

      // Local WorkoutExercises row and SetEntries rows are PRESERVED
      final weAfter = await (db.select(
        db.workoutExercises,
      )..where((t) => t.id.equals(weId))).getSingleOrNull();
      expect(weAfter, isNotNull);

      final sets = await (db.select(
        db.setEntries,
      )..where((t) => t.workoutExerciseId.equals(weId))).get();
      expect(sets.any((s) => s.weightKg == 105.0 && s.reps == 8), isTrue);
    });
  });
}
