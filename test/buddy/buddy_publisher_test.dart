import 'package:drift/drift.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:herculex/core/utils/clock.dart';
import 'package:herculex/data/local/database.dart';
import 'package:herculex/data/sync/sync_id_resolver.dart';
import 'package:herculex/features/buddy/application/buddy_choreography_sender.dart';
import 'package:herculex/features/buddy/data/buddy_slot_store.dart';
import 'package:herculex/features/buddy/domain/buddy_event.dart';
import 'package:herculex/features/buddy/domain/buddy_scope.dart';
import 'package:herculex/features/workouts/data/workouts_repository.dart';

import '../support/test_database.dart';
import 'fake_buddy_publisher.dart';

void main() {
  late AppDatabase db;
  late WorkoutsRepository workouts;
  late SyncIdResolver resolver;
  late BuddySlotStore slotStore;
  late FakeBuddyPublisher fakePublisher;
  late BuddyChoreographySender sender;
  late int sessionId;
  late int benchPressId;
  late int squatId;
  const buddySessionId = 'publisher-test-session';

  setUp(() async {
    db = await openTestDatabase();
    workouts = WorkoutsRepository(db, const SystemClock());
    resolver = SyncIdResolver(db);
    slotStore = BuddySlotStore(db, buddySessionId);
    fakePublisher = FakeBuddyPublisher();

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

    sender = BuddyChoreographySender(
      publisher: fakePublisher,
      slots: slotStore,
      workouts: workouts,
      resolver: resolver,
      buddySessionId: buddySessionId,
      localWorkoutSessionId: sessionId,
      newSlotId: () => 'slot-abc',
    );
  });

  tearDown(() async {
    await db.close();
  });

  test(
    'no published payload map contains a "scope" key across all kinds',
    () async {
      // 1. Add
      await sender.addExercise(
        exerciseId: benchPressId,
        scope: BuddyScope.both,
      );

      // 2. Replace
      final slot = (await slotStore.all()).single;
      await sender.replaceExercise(
        workoutExerciseId: slot.workoutExerciseId!,
        newExerciseId: squatId,
        scope: BuddyScope.both,
      );

      // 3. Reorder
      await sender.reorder(
        workoutExerciseIdsInOrder: [slot.workoutExerciseId!],
        scope: BuddyScope.both,
      );

      // 4. Remove
      await sender.removeExercise(
        workoutExerciseId: slot.workoutExerciseId!,
        scope: BuddyScope.both,
      );

      expect(fakePublisher.appendCount, 4);

      for (final append in fakePublisher.appends) {
        expect(
          append.payload.containsKey('scope'),
          isFalse,
          reason: 'Payload for ${append.kind} must never contain a "scope" key',
        );
      }
    },
  );

  test('wire contract matches JSON schema per event kind', () async {
    await sender.addExercise(
      exerciseId: benchPressId,
      scope: BuddyScope.both,
      equipmentVariant: 'barbell',
    );

    final addAppend = fakePublisher.appends[0];
    expect(addAppend.kind, BuddyEventKind.add);
    expect(addAppend.payload['slotId'], isA<String>());
    expect(addAppend.payload['ref'], isA<Map<String, dynamic>>());
    expect(addAppend.payload['ref']['slug'], 'bench-press');
    expect(addAppend.payload['equipmentVariant'], 'barbell');

    final addPayloadParsed = BuddyAddPayload.fromJson(addAppend.payload);
    expect(addPayloadParsed.slotId, 'slot-abc');
    expect(addPayloadParsed.ref.slug, 'bench-press');
    expect(addPayloadParsed.equipmentVariant, 'barbell');
  });
}
