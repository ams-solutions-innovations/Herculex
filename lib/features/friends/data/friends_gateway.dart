import 'package:herculex/features/friends/domain/friend_comparison.dart';
import 'package:herculex/features/friends/domain/friend_snapshot.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// The one error an invite can fail with. Like `BuddyJoinRejected`, it never
/// carries the server's reason: "unknown", "expired" and "used" must look the
/// same to the client.
class FriendInviteRejected implements Exception {
  const FriendInviteRejected();

  @override
  String toString() => 'Invalid or expired invite';
}

/// Thrown when the build has no backend or nobody is signed in.
class FriendsUnavailable implements Exception {
  const FriendsUnavailable();

  @override
  String toString() => 'Sign in to use Gym Buddy';
}

abstract interface class FriendsGateway {
  Future<void> upsertProfile({
    required String? displayName,
    required String? avatarId,
    required bool sharingEnabled,
  });

  Future<void> publishSnapshot(FriendSnapshot snapshot);

  /// Every friend with whatever they currently share.
  Future<List<FriendEntry>> fetchFriends();

  /// Mints a single-use invite token.
  Future<String> createInvite();

  /// Returns the new friend's user id.
  Future<String> acceptInvite(String token);

  Future<void> removeFriend(String friendUserId);

  /// Buddy sessions both people joined, by id, with the date.
  Future<Map<String, DateTime>> sharedSessions(String friendUserId);
}

class SupabaseFriendsGateway implements FriendsGateway {
  const SupabaseFriendsGateway(this._client);

  final SupabaseClient _client;

  String get _uid {
    final id = _client.auth.currentUser?.id;
    if (id == null) throw const FriendsUnavailable();
    return id;
  }

  @override
  Future<void> upsertProfile({
    required String? displayName,
    required String? avatarId,
    required bool sharingEnabled,
  }) async {
    await _client.from('friend_profiles').upsert({
      'user_id': _uid,
      'display_name': displayName,
      'avatar_id': avatarId,
      'sharing_enabled': sharingEnabled,
    });
  }

  @override
  Future<void> publishSnapshot(FriendSnapshot snapshot) async {
    await _client.from('friend_snapshots').upsert({
      'user_id': _uid,
      'payload': snapshot.toJson(),
    });
  }

  @override
  Future<List<FriendEntry>> fetchFriends() async {
    final me = _uid;
    // RLS already limits friendships to rows the caller is in.
    final pairs = await _client.from('friendships').select('user_a, user_b');
    final ids = <String>{
      for (final row in pairs)
        row['user_a'] == me ? row['user_b'] as String : row['user_a'] as String,
    };
    if (ids.isEmpty) return const [];

    final profiles = await _client
        .from('friend_profiles')
        .select('user_id, display_name, avatar_id')
        .inFilter('user_id', ids.toList());
    // Rows for friends with sharing off are filtered out by RLS.
    final snapshots = await _client
        .from('friend_snapshots')
        .select('user_id, payload')
        .inFilter('user_id', ids.toList());

    final profileById = {for (final p in profiles) p['user_id'] as String: p};
    final snapshotById = <String, FriendSnapshot>{};
    for (final s in snapshots) {
      final payload = s['payload'];
      if (payload is Map) {
        snapshotById[s['user_id'] as String] = FriendSnapshot.fromJson(
          Map<String, dynamic>.from(payload),
        );
      }
    }

    return [
      for (final id in ids)
        FriendEntry(
          userId: id,
          displayName:
              (profileById[id]?['display_name'] as String?)
                      ?.trim()
                      .isNotEmpty ==
                  true
              ? profileById[id]!['display_name'] as String
              : 'Gym buddy',
          avatarId: profileById[id]?['avatar_id'] as String?,
          snapshot: snapshotById[id],
        ),
    ]..sort((a, b) => a.displayName.compareTo(b.displayName));
  }

  @override
  Future<String> createInvite() async {
    _uid;
    final token = await _client.rpc('friend_create_invite');
    return token as String;
  }

  @override
  Future<String> acceptInvite(String token) async {
    _uid;
    try {
      final friend = await _client.rpc(
        'friend_accept_invite',
        params: {'p_token': token},
      );
      return friend as String;
    } catch (_) {
      // Never forward the server's detail (anti-oracle, as in buddy join).
      throw const FriendInviteRejected();
    }
  }

  @override
  Future<void> removeFriend(String friendUserId) async {
    final me = _uid;
    await _client
        .from('friendships')
        .delete()
        .or(
          'and(user_a.eq.$me,user_b.eq.$friendUserId),'
          'and(user_a.eq.$friendUserId,user_b.eq.$me)',
        );
  }

  @override
  Future<Map<String, DateTime>> sharedSessions(String friendUserId) async {
    _uid;
    final rows = await _client.rpc(
      'friend_shared_sessions',
      params: {'p_friend': friendUserId},
    );
    return {
      for (final r in (rows as List? ?? const []))
        if (r is Map)
          r['buddy_session_id'] as String: DateTime.parse(
            r['joined_at'] as String,
          ).toLocal(),
    };
  }
}

/// No backend in this build: reads are empty, writes are no-ops, and the
/// invite actions say why they cannot work.
class UnconfiguredFriendsGateway implements FriendsGateway {
  const UnconfiguredFriendsGateway();

  @override
  Future<void> upsertProfile({
    required String? displayName,
    required String? avatarId,
    required bool sharingEnabled,
  }) async {}

  @override
  Future<void> publishSnapshot(FriendSnapshot snapshot) async {}

  @override
  Future<List<FriendEntry>> fetchFriends() async => const [];

  @override
  Future<String> createInvite() => Future.error(const FriendsUnavailable());

  @override
  Future<String> acceptInvite(String token) =>
      Future.error(const FriendsUnavailable());

  @override
  Future<void> removeFriend(String friendUserId) async {}

  @override
  Future<Map<String, DateTime>> sharedSessions(String friendUserId) async =>
      const {};
}
