import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:flutter_test/flutter_test.dart';
import 'package:herculex/core/clock.dart';
import 'package:herculex/data/local/database.dart';
import 'package:herculex/data/sync/sync_id_resolver.dart';
import 'package:herculex/features/buddy/application/buddy_choreography_sender.dart';
import 'package:herculex/features/buddy/application/buddy_session_controller.dart';
import 'package:herculex/features/buddy/data/buddy_channel_service.dart';
import 'package:herculex/features/buddy/data/buddy_remote_gateway.dart';
import 'package:herculex/features/buddy/data/buddy_slot_store.dart';
import 'package:herculex/features/buddy/domain/buddy_event.dart';
import 'package:herculex/features/buddy/domain/buddy_join_payload.dart';
import 'package:herculex/features/buddy/domain/buddy_scope.dart';
import 'package:herculex/features/workouts/data/workouts_repository.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uuid/uuid.dart';

import '../support/test_database.dart';

/// Simulates the Supabase Realtime / REST transport between two simulated devices.
class TwoDeviceTransport {
  final Map<String, List<BuddyEvent>> _eventsBySession = {};
  final Map<String, List<Future<void> Function(BuddyEvent)>> _subscribers = {};
  final Map<String, String> _tokens = {}; // token -> buddySessionId

  ({String buddySessionId, String joinToken}) createSession({
    required String workoutSessionUuid,
    String? displayName,
    String? avatarUrl,
  }) {
    final buddySessionId = const Uuid().v4();
    final joinToken = const Uuid().v4();
    _tokens[joinToken] = buddySessionId;
    _eventsBySession[buddySessionId] = [];
    _subscribers[buddySessionId] = [];
    return (
      buddySessionId: buddySessionId,
      joinToken: joinToken,
    );
  }

  String joinSession({required String token}) {
    final sessionId = _tokens[token];
    if (sessionId == null) {
      throw const BuddyJoinRejected('Invalid or expired join code');
    }
    return sessionId;
  }

  void subscribe(String buddySessionId, Future<void> Function(BuddyEvent) onEvent) {
    _subscribers.putIfAbsent(buddySessionId, () => []).add(onEvent);
  }

  void unsubscribe(String buddySessionId, Future<void> Function(BuddyEvent) onEvent) {
    _subscribers[buddySessionId]?.remove(onEvent);
  }

  Future<int> append({
    required String buddySessionId,
    required String actorUserId,
    required BuddyEventKind kind,
    required Map<String, dynamic> payload,
  }) async {
    final list = _eventsBySession.putIfAbsent(buddySessionId, () => []);
    final nextSeq = list.length + 1;
    final event = BuddyEvent(
      buddySessionId: buddySessionId,
      seq: nextSeq,
      actorUserId: actorUserId,
      kind: kind,
      payload: payload,
    );
    list.add(event);

    final subs = List<Future<void> Function(BuddyEvent)>.from(_subscribers[buddySessionId] ?? []);
    for (final s in subs) {
      await s(event);
    }

    return nextSeq;
  }

  List<BuddyEvent> fetchEventsSince({
    required String buddySessionId,
    required int afterSeq,
  }) {
    final list = _eventsBySession[buddySessionId] ?? [];
    return list.where((e) => e.seq > afterSeq).toList();
  }
}

class SimulatedBuddyGateway implements BuddyGateway {
  SimulatedBuddyGateway({
    required this.transport,
    required this.userId,
  });

  final TwoDeviceTransport transport;
  final String userId;

  @override
  Future<({String buddySessionId, String joinToken})> createSession({
    required String workoutSessionUuid,
    String? displayName,
    String? avatarUrl,
  }) async {
    return transport.createSession(
      workoutSessionUuid: workoutSessionUuid,
      displayName: displayName,
      avatarUrl: avatarUrl,
    );
  }

  @override
  Future<String> joinSession({
    required String token,
    required String workoutSessionUuid,
    String? displayName,
    String? avatarUrl,
  }) async {
    return transport.joinSession(token: token);
  }

