import '../../../data/local/database.dart';
import '../domain/buddy_scope.dart';

/// The resolved scope and UI metadata for a workout action.
class ShareDecision {
  const ShareDecision({
    required this.scope,
    required this.userOverridable,
    this.reason,
  });

  final BuddyScope scope;
  final bool userOverridable;
  final String? reason;
}

/// Evaluates whether a local action should be shared with a buddy, taking into
/// account action defaults, user choices, and hard constraints (such as custom
/// exercises being kept local).
class BuddySharePolicy {
  BuddySharePolicy(this._db);

  final AppDatabase _db;

  Future<ShareDecision> decide({
    required BuddyActionKind kind,
    int? exerciseId,
    BuddyScope? userChoice,
    bool hasActiveBuddySession = true,
  }) async {
    if (!hasActiveBuddySession) {
      return const ShareDecision(
        scope: BuddyScope.mine,
        userOverridable: false,
        reason: null,
      );
    }

    if (exerciseId != null) {
      final exercise = await (_db.select(_db.exerciseCatalog)
            ..where((t) => t.id.equals(exerciseId)))
          .getSingleOrNull();

      if (exercise != null && exercise.isCustom) {
        return const ShareDecision(
          scope: BuddyScope.mine,
          userOverridable: false,
          reason: 'Custom exercises stay on your device and cannot be shared.',
        );
      }
    }

    final effectiveScope = userChoice ?? BuddyScopeDefaults.forAction(kind);
    return ShareDecision(
      scope: effectiveScope,
      userOverridable: true,
      reason: null,
    );
  }
}
