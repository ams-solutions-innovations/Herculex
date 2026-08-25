import 'package:herculex/features/buddy/data/buddy_remote_gateway.dart';
import 'package:herculex/features/buddy/domain/buddy_event.dart';

class FakeBuddyGateway implements BuddyGateway {
  final List<BuddyEvent> events = [];
  final List<
    ({String buddySessionId, BuddyEventKind kind, Map<String, dynamic> payload})
  >
  appends = [];

  int fetchCallCount = 0;
  int joinCallCount = 0;
  final List<int> fetchAfterSeqs = [];
  Object? failWith;
  Object? failJoinWith;
  int _nextSeq = 1;
  final List<BuddyRemoteParticipant> participants = [];

  int get appendCount => appends.length;

  @override
  Future<({String buddySessionId, String joinToken})> createSession({
    required String workoutSessionUuid,
    String? displayName,
    String? avatarUrl,
  }) async {
    if (failWith != null) throw failWith!;
    return (buddySessionId: 'fake-session-123', joinToken: 'fake-token-abc');
  }

  @override
  Future<String> joinSession({
    required String token,
    required String workoutSessionUuid,
    String? displayName,
    String? avatarUrl,
  }) async {
    joinCallCount++;
    if (failJoinWith != null) throw failJoinWith!;
    if (failWith != null) throw failWith!;
    if (token == 'invalid-token') throw const BuddyJoinRejected();
    return 'fake-session-123';
  }

  @override
  Future<int> append({
    required String buddySessionId,
    required BuddyEventKind kind,
    required Map<String, dynamic> payload,
  }) async {
    if (failWith != null) throw failWith!;
    final seq = _nextSeq++;
    final event = BuddyEvent(
      buddySessionId: buddySessionId,
      seq: seq,
      actorUserId: 'fake-user-1',
      kind: kind,
      payload: payload,
    );
    events.add(event);
    appends.add((
      buddySessionId: buddySessionId,
      kind: kind,
      payload: payload,
    ));
    return seq;
  }

  @override
  Future<List<BuddyEvent>> fetchEventsSince({
    required String buddySessionId,
    required int afterSeq,
  }) async {
    if (failWith != null) throw failWith!;
    fetchCallCount++;
    fetchAfterSeqs.add(afterSeq);
    return events
        .where((e) => e.buddySessionId == buddySessionId && e.seq > afterSeq)
        .toList();
  }

  @override
  Future<List<BuddyRemoteParticipant>> fetchParticipants(
    String buddySessionId,
  ) async {
    if (failWith != null) throw failWith!;
    return participants;
  }

  @override
  Future<void> leave(String buddySessionId) async {
    if (failWith != null) throw failWith!;
  }

  @override
  Future<void> endSession(String buddySessionId) async {
    if (failWith != null) throw failWith!;
    await append(
      buddySessionId: buddySessionId,
      kind: BuddyEventKind.sessionEnded,
      payload: {'endedBy': 'fake-user-1'},
    );
  }
}