  @override
  Future<int> append({
    required String buddySessionId,
    required BuddyEventKind kind,
    required Map<String, dynamic> payload,
  }) async {
    return transport.append(
      buddySessionId: buddySessionId,
      actorUserId: userId,
      kind: kind,
      payload: payload,
    );
  }

  @override
  Future<List<BuddyEvent>> fetchEventsSince({
    required String buddySessionId,
    required int afterSeq,
  }) async {
    return transport.fetchEventsSince(
      buddySessionId: buddySessionId,
      afterSeq: afterSeq,
    );
  }

  @override
  Future<List<BuddyRemoteParticipant>> fetchParticipants(String buddySessionId) async {
    return const [];
  }

  @override
  Future<void> leave(String buddySessionId) async {}

  @override
  Future<void> endSession(String buddySessionId) async {
    await append(
      buddySessionId: buddySessionId,
      kind: BuddyEventKind.sessionEnded,
      payload: {'endedBy': userId},
    );
  }
}

class SimulatedBuddyChannelService extends BuddyChannelService {
  SimulatedBuddyChannelService({
    required this.transport,
    required super.gateway,
  }) : super(client: SupabaseClient('https://dummy.supabase.co', 'anon-key'));

  final TwoDeviceTransport transport;
  String? _connectedSessionId;
  Future<void> Function(BuddyEvent)? _currentApply;

  @override
  Future<void> connect({
    required String buddySessionId,
    required int lastSeenSeq,
    required String userId,
    String? displayName,
    required Future<void> Function(BuddyEvent) apply,
    required Future<void> Function(int seq) commitSeq,
  }) async {
    _connectedSessionId = buddySessionId;
    _currentApply = (e) async {
      // Don't replay our own appended events back into our own apply callback
      if (e.actorUserId == userId) return;
      await apply(e);
      await commitSeq(e.seq);
    };
    transport.subscribe(buddySessionId, _currentApply!);

    // Replay any events missed
    final missed = transport.fetchEventsSince(
      buddySessionId: buddySessionId,
      afterSeq: lastSeenSeq,
    );
    for (final e in missed) {
      if (e.actorUserId != userId) {
        await apply(e);
        await commitSeq(e.seq);
      }
    }
  }

  @override
  Future<void> disconnect() async {
    if (_connectedSessionId != null && _currentApply != null) {
      transport.unsubscribe(_connectedSessionId!, _currentApply!);
    }
    _connectedSessionId = null;
    _currentApply = null;
  }
}

class DeviceHarness {
  DeviceHarness({
    required this.userId,
    required this.displayName,
    required this.transport,
  });

  final String userId;
  final String displayName;
  final TwoDeviceTransport transport;

  late AppDatabase db;
  late WorkoutsRepository workouts;
  late SyncIdResolver resolver;
  late SimulatedBuddyGateway gateway;
  late SimulatedBuddyChannelService channelService;
  late BuddySessionController controller;

  Future<void> init() async {
    db = await openTestDatabase();
    workouts = WorkoutsRepository(db, const SystemClock());
    resolver = SyncIdResolver(db);
    gateway = SimulatedBuddyGateway(transport: transport, userId: userId);
    channelService = SimulatedBuddyChannelService(transport: transport, gateway: gateway);

    controller = BuddySessionController(
      db: db,
      gateway: gateway,
      channelService: channelService,
      workouts: workouts,
      resolver: resolver,
      currentUserId: userId,
      currentDisplayName: displayName,
    );

    // Seed standard exercise catalog on this device
    await _seedCatalog();
  }

