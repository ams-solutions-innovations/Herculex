import 'package:herculex/features/buddy/data/buddy_remote_gateway.dart';
import 'package:herculex/features/buddy/domain/buddy_event.dart';

/// Stand-in [BuddyGateway] for builds without Supabase credentials.
///
/// Buddy training is the app's only genuinely server-side feature, so its
/// providers used to `throw StateError('Supabase is not configured in this
/// build')` when `Env.hasSupabase` was false. That throw happened inside
/// `Provider.create`, which propagates **synchronously out of `ref.watch`
/// during `build`** — and `ActiveWorkoutView` watches
/// `buddySessionControllerProvider`, so the app's most-used screen died on
/// arrival in any credential-less build (the "local-only, no backend" launch
/// config, a bare `flutter run`, and every widget test).
///
/// Same idiom as [UnconfiguredAuthService] and [NoopSyncBackendService]: reads
/// degrade to empty, and the actions a user can actually trigger fail with a
/// message that says what to do about it.
class UnconfiguredBuddyGateway implements BuddyGateway {
  const UnconfiguredBuddyGateway();

  static const _message =
      'Training with a buddy needs a backend. Rebuild with '
      '--dart-define=SUPABASE_URL=... --dart-define=SUPABASE_ANON_KEY=...';

  @override
  Future<({String buddySessionId, String joinToken})> createSession({
    required String workoutSessionUuid,
    String? displayName,
    String? avatarUrl,
  }) async => throw UnsupportedError(_message);

  @override
  Future<String> joinSession({
    required String token,
    required String workoutSessionUuid,
    String? displayName,
    String? avatarUrl,
  }) async => throw UnsupportedError(_message);

  @override
  Future<int> append({
    required String buddySessionId,
    required BuddyEventKind kind,
    required Map<String, dynamic> payload,
  }) async => throw UnsupportedError(_message);

  @override
  Future<List<BuddyEvent>> fetchEventsSince({
    required String buddySessionId,
    required int afterSeq,
  }) async => const [];

  @override
  Future<List<BuddyRemoteParticipant>> fetchParticipants(
    String buddySessionId,
  ) async => const [];

  // Leaving/ending a session that could never have started is a no-op, not an
  // error — these run on teardown paths that must not throw.
  @override
  Future<void> leave(String buddySessionId) async {}

  @override
  Future<void> endSession(String buddySessionId) async {}
}
