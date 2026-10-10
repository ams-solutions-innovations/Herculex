import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:herculex/app/providers.dart';
import 'package:herculex/features/analytics/application/analytics_providers.dart';
import 'package:herculex/features/buddy/application/buddy_providers.dart';
import 'package:herculex/features/dashboard/application/dashboard_providers.dart';
import 'package:herculex/features/friends/data/friends_gateway.dart';
import 'package:herculex/features/friends/domain/friend_comparison.dart';
import 'package:herculex/features/friends/domain/friend_snapshot.dart';
import 'package:herculex/features/friends/domain/friend_snapshot_builder.dart';
import 'package:herculex/features/gamification/application/gamification_providers.dart';
import 'package:herculex/features/physique/application/goal_target_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

final friendsGatewayProvider = Provider<FriendsGateway>((ref) {
  final client = ref.watch(supabaseClientProvider);
  if (client == null) return const UnconfiguredFriendsGateway();
  return SupabaseFriendsGateway(client);
});

/// Whether friends may see this user's stats. On by default — adding a
/// friend is already an opt-in — and switchable on the Gym Buddy page.
class FriendSharingNotifier extends Notifier<bool> {
  static const prefsKey = 'friends_sharing_enabled_v1';

  SharedPreferences get _prefs => ref.read(sharedPreferencesProvider);

  @override
  bool build() => _prefs.getBool(prefsKey) ?? true;

  Future<void> set(bool enabled) async {
    state = enabled;
    await _prefs.setBool(prefsKey, enabled);
    await ref.read(friendSnapshotPublisherProvider).publishNow();
  }
}

final friendSharingProvider = NotifierProvider<FriendSharingNotifier, bool>(
  FriendSharingNotifier.new,
);

/// Signed in, with a backend: the only state in which Gym Buddy works.
final friendsAvailableProvider = Provider<bool>((ref) {
  if (ref.watch(supabaseClientProvider) == null) return false;
  return ref.watch(authSessionProvider).valueOrNull != null;
});

/// What this user publishes, built from local data. Also the "me" row on the
/// Gym Buddy page, so it works before anything reaches the server.
final myFriendSnapshotProvider = FutureProvider<FriendSnapshot>((ref) async {
  final training = await ref.watch(trainingSnapshotProvider.future);
  final strength = await ref.watch(strengthAssessmentProvider.future);
  final level = ref.watch(levelProgressProvider).valueOrNull;
  final profile = ref.watch(profileProvider).valueOrNull;
  final goal = ref.watch(goalTargetProvider);
  final bodyweights =
      ref.watch(bodyweightHistoryProvider).valueOrNull ?? const [];
  final now = ref.watch(clockProvider).now();

  final current = bodyweights.isNotEmpty
      ? bodyweights.last.value
      : profile?.weightKg;
  final start = bodyweights.isNotEmpty ? bodyweights.first.value : current;

  return const FriendSnapshotBuilder().build(
    training: training,
    strength: strength,
    levelTitle: level?.level.title ?? '',
    completedWorkouts: level?.completedWorkouts ?? 0,
    asOf: now,
    goalStartKg: start,
    currentBodyweightKg: current,
    goalTargetKg: goal.dreamKg ?? goal.targetKg,
  );
});

/// Friends and whatever each one shares. Refresh with `ref.invalidate`.
final friendsListProvider = FutureProvider<List<FriendEntry>>((ref) async {
  if (!ref.watch(friendsAvailableProvider)) return const [];
  return ref.watch(friendsGatewayProvider).fetchFriends();
});

/// The user as a [FriendEntry], for leaderboards next to their friends.
final meAsFriendProvider = FutureProvider<FriendEntry>((ref) async {
  final snapshot = await ref.watch(myFriendSnapshotProvider.future);
  final profile = ref.watch(profileProvider).valueOrNull;
  return FriendEntry(
    userId: ref.watch(authSessionProvider).valueOrNull?.uid ?? 'me',
    displayName: 'You',
    avatarId: profile?.avatarId,
    snapshot: snapshot,
    isMe: true,
  );
});

final friendSharedSessionsProvider =
    FutureProvider.family<Map<String, DateTime>, String>((ref, friendId) {
      if (!ref.watch(friendsAvailableProvider)) return const {};
      return ref.watch(friendsGatewayProvider).sharedSessions(friendId);
    });

/// Pushes the profile row and the snapshot to the server.
class FriendSnapshotPublisher {
  FriendSnapshotPublisher(this._ref);

  final Ref _ref;

  /// Publishes when signed in. With sharing off only the profile row is
  /// updated (its flag is what hides the snapshot); the stale snapshot is
  /// left in place but unreadable to friends.
  Future<void> publishNow() async {
    if (!_ref.read(friendsAvailableProvider)) return;
    final gateway = _ref.read(friendsGatewayProvider);
    final sharing = _ref.read(friendSharingProvider);
    final profile = _ref.read(profileProvider).valueOrNull;
    try {
      await gateway.upsertProfile(
        displayName: profile?.name,
        avatarId: profile?.avatarId,
        sharingEnabled: sharing,
      );
      if (!sharing) return;
      final snapshot = await _ref.read(myFriendSnapshotProvider.future);
      await gateway.publishSnapshot(snapshot);
    } catch (_) {
      // Best effort: offline now means the next change publishes instead.
    }
  }
}

final friendSnapshotPublisherProvider = Provider<FriendSnapshotPublisher>(
  FriendSnapshotPublisher.new,
);

/// Watched once from the app root: republishes a few seconds after the local
/// snapshot changes (a finished workout, a new bodyweight) or the user signs
/// in. The debounce folds a burst of provider updates into one upload.
final friendSnapshotAutoPublishProvider = Provider<void>((ref) {
  // Signed out: build nothing. Signing in rebuilds this provider.
  if (!ref.watch(friendsAvailableProvider)) return;

  Timer? debounce;
  void schedule() {
    debounce?.cancel();
    debounce = Timer(
      const Duration(seconds: 5),
      () => unawaited(ref.read(friendSnapshotPublisherProvider).publishNow()),
    );
  }

  schedule();
  ref
    ..listen(myFriendSnapshotProvider, (_, next) {
      if (next.hasValue) schedule();
    })
    ..onDispose(() => debounce?.cancel());
});