  Future<void> _seedCatalog() async {
    Future<void> ensureExercise(String name, String slug, String muscle, String eq) async {
      final existing = await (db.select(db.exerciseCatalog)
            ..where((t) => t.name.equals(name) & t.equipment.equals(eq)))
          .getSingleOrNull();
      if (existing == null) {
        await db.into(db.exerciseCatalog).insert(
          ExerciseCatalogCompanion.insert(
            name: name,
            primaryMuscle: muscle,
            equipment: eq,
            mechanics: 'compound',
            force: 'push',
            plane: 'horizontal',
            slug: Value(slug),
          ),
        );
      } else {
        await (db.update(db.exerciseCatalog)..where((t) => t.id.equals(existing.id)))
            .write(ExerciseCatalogCompanion(slug: Value(slug)));
      }
    }

    await ensureExercise('Bench Press', 'bench-press', 'Chest', 'Barbell');
    await ensureExercise('Incline Dumbbell Press', 'incline-dumbbell-press', 'Chest', 'Dumbbell');
    await ensureExercise('Bicep Curl', 'bicep-curl', 'Biceps', 'Dumbbell');
  }

  Future<int> getCatalogIdBySlug(String slug) async {
    final entry = await (db.select(db.exerciseCatalog)..where((t) => t.slug.equals(slug))).getSingle();
    return entry.id;
  }

  BuddyChoreographySender makeSender(int localWorkoutSessionId) {
    final sessionId = controller.state.buddySessionId!;
    final slots = BuddySlotStore(db, sessionId);
    return BuddyChoreographySender(
      publisher: gateway,
      slots: slots,
      workouts: workouts,
      resolver: resolver,
      buddySessionId: sessionId,
      localWorkoutSessionId: localWorkoutSessionId,
    );
  }

  Future<void> dispose() async {
    controller.dispose();
    await channelService.disconnect();
    await db.close();
  }
}

