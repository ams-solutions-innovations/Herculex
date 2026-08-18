/// Whether a buddy action should be broadcast to the paired partner or kept
/// local to the acting device.
///
/// **Deliberately outside the buddy transport module.** Scope is a
/// caller-side control-flow decision — it decides *whether* to call
/// `BuddyEventPublisher.append` at all, never a value carried inside the
/// event payload. See `11-RESEARCH.md` § Pitfall 5 and
/// `lib/features/buddy/domain/buddy_event.dart`'s header for the boundary
/// this file must never cross.
enum BuddyScope {
  /// Broadcast to both devices — the default for additive/structural
  /// changes the partner should see.
  both,

  /// Applies only to the acting device — the default for removing an
  /// exercise, which should not silently delete it for the partner too.
  mine,
}

/// The four user-initiated actions a scope default applies to.
enum BuddyActionKind { add, remove, reorder, replace }

/// Sticky per-action scope defaults. "Sticky" because the UI remembers the
/// user's last explicit choice per action kind within a session rather than
/// re-prompting every time — that behavior lives in a later plan; this file
/// only owns the starting default each action kind opens with.
abstract final class BuddyScopeDefaults {
  /// The default [BuddyScope] for [kind]:
  /// - `add`, `reorder`, `replace` default to [BuddyScope.both] — the
  ///   partner should see structural changes to the shared workout.
  /// - `remove` defaults to [BuddyScope.mine] — removing an exercise should
  ///   not silently delete it from the partner's view too.
  static BuddyScope forAction(BuddyActionKind kind) {
    switch (kind) {
      case BuddyActionKind.remove:
        return BuddyScope.mine;
      case BuddyActionKind.add:
      case BuddyActionKind.reorder:
      case BuddyActionKind.replace:
        return BuddyScope.both;
    }
  }
}
