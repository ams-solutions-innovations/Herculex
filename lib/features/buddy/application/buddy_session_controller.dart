import 'dart:async';

import 'package:drift/drift.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import '../../../data/local/database.dart';
import '../../../data/sync/sync_id_resolver.dart';
import '../../workouts/data/workouts_repository.dart';
import '../data/buddy_channel_service.dart';
import '../data/buddy_choreography_applier.dart';
import '../data/buddy_remote_gateway.dart';
import '../data/buddy_slot_store.dart';
import '../domain/buddy_event.dart';
import '../domain/buddy_join_payload.dart';

class BuddyParticipant {
  const BuddyParticipant({
    required this.userId,
    required this.displayName,
    this.avatarUrl,
  });

  final String userId;
  final String displayName;
  final String? avatarUrl;
}

class BuddySessionState {
  const BuddySessionState({
    this.buddySessionId,
    this.pendingJoinToken,
    this.partner,
    this.isHost = false,
    this.isLive = false,
    this.notice,
  });

  final String? buddySessionId;
  final String? pendingJoinToken;
  final BuddyParticipant? partner;
  final bool isHost;
  final bool isLive;
  final String? notice;

  bool get isSharing => buddySessionId != null;

  BuddySessionState copyWith({
    String? Function()? buddySessionId,
    String? Function()? pendingJoinToken,
    BuddyParticipant? Function()? partner,
    bool? isHost,
    bool? isLive,
    String? Function()? notice,
  }) {
    return BuddySessionState(
      buddySessionId: buddySessionId != null
          ? buddySessionId()
          : this.buddySessionId,
      pendingJoinToken: pendingJoinToken != null
          ? pendingJoinToken()
          : this.pendingJoinToken,
      partner: partner != null ? partner() : this.partner,
      isHost: isHost ?? this.isHost,
      isLive: isLive ?? this.isLive,
      notice: notice != null ? notice() : this.notice,
    );
  }
}

class BuddySessionController extends StateNotifier<BuddySessionState> {
  BuddySessionController({
    required AppDatabase db,
    required BuddyGateway gateway,
    required BuddyChannelService channelService,
    required WorkoutsRepository workouts,
    required SyncIdResolver resolver,
    required String currentUserId,
    String? currentDisplayName,
    String? currentAvatarUrl,
  }) : _db = db,
       _gateway = gateway,
       _channelService = channelService,
       _workouts = workouts,
       _resolver = resolver,
       _currentUserId = currentUserId,
       _currentDisplayName = currentDisplayName,
       _currentAvatarUrl = currentAvatarUrl,
       super(const BuddySessionState());

  final AppDatabase _db;
  final BuddyGateway _gateway;
  final BuddyChannelService _channelService;
  final WorkoutsRepository _workouts;
  final SyncIdResolver _resolver;
  final String _currentUserId;
  final String? _currentDisplayName;
  final String? _currentAvatarUrl;

  StreamSubscription<List<String>>? _presenceSubscription;

  Future<String> hostFromActiveWorkout() async {
    final activeSession =
        await (_db.select(_db.workoutSessions)
              ..where((t) => t.endedAt.isNull())
              ..orderBy([
                (t) => OrderingTerm(
                  expression: t.startedAt,
                  mode: OrderingMode.desc,
                ),
              ])
              ..limit(1))
            .getSingleOrNull();

    if (activeSession == null) {
      throw StateError(
        'No active workout session to host a Gym Buddy session from',
      );
    }

    final sessionUuid = activeSession.sessionUuid ?? const Uuid().v4();

    final created = await _gateway.createSession(
      workoutSessionUuid: sessionUuid,
      displayName: _currentDisplayName,
      avatarUrl: _currentAvatarUrl,
    );

    final buddySessionId = created.buddySessionId;
    final joinToken = created.joinToken;

    await (_db.update(
      _db.workoutSessions,
    )..where((t) => t.id.equals(activeSession.id))).write(
      WorkoutSessionsCompanion(
        buddySessionId: Value(buddySessionId),
        sessionUuid: Value(sessionUuid),
      ),
    );

    await _db
        .into(_db.buddySessionsLocal)
        .insertOnConflictUpdate(
          BuddySessionsLocalCompanion(
            buddySessionId: Value(buddySessionId),
            workoutSessionId: Value(activeSession.id),
            role: const Value('host'),
            lastSeenSeq: const Value(0),
            joinedAt: Value(DateTime.now()),
          ),
        );

    final slots = BuddySlotStore(_db, buddySessionId);
    final applier = BuddyChoreographyApplier(
      db: _db,
      workouts: _workouts,
      resolver: _resolver,
      slots: slots,
      localWorkoutSessionId: activeSession.id,
      onNotice: (outcome, msg) {
        state = state.copyWith(notice: () => msg);
      },
    );

    _presenceSubscription?.cancel();
    _presenceSubscription = _channelService.presentUserIds.listen((ids) {
      final otherIds = ids.where((id) => id != _currentUserId).toList();
      if (otherIds.isNotEmpty) {
        state = state.copyWith(
          pendingJoinToken: () => null,
          partner: () => BuddyParticipant(
            userId: otherIds.first,
            displayName: 'Gym Buddy',
          ),
          isLive: true,
        );
      }
    });

    await _channelService.connect(
      buddySessionId: buddySessionId,
      lastSeenSeq: 0,
      userId: _currentUserId,
      displayName: _currentDisplayName,
      apply: (e) async {
        if (e.kind == BuddyEventKind.sessionEnded) {
          await _handleSessionEnded();
          return;
        }
        await applier.apply(e);
      },
      commitSeq: (seq) async {
        await (_db.update(_db.buddySessionsLocal)
              ..where((t) => t.buddySessionId.equals(buddySessionId)))
            .write(BuddySessionsLocalCompanion(lastSeenSeq: Value(seq)));
      },
    );

    state = BuddySessionState(
      buddySessionId: buddySessionId,
      pendingJoinToken: joinToken,
      isHost: true,
      isLive: true,
    );

    return joinToken;
  }

