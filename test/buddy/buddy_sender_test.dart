import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:flutter_test/flutter_test.dart';
import 'package:herculex/core/clock.dart';
import 'package:herculex/data/local/database.dart';
import 'package:herculex/data/sync/sync_id_resolver.dart';
import 'package:herculex/features/buddy/application/buddy_choreography_sender.dart';
import 'package:herculex/features/buddy/application/buddy_share_policy.dart';
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
  late BuddySharePolicy policy;
  late BuddyChoreographySender sender;
  late int sessionId;
  late int benchPressId;
  late int squatId;
  late int customExerciseId;
  const buddySessionId = 'sender-session-1';

  setUp(() async {
    db = await openTestDatabase();
    workouts = WorkoutsRepository(db, const SystemClock());
    resolver = SyncIdResolver(db);
    slotStore = BuddySlotStore(db, buddySessionId);
    fakePublisher = FakeBuddyPublisher();
    policy = BuddySharePolicy(db);

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

    customExerciseId = await db
        .into(db.exerciseCatalog)
        .insert(
          ExerciseCatalogCompanion.insert(
            name: 'My Custom Movement',
            primaryMuscle: 'Chest',
            equipment: 'Barbell',
            mechanics: 'compound',
            force: 'push',
            plane: 'horizontal',
            isCustom: const Value(true),
          ),
        );

    sender = BuddyChoreographySender(
      publisher: fakePublisher,
      slots: slotStore,
      workouts: workouts,
      resolver: resolver,
      buddySessionId: buddySessionId,
      localWorkoutSessionId: sessionId,
      newSlotId: () => 'minted-slot-1',
    );
  });

  tearDown(() async {
    await db.close();
  });

  group('share policy', () {
    test('default without user choice uses BuddyScopeDefaults', () async {
      final addDecision = await policy.decide(kind: BuddyActionKind.add);
      expect(addDecision.scope, BuddyScope.both);
      expect(addDecision.userOverridable, isTrue);

      final removeDecision = await policy.decide(kind: BuddyActionKind.remove);
      expect(removeDecision.scope, BuddyScope.mine);
      expect(removeDecision.userOverridable, isTrue);

      final reorderDecision = await policy.decide(
        kind: BuddyActionKind.reorder,
      );
      expect(reorderDecision.scope, BuddyScope.both);
      expect(reorderDecision.userOverridable, isTrue);

      final replaceDecision = await policy.decide(
        kind: BuddyActionKind.replace,
      );
      expect(replaceDecision.scope, BuddyScope.both);
      expect(replaceDecision.userOverridable, isTrue);
    });

    test('user override of both on remove is honoured', () async {
      final decision = await policy.decide(
        kind: BuddyActionKind.remove,
        userChoice: BuddyScope.both,
      );
      expect(decision.scope, BuddyScope.both);
      expect(decision.userOverridable, isTrue);
    });

    test('custom exercise forces scope mine with non-null reason', () async {
      final decision = await policy.decide(
        kind: BuddyActionKind.add,
        exerciseId: customExerciseId,
        userChoice: BuddyScope.both,
      );
      expect(decision.scope, BuddyScope.mine);
      expect(decision.userOverridable, isFalse);
      expect(decision.reason, isNotNull);
      expect(decision.reason, contains('Custom exercises stay on your device'));
    });

    test(
      'no active buddy session forces scope mine with null reason',
      () async {
        final decision = await policy.decide(
          kind: BuddyActionKind.add,
          hasActiveBuddySession: false,
          userChoice: BuddyScope.both,
        );
        expect(decision.scope, BuddyScope.mine);
        expect(decision.userOverridable, isFalse);
        expect(decision.reason, isNull);
      },
    );

    test('decide treats unknown exerciseId as non-custom', () async {
      final decision = await policy.decide(
        kind: BuddyActionKind.add,
        exerciseId: 999999,
      );
      expect(decision.scope, BuddyScope.both);
      expect(decision.userOverridable, isTrue);
    });
  });

  group('sender', () {
    test('scope mine never publishes', () async {
      // 1. add
      await sender.addExercise(
        exerciseId: benchPressId,
        scope: BuddyScope.mine,
      );
      expect(fakePublisher.appendCount, 0);

      final we = await (db.select(
        db.workoutExercises,
      )..where((t) => t.sessionId.equals(sessionId))).getSingle();

      // 2. replace
      await sender.replaceExercise(
        workoutExerciseId: we.id,
        newExerciseId: squatId,
        scope: BuddyScope.mine,
      );
      expect(fakePublisher.appendCount, 0);

      // 3. reorder
      await sender.reorder(
        workoutExerciseIdsInOrder: [we.id],
        scope: BuddyScope.mine,
      );
      expect(fakePublisher.appendCount, 0);

      // 4. remove
      await sender.removeExercise(
        workoutExerciseId: we.id,
        scope: BuddyScope.mine,
      );
      expect(fakePublisher.appendCount, 0);
    });

    test(
      'addExercise with scope both mints slot, applies locally, and publishes',
      () async {
        await sender.addExercise(
          exerciseId: benchPressId,
          scope: BuddyScope.both,
        );

        expect(fakePublisher.appendCount, 1);
        final append = fakePublisher.appends.single;
        expect(append.kind, BuddyEventKind.add);
        expect(append.payload['slotId'], 'minted-slot-1');
        expect(append.payload['ref']['slug'], 'bench-press');

        final slots = await slotStore.all();
        expect(slots, hasLength(1));
        expect(slots.single.slotId, 'minted-slot-1');
      },
    );

    test(
      'rollback on append failure reverts local database modifications',
      () async {
        fakePublisher.failWith = Exception('Simulated Realtime error');

        final weBefore = await (db.select(
          db.workoutExercises,
        )..where((t) => t.sessionId.equals(sessionId))).get();
        expect(weBefore, isEmpty);

        await expectLater(
          sender.addExercise(exerciseId: benchPressId, scope: BuddyScope.both),
          throwsA(isA<Exception>()),
        );

        final weAfter = await (db.select(
          db.workoutExercises,
        )..where((t) => t.sessionId.equals(sessionId))).get();
        expect(weAfter, isEmpty);
        expect(await slotStore.all(), isEmpty);
      },
    );

    test(
      'removeExercise with scope both publishes remove payload with slotId',
      () async {
        await sender.addExercise(
          exerciseId: benchPressId,
          scope: BuddyScope.both,
        );
        final slot = (await slotStore.all()).single;

        await sender.removeExercise(
          workoutExerciseId: slot.workoutExerciseId!,
          scope: BuddyScope.both,
        );

        expect(fakePublisher.appendCount, 2);
        final removeAppend = fakePublisher.appends[1];
        expect(removeAppend.kind, BuddyEventKind.remove);
        expect(removeAppend.payload['slotId'], 'minted-slot-1');
        expect(await slotStore.all(), isEmpty);
      },
    );

    test(
      'removeExercise on local-only exercise publishes nothing even with scope both',
      () async {
        await sender.addExercise(
          exerciseId: benchPressId,
          scope: BuddyScope.mine, // local only
        );
        final we = (await (db.select(
          db.workoutExercises,
        )..where((t) => t.sessionId.equals(sessionId))).get()).single;

        await sender.removeExercise(
          workoutExerciseId: we.id,
          scope: BuddyScope.both,
        );

        expect(fakePublisher.appendCount, 0);
      },
    );

    test(
      'reorder with scope both publishes absolute slotId order excluding local-only exercises',
      () async {
        var slotCounter = 1;
        final multiSender = BuddyChoreographySender(
          publisher: fakePublisher,
          slots: slotStore,
          workouts: workouts,
          resolver: resolver,
          buddySessionId: buddySessionId,
          localWorkoutSessionId: sessionId,
          newSlotId: () => 'slot-${slotCounter++}',
        );

        await multiSender.addExercise(
          exerciseId: benchPressId,
          scope: BuddyScope.both,
        ); // slot-1
        await multiSender.addExercise(
          exerciseId: squatId,
          scope: BuddyScope.both,
        ); // slot-2
        await multiSender.addExercise(
          exerciseId: benchPressId,
          scope: BuddyScope.mine,
        ); // local only

        final allExercises = await (db.select(
          db.workoutExercises,
        )..where((t) => t.sessionId.equals(sessionId))).get();

        // Reverse order of exercises
        final reversedIds = allExercises
            .map((e) => e.id)
            .toList()
            .reversed
            .toList();

        await multiSender.reorder(
          workoutExerciseIdsInOrder: reversedIds,
          scope: BuddyScope.both,
        );

        final reorderAppend = fakePublisher.appends.last;
        expect(reorderAppend.kind, BuddyEventKind.reorder);
        expect(reorderAppend.payload['order'], ['slot-2', 'slot-1']);
      },
    );

    test(
      'replaceExercise with scope both publishes replace payload with slotId',
      () async {
        await sender.addExercise(
          exerciseId: benchPressId,
          scope: BuddyScope.both,
        );
        final slot = (await slotStore.all()).single;

        await sender.replaceExercise(
          workoutExerciseId: slot.workoutExerciseId!,
          newExerciseId: squatId,
          scope: BuddyScope.both,
        );

        expect(fakePublisher.appendCount, 2);
        final replaceAppend = fakePublisher.appends[1];
        expect(replaceAppend.kind, BuddyEventKind.replace);
        expect(replaceAppend.payload['slotId'], 'minted-slot-1');
        expect(replaceAppend.payload['ref']['slug'], 'squat');
      },
    );
  });
}
