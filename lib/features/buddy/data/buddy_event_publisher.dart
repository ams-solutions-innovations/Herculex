import '../domain/buddy_event.dart';

/// The network-facing seam between buddy live-workout logic and whatever
/// actually appends an event to a session's shared log (Supabase broadcast
/// plus the durable log table, in the real implementation).
///
/// Part of the buddy transport module along with everything else under
/// `lib/features/buddy/data/` — see
/// `test/buddy/buddy_scope_boundary_test.dart` for the structural gate this
/// file must keep satisfying. There is no visibility-control parameter here;
/// that decision is made by the caller before it ever reaches this
/// interface.
abstract interface class BuddyEventPublisher {
  /// Appends one event to [buddySessionId]'s log and returns the resulting
  /// `seq`.
  Future<int> append({
    required String buddySessionId,
    required BuddyEventKind kind,
    required Map<String, dynamic> payload,
  });
}