  Future<void> joinFromScan(String rawPayload) async {
    final payload = BuddyJoinPayload.tryDecode(rawPayload);
    if (payload == null) {
      throw const BuddyJoinRejected('Invalid or expired join code');
    }

    var activeSession =
        await (_db.select(_db.workoutSessions)
              ..where((t) => t.endedAt.isNull())
              ..orderBy([
                (t) => OrderingTerm(
                  expression: t.startedAt,
                  mode: OrderingMode.desc,
                ),
              ])
              ..limit(1))
            .getSingleOrNull();

    int workoutSessionId;
    String sessionUuid;
    bool autoCreated = false;

    if (activeSession != null) {
      workoutSessionId = activeSession.id;
      sessionUuid = activeSession.sessionUuid ?? const Uuid().v4();
    } else {
      workoutSessionId = await _workouts.startSession();
      activeSession = await (_db.select(
        _db.workoutSessions,
      )..where((t) => t.id.equals(workoutSessionId))).getSingle();
      sessionUuid = activeSession.sessionUuid ?? const Uuid().v4();
      autoCreated = true;
    }

    String buddySessionId;
    try {
      buddySessionId = await _gateway.joinSession(
        token: payload.token,
        workoutSessionUuid: sessionUuid,
        displayName: _currentDisplayName,
        avatarUrl: _currentAvatarUrl,
      );
    } catch (e) {
      if (autoCreated) {
        await _workouts.deleteSession(workoutSessionId);
      }
      rethrow;
    }

    await (_db.update(
      _db.workoutSessions,
    )..where((t) => t.id.equals(workoutSessionId))).write(
      WorkoutSessionsCompanion(
        buddySessionId: Value(buddySessionId),
        sessionUuid: Value(sessionUuid),
      ),
    );

    await _db
        .into(_db.buddySessionsLocal)
        .insertOnConflictUpdate(
          BuddySessionsLocalCompanion(
            buddySessionId: Value(buddySessionId),
            workoutSessionId: Value(workoutSessionId),
            role: const Value('guest'),
            lastSeenSeq: const Value(0),
            joinedAt: Value(DateTime.now()),
          ),
        );

    final slots = BuddySlotStore(_db, buddySessionId);
    final applier = BuddyChoreographyApplier(
      db: _db,
      workouts: _workouts,
      resolver: _resolver,
      slots: slots,
      localWorkoutSessionId: workoutSessionId,
      onNotice: (outcome, msg) {
        state = state.copyWith(notice: () => msg);
      },
    );

    _presenceSubscription?.cancel();
    _presenceSubscription = _channelService.presentUserIds.listen((ids) {
      final otherIds = ids.where((id) => id != _currentUserId).toList();
      if (otherIds.isNotEmpty) {
        state = state.copyWith(
          partner: () => BuddyParticipant(
            userId: otherIds.first,
            displayName: 'Gym Buddy',
          ),
          isLive: true,
        );
      }
    });

    await _channelService.connect(
      buddySessionId: buddySessionId,
      lastSeenSeq: 0,
      userId: _currentUserId,
      displayName: _currentDisplayName,
      apply: (e) async {
        if (e.kind == BuddyEventKind.sessionEnded) {
          await _handleSessionEnded();
          return;
        }
        await applier.apply(e);
      },
      commitSeq: (seq) async {
        await (_db.update(_db.buddySessionsLocal)
              ..where((t) => t.buddySessionId.equals(buddySessionId)))
            .write(BuddySessionsLocalCompanion(lastSeenSeq: Value(seq)));
      },
    );

    state = BuddySessionState(
      buddySessionId: buddySessionId,
      isHost: false,
      isLive: true,
      partner: const BuddyParticipant(userId: 'host', displayName: 'Gym Buddy'),
    );
  }

  Future<void> leave() async {
    if (state.buddySessionId == null) return;
    final sessionId = state.buddySessionId!;

    _presenceSubscription?.cancel();
    _presenceSubscription = null;

    await _channelService.disconnect();

    await (_db.update(_db.buddySessionsLocal)
          ..where((t) => t.buddySessionId.equals(sessionId)))
        .write(BuddySessionsLocalCompanion(endedAt: Value(DateTime.now())));

    state = const BuddySessionState();
  }

  Future<void> endForEveryone() async {
    if (state.buddySessionId == null) return;
    if (state.isHost) {
      try {
        await _gateway.append(
          buddySessionId: state.buddySessionId!,
          kind: BuddyEventKind.sessionEnded,
          payload: {'endedBy': _currentUserId},
        );
      } catch (_) {}
    }
    await leave();
  }

  Future<void> _handleSessionEnded() async {
    final sessionId = state.buddySessionId;
    _presenceSubscription?.cancel();
    _presenceSubscription = null;

    await _channelService.disconnect();

    if (sessionId != null) {
      await (_db.update(_db.buddySessionsLocal)
            ..where((t) => t.buddySessionId.equals(sessionId)))
          .write(BuddySessionsLocalCompanion(endedAt: Value(DateTime.now())));
    }

    state = state.copyWith(
      buddySessionId: () => null,
      pendingJoinToken: () => null,
      partner: () => null,
      isLive: false,
      notice: () => 'The host ended the shared session.',
    );
  }

  @override
  void dispose() {
    _presenceSubscription?.cancel();
    _presenceSubscription = null;
    super.dispose();
  }
}
