import 'package:flutter_test/flutter_test.dart';
import 'package:herculex/core/clock.dart';
import 'package:herculex/data/local/database.dart';
import 'package:herculex/data/sync/sync_id_resolver.dart';
import 'package:herculex/features/buddy/application/buddy_session_controller.dart';
import 'package:herculex/features/buddy/data/buddy_channel_service.dart';
import 'package:herculex/features/buddy/data/buddy_remote_gateway.dart';
import 'package:herculex/features/buddy/domain/buddy_event.dart';
import 'package:herculex/features/buddy/domain/buddy_join_payload.dart';
import 'package:herculex/features/workouts/data/workouts_repository.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../support/test_database.dart';
import 'fake_buddy_gateway.dart';

class FakeBuddyChannelService extends BuddyChannelService {
  FakeBuddyChannelService({required super.gateway})
    : super(client: SupabaseClient('https://dummy.supabase.co', 'anon-key'));

  bool isConnected = false;
  String? connectedSessionId;
  int? connectedLastSeenSeq;

  @override
  Future<void> connect({
    required String buddySessionId,
    required int lastSeenSeq,
    required String userId,
    String? displayName,
    required Future<void> Function(BuddyEvent) apply,
    required Future<void> Function(int seq) commitSeq,
  }) async {
    isConnected = true;
    connectedSessionId = buddySessionId;
    connectedLastSeenSeq = lastSeenSeq;
  }

  @override
  Future<void> disconnect() async {
    isConnected = false;
  }
}

void main() {
  late AppDatabase db;
  late WorkoutsRepository workouts;
  late SyncIdResolver resolver;
  late FakeBuddyGateway gateway;
  late FakeBuddyChannelService channelService;
  late BuddySessionController controller;
  const currentUserId = 'user-test-host';

  setUp(() async {
    db = await openTestDatabase();
    workouts = WorkoutsRepository(db, const SystemClock());
    resolver = SyncIdResolver(db);
    gateway = FakeBuddyGateway();
    channelService = FakeBuddyChannelService(gateway: gateway);

    controller = BuddySessionController(
      db: db,
      gateway: gateway,
      channelService: channelService,
      workouts: workouts,
      resolver: resolver,
      currentUserId: currentUserId,
      currentDisplayName: 'Martin',
    );
  });

  tearDown(() async {
    controller.dispose();
    await db.close();
  });

  group('host', () {
    test(
      'hosting with no active workout throws StateError and leaves no local session',
      () async {
        await expectLater(
          controller.hostFromActiveWorkout(),
          throwsA(isA<StateError>()),
        );

        final localSessions = await db.select(db.buddySessionsLocal).get();
        expect(localSessions, isEmpty);
      },
    );

    test(
      'hostFromActiveWorkout creates session, links workout, connects channel, and returns token',
      () async {
        final workoutId = await workouts.startSession();
        final token = await controller.hostFromActiveWorkout();

        expect(token, isNotEmpty);
        expect(controller.state.isHost, isTrue);
        expect(controller.state.pendingJoinToken, token);
        expect(controller.state.buddySessionId, isNotNull);

        // Verify local workout row gained buddySessionId
        final workout = await (db.select(
          db.workoutSessions,
        )..where((t) => t.id.equals(workoutId))).getSingle();
        expect(workout.buddySessionId, controller.state.buddySessionId);

        // Verify BuddySessionsLocal entry
        final local =
            await (db.select(db.buddySessionsLocal)..where(
                  (t) =>
                      t.buddySessionId.equals(controller.state.buddySessionId!),
                ))
                .getSingle();
        expect(local.role, 'host');
        expect(local.lastSeenSeq, 0);

        // Verify channel service connected
        expect(channelService.isConnected, isTrue);
        expect(
          channelService.connectedSessionId,
          controller.state.buddySessionId,
        );
      },
    );
  });

  group('join', () {
    test(
      'joinFromScan with malformed payload rejects before calling gateway',
      () async {
        await expectLater(
          controller.joinFromScan('bad-non-qr-string'),
          throwsA(isA<BuddyJoinRejected>()),
        );
        expect(gateway.joinCallCount, 0);
      },
    );

    test(
      'joinFromScan with no active workout auto-starts local workout and links it',
      () async {
        final joinPayload = const BuddyJoinPayload('valid-token-123').encode();

        await controller.joinFromScan(joinPayload);

        expect(controller.state.isHost, isFalse);
        expect(controller.state.buddySessionId, isNotNull);
        expect(controller.state.isLive, isTrue);

        final activeWorkouts = await (db.select(
          db.workoutSessions,
        )..where((t) => t.endedAt.isNull())).get();
        expect(activeWorkouts, hasLength(1));
        expect(
          activeWorkouts.single.buddySessionId,
          controller.state.buddySessionId,
        );

        final local =
            await (db.select(db.buddySessionsLocal)..where(
                  (t) =>
                      t.buddySessionId.equals(controller.state.buddySessionId!),
                ))
                .getSingle();
        expect(local.role, 'guest');
      },
    );

    test(
      'joinFromScan with existing active workout links that session without starting a second',
      () async {
        final existingWorkoutId = await workouts.startSession();
        final joinPayload = const BuddyJoinPayload('valid-token-456').encode();

        await controller.joinFromScan(joinPayload);

        final activeWorkouts = await (db.select(
          db.workoutSessions,
        )..where((t) => t.endedAt.isNull())).get();
        expect(activeWorkouts, hasLength(1));
        expect(activeWorkouts.single.id, existingWorkoutId);
        expect(
          activeWorkouts.single.buddySessionId,
          controller.state.buddySessionId,
        );
      },
    );

    test(
      'join rejection on invalid token throws BuddyJoinRejected and does not leave dangling workout',
      () async {
        gateway.failJoinWith = const BuddyJoinRejected(
          'Invalid or expired join code',
        );
        final joinPayload = const BuddyJoinPayload('rejected-token').encode();

        await expectLater(
          controller.joinFromScan(joinPayload),
          throwsA(isA<BuddyJoinRejected>()),
        );

        final activeWorkouts = await (db.select(
          db.workoutSessions,
        )..where((t) => t.endedAt.isNull())).get();
        expect(activeWorkouts, isEmpty);
        expect(await db.select(db.buddySessionsLocal).get(), isEmpty);
      },
    );
  });

  group('leave', () {
    test(
      'leave disconnects channel and clears state while preserving workout and buddySessionId link',
      () async {
        final workoutId = await workouts.startSession();
        await controller.hostFromActiveWorkout();
        final buddySessionId = controller.state.buddySessionId!;

        await controller.leave();

        expect(channelService.isConnected, isFalse);
        expect(controller.state.isSharing, isFalse);

        // Local workout is still running
        final workout = await (db.select(
          db.workoutSessions,
        )..where((t) => t.id.equals(workoutId))).getSingle();
        expect(workout.endedAt, isNull);
        expect(workout.buddySessionId, buddySessionId);

        // BuddySessionsLocal marked as ended
        final local = await (db.select(
          db.buddySessionsLocal,
        )..where((t) => t.buddySessionId.equals(buddySessionId))).getSingle();
        expect(local.endedAt, isNotNull);

        // Calling leave again is a safe no-op
        await expectLater(controller.leave(), completes);
      },
    );

    test(
      'endForEveryone appends sessionEnded event when called by host',
      () async {
        await workouts.startSession();
        await controller.hostFromActiveWorkout();

        await controller.endForEveryone();

        expect(
          gateway.events.any((e) => e.kind == BuddyEventKind.sessionEnded),
          isTrue,
        );
        expect(controller.state.isSharing, isFalse);
      },
    );
  });
}
