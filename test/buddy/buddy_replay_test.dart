import 'package:drift/drift.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:herculex/core/clock.dart';
import 'package:herculex/data/local/database.dart';
import 'package:herculex/data/sync/sync_id_resolver.dart';
import 'package:herculex/features/buddy/data/buddy_choreography_applier.dart';
import 'package:herculex/features/buddy/data/buddy_event_stream.dart';
import 'package:herculex/features/buddy/data/buddy_slot_store.dart';
import 'package:herculex/features/buddy/domain/buddy_event.dart';
import 'package:herculex/features/workouts/data/workouts_repository.dart';

import '../support/test_database.dart';
import 'fake_buddy_gateway.dart';

void main() {
  late AppDatabase db;
  late WorkoutsRepository workouts;
  late SyncIdResolver resolver;
  late BuddySlotStore slotStore;
  late FakeBuddyGateway gateway;
  late int sessionId;
  const buddySessionId = 'replay-session-1';

  setUp(() async {
    db = await openTestDatabase();
    workouts = WorkoutsRepository(db, const SystemClock());
    resolver = SyncIdResolver(db);
    slotStore = BuddySlotStore(db, buddySessionId);
    gateway = FakeBuddyGateway();

    sessionId = await db
        .into(db.workoutSessions)
        .insert(WorkoutSessionsCompanion.insert(startedAt: DateTime(2026, 8, 1)));

    // Seed test catalogue exercises
    for (final slug in ['bench-press', 'squat', 'deadlift', 'overhead-press']) {
      await db
          .into(db.exerciseCatalog)
          .insert(
            ExerciseCatalogCompanion.insert(
              name: slug,
              primaryMuscle: 'All',
              equipment: 'Barbell',
              mechanics: 'compound',
              force: 'push',
              plane: 'vertical',
              slug: Value(slug),
            ),
          );
    }
  });

  tearDown(() async {
    await db.close();
  });

  test('cold start replay from log reconstructs correct exercise list', () async {
    gateway.events.addAll([
      BuddyEvent(
        buddySessionId: buddySessionId,
        seq: 1,
        actorUserId: 'u1',
        kind: BuddyEventKind.add,
        payload: {
          'slotId': 'slot-1',
          'ref': {'slug': 'bench-press', 'uuid': null},
        },
      ),
      BuddyEvent(
        buddySessionId: buddySessionId,
        seq: 2,
        actorUserId: 'u1',
        kind: BuddyEventKind.add,
        payload: {
          'slotId': 'slot-2',
          'ref': {'slug': 'squat', 'uuid': null},
        },
      ),
      BuddyEvent(
        buddySessionId: buddySessionId,
        seq: 3,
        actorUserId: 'u1',
        kind: BuddyEventKind.reorder,
        payload: {
          'order': ['slot-2', 'slot-1'],
        },
      ),
    ]);

    final applier = BuddyChoreographyApplier(
      db: db,
      workouts: workouts,
      resolver: resolver,
      slots: slotStore,
      localWorkoutSessionId: sessionId,
    );

    int savedLastSeenSeq = 0;
    final stream = BuddyEventStream(
      gateway: gateway,
      buddySessionId: buddySessionId,
      lastSeenSeq: savedLastSeenSeq,
      apply: (e) => applier.apply(e),
      commitSeq: (s) async {
        savedLastSeenSeq = s;
      },
    );

    await stream.start();

    expect(savedLastSeenSeq, 3);
    final slots = await slotStore.all();
    expect(slots, hasLength(2));
    expect(slots[0].slotId, 'slot-2');
    expect(slots[1].slotId, 'slot-1');

    // Second pass changes nothing
    final stream2 = BuddyEventStream(
      gateway: gateway,
      buddySessionId: buddySessionId,
      lastSeenSeq: savedLastSeenSeq,
      apply: (e) => applier.apply(e),
      commitSeq: (s) async {
        savedLastSeenSeq = s;
      },
    );
    await stream2.start();
    expect(await slotStore.all(), hasLength(2));
  });

  test('interrupted replay resumes from last committed seq', () async {
    gateway.events.addAll([
      BuddyEvent(
        buddySessionId: buddySessionId,
        seq: 1,
        actorUserId: 'u1',
        kind: BuddyEventKind.add,
        payload: {
          'slotId': 'slot-1',
          'ref': {'slug': 'bench-press', 'uuid': null},
        },
      ),
      BuddyEvent(
        buddySessionId: buddySessionId,
        seq: 2,
        actorUserId: 'u1',
        kind: BuddyEventKind.add,
        payload: {
          'slotId': 'slot-2',
          'ref': {'slug': 'squat', 'uuid': null},
        },
      ),
      BuddyEvent(
        buddySessionId: buddySessionId,
        seq: 3,
        actorUserId: 'u1',
        kind: BuddyEventKind.add,
        payload: {
          'slotId': 'slot-3',
          'ref': {'slug': 'deadlift', 'uuid': null},
        },
      ),
    ]);

    int savedLastSeenSeq = 0;
    var failOnSeq = 2;

    final applier = BuddyChoreographyApplier(
      db: db,
      workouts: workouts,
      resolver: resolver,
      slots: slotStore,
      localWorkoutSessionId: sessionId,
    );

    final stream1 = BuddyEventStream(
      gateway: gateway,
      buddySessionId: buddySessionId,
      lastSeenSeq: savedLastSeenSeq,
      apply: (e) async {
        if (e.seq == failOnSeq) throw Exception('Simulated network/DB crash');
        await applier.apply(e);
      },
      commitSeq: (s) async {
        savedLastSeenSeq = s;
      },
    );

    await expectLater(stream1.start(), throwsA(isA<Exception>()));
    expect(savedLastSeenSeq, 1);

    // Resume from savedLastSeenSeq (1)
    failOnSeq = -1; // don't fail this time
    final stream2 = BuddyEventStream(
      gateway: gateway,
      buddySessionId: buddySessionId,
      lastSeenSeq: savedLastSeenSeq,
      apply: (e) => applier.apply(e),
      commitSeq: (s) async {
        savedLastSeenSeq = s;
      },
    );

    await stream2.start();
    expect(savedLastSeenSeq, 3);
    expect(await slotStore.all(), hasLength(3));
  });

  test('replay with unresolvable reference converges with placeholder in correct slot', () async {
    gateway.events.addAll([
      BuddyEvent(
        buddySessionId: buddySessionId,
        seq: 1,
        actorUserId: 'u1',
        kind: BuddyEventKind.add,
        payload: {
          'slotId': 'slot-1',
          'ref': {'slug': 'bench-press', 'uuid': null},
        },
      ),
      BuddyEvent(
        buddySessionId: buddySessionId,
        seq: 2,
        actorUserId: 'u1',
        kind: BuddyEventKind.add,
        payload: {
          'slotId': 'slot-custom',
          'ref': {'slug': null, 'uuid': 'missing-custom-uuid'},
        },
      ),
    ]);

    final applier = BuddyChoreographyApplier(
      db: db,
      workouts: workouts,
      resolver: resolver,
      slots: slotStore,
      localWorkoutSessionId: sessionId,
    );

    int savedLastSeenSeq = 0;
    final stream = BuddyEventStream(
      gateway: gateway,
      buddySessionId: buddySessionId,
      lastSeenSeq: 0,
      apply: (e) => applier.apply(e),
      commitSeq: (s) async => savedLastSeenSeq = s,
    );

    await stream.start();

    expect(savedLastSeenSeq, 2);
    final slots = await slotStore.all();
    expect(slots, hasLength(2));
    expect(slots[0].slotId, 'slot-1');
    expect(slots[0].isPlaceholder, isFalse);
    expect(slots[1].slotId, 'slot-custom');
    expect(slots[1].isPlaceholder, isTrue);
  });
}
