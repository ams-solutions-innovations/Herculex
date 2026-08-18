import 'package:herculex/features/buddy/data/buddy_event_publisher.dart';
import 'package:herculex/features/buddy/domain/buddy_event.dart';

/// In-memory [BuddyEventPublisher] for tests — mirrors
/// `test/sync/fake_sync_backend_service.dart`'s doctrine: fake only the
/// network-facing seam, run the real buddy logic against it. Has no logic
/// of its own beyond recording what it was called with.
class FakeBuddyPublisher implements BuddyEventPublisher {
  /// Every call, in call order.
  final List<
    ({String buddySessionId, BuddyEventKind kind, Map<String, dynamic> payload})
  >
  appends = [];

  /// When non-null, [append] throws this instead of recording — the seam
  /// 11-08 uses to test the optimistic-rollback path.
  Object? failWith;

  int _nextSeq = 1;

  int get appendCount => appends.length;

  @override
  Future<int> append({
    required String buddySessionId,
    required BuddyEventKind kind,
    required Map<String, dynamic> payload,
  }) async {
    if (failWith != null) {
      throw failWith!;
    }
    appends.add((
      buddySessionId: buddySessionId,
      kind: kind,
      payload: payload,
    ));
    return _nextSeq++;
  }
}
