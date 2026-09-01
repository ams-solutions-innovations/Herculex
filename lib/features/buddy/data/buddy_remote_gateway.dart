import 'package:herculex/features/buddy/data/buddy_event_publisher.dart';
import 'package:herculex/features/buddy/domain/buddy_event.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Minimal display identity of a buddy participant, denormalised at join time.
class BuddyRemoteParticipant {
  const BuddyRemoteParticipant({
    required this.buddySessionId,
    required this.userId,
    required this.workoutSessionUuid,
    this.displayName,
    this.avatarUrl,
    required this.joinedAt,
    this.leftAt,
  });

  final String buddySessionId;
  final String userId;
  final String workoutSessionUuid;
  final String? displayName;
  final String? avatarUrl;
  final DateTime joinedAt;
  final DateTime? leftAt;

  factory BuddyRemoteParticipant.fromJson(Map<String, dynamic> json) =>
      BuddyRemoteParticipant(
        buddySessionId: json['buddy_session_id'] as String,
        userId: json['user_id'] as String,
        workoutSessionUuid: json['workout_session_uuid'] as String,
        displayName: json['display_name'] as String?,
        avatarUrl: json['avatar_url'] as String?,
        joinedAt: DateTime.parse(json['joined_at'] as String),
        leftAt: json['left_at'] != null
            ? DateTime.parse(json['left_at'] as String)
            : null,
      );
}

/// The ONE generic failure exception returned to the client when a join is rejected.
/// Intentionally carries no detailed server reason to prevent existence oracle leaks.
class BuddyJoinRejected implements Exception {
  const BuddyJoinRejected([this.message = 'Invalid or expired join code']);

  final String message;

  @override
  String toString() => 'BuddyJoinRejected: $message';
}

/// The typed remote gateway contract for buddy sessions.
abstract interface class BuddyGateway implements BuddyEventPublisher {
  Future<({String buddySessionId, String joinToken})> createSession({
    required String workoutSessionUuid,
    String? displayName,
    String? avatarUrl,
  });

  Future<String> joinSession({
    required String token,
    required String workoutSessionUuid,
    String? displayName,
    String? avatarUrl,
  });

  @override
  Future<int> append({
    required String buddySessionId,
    required BuddyEventKind kind,
    required Map<String, dynamic> payload,
  });

  Future<List<BuddyEvent>> fetchEventsSince({
    required String buddySessionId,
    required int afterSeq,
  });

  Future<List<BuddyRemoteParticipant>> fetchParticipants(String buddySessionId);

  Future<void> leave(String buddySessionId);

  Future<void> endSession(String buddySessionId);
}

/// Production implementation of [BuddyGateway] wrapping [SupabaseClient].
class SupabaseBuddyGateway implements BuddyGateway {
  const SupabaseBuddyGateway({required SupabaseClient client})
    : _client = client;

  final SupabaseClient _client;

  @override
  Future<({String buddySessionId, String joinToken})> createSession({
    required String workoutSessionUuid,
    String? displayName,
    String? avatarUrl,
  }) async {
    final response = await _client.rpc(
      'buddy_create_session',
      params: {
        'p_workout_session_uuid': workoutSessionUuid,
        'p_display_name': displayName,
        'p_avatar_url': avatarUrl,
      },
    );

    final List<dynamic> rows = response is List ? response : [response];
    if (rows.isEmpty) {
      throw StateError('buddy_create_session returned empty result');
    }
    final first = Map<String, dynamic>.from(rows.first as Map);
    return (
      buddySessionId: first['buddy_session_id'] as String,
      joinToken: first['join_token'] as String,
    );
  }

  @override
  Future<String> joinSession({
    required String token,
    required String workoutSessionUuid,
    String? displayName,
    String? avatarUrl,
  }) async {
    try {
      final response = await _client.rpc(
        'buddy_join_session',
        params: {
          'p_token': token,
          'p_workout_session_uuid': workoutSessionUuid,
          'p_display_name': displayName,
          'p_avatar_url': avatarUrl,
        },
      );
      return response.toString();
    } on PostgrestException {
      // Server intentionally returns one generic error for 5 causes.
      // Do not forward server detail into client fields (anti-oracle defense).
      throw const BuddyJoinRejected();
    } catch (e) {
      if (e is BuddyJoinRejected) rethrow;
      throw const BuddyJoinRejected();
    }
  }

  @override
  Future<int> append({
    required String buddySessionId,
    required BuddyEventKind kind,
    required Map<String, dynamic> payload,
  }) async {
    final response = await _client.rpc(
      'buddy_append_event',
      params: {
        'p_buddy_session_id': buddySessionId,
        'p_kind': kind.wireName,
        'p_payload': payload,
      },
    );
    if (response is int) return response;
    return int.parse(response.toString());
  }

  @override
  Future<List<BuddyEvent>> fetchEventsSince({
    required String buddySessionId,
    required int afterSeq,
  }) async {
    final response = await _client
        .from('buddy_session_events')
        .select()
        .eq('buddy_session_id', buddySessionId)
        .gt('seq', afterSeq)
        .order('seq', ascending: true);

    final list = response as List<dynamic>;
    return list
        .map(
          (row) => BuddyEvent.fromLogRow(Map<String, dynamic>.from(row as Map)),
        )
        .toList();
  }

  @override
  Future<List<BuddyRemoteParticipant>> fetchParticipants(
    String buddySessionId,
  ) async {
    final response = await _client
        .from('buddy_participants')
        .select()
        .eq('buddy_session_id', buddySessionId);

    final list = response as List<dynamic>;
    return list
        .map(
          (row) => BuddyRemoteParticipant.fromJson(
            Map<String, dynamic>.from(row as Map),
          ),
        )
        .toList();
  }

  @override
  Future<void> leave(String buddySessionId) async {
    final uid = _client.auth.currentUser?.id;
    if (uid == null) return;

    await _client
        .from('buddy_participants')
        .update({'left_at': DateTime.now().toUtc().toIso8601String()})
        .eq('buddy_session_id', buddySessionId)
        .eq('user_id', uid);
  }

  @override
  Future<void> endSession(String buddySessionId) async {
    final uid = _client.auth.currentUser?.id ?? '';
    await append(
      buddySessionId: buddySessionId,
      kind: BuddyEventKind.sessionEnded,
      payload: {'endedBy': uid},
    );
  }
}