void main() {
  late TwoDeviceTransport transport;
  late DeviceHarness host;
  late DeviceHarness guest;

  setUp(() async {
    transport = TwoDeviceTransport();
    host = DeviceHarness(
      userId: 'user-martin-host',
      displayName: 'Martin Host',
      transport: transport,
    );
    guest = DeviceHarness(
      userId: 'user-marko-guest',
      displayName: 'Marko Guest',
      transport: transport,
    );

    await host.init();
    await guest.init();
  });

  tearDown(() async {
    await host.dispose();
    await guest.dispose();
  });

  test('Two-device end-to-end live workout choreography flow', () async {
    // ── 1. Host starts active workout and hosts session ──
    final hostWorkoutId = await host.workouts.startSession();
    final rawToken = await host.controller.hostFromActiveWorkout();

    expect(rawToken, isNotEmpty);
    expect(host.controller.state.isSharing, isTrue);
    expect(host.controller.state.isHost, isTrue);

    // Encode QR payload
    final qrPayload = BuddyJoinPayload(rawToken).encode();

    // ── 2. Guest scans QR code and joins ──
    await guest.controller.joinFromScan(qrPayload);

    expect(guest.controller.state.isSharing, isTrue);
    expect(guest.controller.state.isHost, isFalse);
    expect(guest.controller.state.buddySessionId, host.controller.state.buddySessionId);

    // Verify Guest auto-created active workout session
    final guestActiveWorkouts = await (guest.db.select(guest.db.workoutSessions)
          ..where((t) => t.endedAt.isNull()))
        .get();
    expect(guestActiveWorkouts, hasLength(1));
    final guestWorkoutId = guestActiveWorkouts.single.id;
    expect(guestActiveWorkouts.single.buddySessionId, host.controller.state.buddySessionId);

    // Senders for both devices
    final hostSender = host.makeSender(hostWorkoutId);
    final guestSender = guest.makeSender(guestWorkoutId);

    // ── 3. Host adds "Bench Press" with scope: both ──
    final hostBenchId = await host.getCatalogIdBySlug('bench-press');
    await hostSender.addExercise(
      exerciseId: hostBenchId,
      equipmentVariant: 'barbell',
      scope: BuddyScope.both,
    );

    // Host has Bench Press
    final hostExercises1 = await host.workouts.getExercisesForSession(hostWorkoutId);
    expect(hostExercises1, hasLength(1));
    expect(hostExercises1.first.id, hostBenchId);

    // Guest receives broadcast and resolves Bench Press
    final guestExercises1 = await guest.workouts.getExercisesForSession(guestWorkoutId);
    final guestBenchId = await guest.getCatalogIdBySlug('bench-press');
    expect(guestExercises1, hasLength(1));
    expect(guestExercises1.first.id, guestBenchId);

    // ── 4. Guest adds "Bicep Curl" with scope: mine ──
    final guestBicepId = await guest.getCatalogIdBySlug('bicep-curl');
    await guestSender.addExercise(
      exerciseId: guestBicepId,
      equipmentVariant: 'dumbbell',
      scope: BuddyScope.mine,
    );

    // Guest has 2 exercises (Bench Press, Bicep Curl)
    final guestExercises2 = await guest.workouts.getExercisesForSession(guestWorkoutId);
    expect(guestExercises2, hasLength(2));

    // Host still has ONLY 1 exercise (Bench Press)
    final hostExercises2 = await host.workouts.getExercisesForSession(hostWorkoutId);
    expect(hostExercises2, hasLength(1));

    // ── 5. Guest logs sets for Bench Press ──
    final guestBenchWorkoutExercises = await (guest.db.select(guest.db.workoutExercises)
          ..where((t) => t.sessionId.equals(guestWorkoutId) & t.exerciseId.equals(guestBenchId)))
        .get();
    final guestBenchWorkoutEx = guestBenchWorkoutExercises.first;

    await guest.db.into(guest.db.setEntries).insert(
      SetEntriesCompanion.insert(
        workoutExerciseId: guestBenchWorkoutEx.id,
        setIndex: 1,
        weightKg: 100.0,
        reps: 8,
        isCompleted: const Value(true),
      ),
    );

    // ── 6. Host removes Bench Press (scope: both) ──
    final hostBenchWorkoutExercises = await (host.db.select(host.db.workoutExercises)
          ..where((t) => t.sessionId.equals(hostWorkoutId) & t.exerciseId.equals(hostBenchId)))
        .get();
    final hostBenchWorkoutEx = hostBenchWorkoutExercises.first;

    await hostSender.removeExercise(
      workoutExerciseId: hostBenchWorkoutEx.id,
      scope: BuddyScope.both,
    );

    // Host no longer has Bench Press
    final hostExercises3 = await host.workouts.getExercisesForSession(hostWorkoutId);
    expect(hostExercises3, isEmpty);

    // Guest receives remove event, BUT because Guest logged completed sets,
    // BUD-06 prevents deletion! Guest keeps Bench Press + Bicep Curl intact.
    final guestExercises3 = await guest.workouts.getExercisesForSession(guestWorkoutId);
    expect(guestExercises3, hasLength(2));
    expect(guestExercises3.any((e) => e.id == guestBenchId), isTrue);

    final guestBenchSets = await (guest.db.select(guest.db.setEntries)
          ..where((t) => t.workoutExerciseId.equals(guestBenchWorkoutEx.id)))
        .get();
    expect(guestBenchSets.any((s) => s.weightKg == 100.0 && s.reps == 8), isTrue);

    // ── 7. Guest leaves session safely ──
    await guest.controller.leave();
    expect(guest.controller.state.isSharing, isFalse);

    // Guest workout is still running solo
    final guestActiveStillRunning = await (guest.db.select(guest.db.workoutSessions)
          ..where((t) => t.id.equals(guestWorkoutId)))
        .getSingle();
    expect(guestActiveStillRunning.endedAt, isNull);

    // Host continues workout solo
    final hostInclineId = await host.getCatalogIdBySlug('incline-dumbbell-press');
    await host.workouts.addExerciseToSession(
      sessionId: hostWorkoutId,
      exerciseId: hostInclineId,
    );
    final hostExercises4 = await host.workouts.getExercisesForSession(hostWorkoutId);
    expect(hostExercises4, hasLength(1));
    expect(hostExercises4.single.id, hostInclineId);
  });
}
