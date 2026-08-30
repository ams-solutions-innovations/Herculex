import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../app/providers.dart';
import '../../../core/env.dart';
import '../../../data/sync/sync_id_resolver.dart';
import '../../workouts/presentation/workouts_providers.dart';
import '../data/buddy_channel_service.dart';
import '../data/buddy_remote_gateway.dart';
import '../data/buddy_slot_store.dart';
import '../data/unconfigured_buddy_gateway.dart';
import 'buddy_choreography_sender.dart';
import 'buddy_session_controller.dart';
import 'buddy_share_policy.dart';

final syncIdResolverProvider = Provider<SyncIdResolver>((ref) {
  return SyncIdResolver(ref.watch(appDatabaseProvider));
});

final supabaseClientProvider = Provider<SupabaseClient?>((ref) {
  if (!Env.hasSupabase) return null;
  return Supabase.instance.client;
});

/// Degrades instead of throwing when the build has no backend.
///
/// These two used to `throw StateError` from inside `Provider.create`, which
/// surfaces **synchronously out of `ref.watch` during `build`** — and
/// `ActiveWorkoutView` watches [buddySessionControllerProvider], so every
/// credential-less build red-screened on the app's most-used screen. Same
/// no-op idiom as `authServiceProvider`/`syncBackendServiceProvider`.
final buddyGatewayProvider = Provider<BuddyGateway>((ref) {
  final client = ref.watch(supabaseClientProvider);
  if (client == null) return const UnconfiguredBuddyGateway();
  return SupabaseBuddyGateway(client: client);
});

final buddyChannelServiceProvider = Provider<BuddyChannelService>((ref) {
  return BuddyChannelService(
    client: ref.watch(supabaseClientProvider),
    gateway: ref.watch(buddyGatewayProvider),
  );
});

final buddySharePolicyProvider = Provider<BuddySharePolicy>((ref) {
  return BuddySharePolicy(ref.watch(appDatabaseProvider));
});

final buddySlotStoreProvider = Provider.family<BuddySlotStore, String>((
  ref,
  buddySessionId,
) {
  return BuddySlotStore(ref.watch(appDatabaseProvider), buddySessionId);
});

final buddySessionControllerProvider =
    StateNotifierProvider<BuddySessionController, BuddySessionState>((ref) {
      final auth = ref.watch(authSessionProvider).valueOrNull;
      final profile = ref.watch(profileProvider).valueOrNull;

      final controller = BuddySessionController(
        db: ref.watch(appDatabaseProvider),
        gateway: ref.watch(buddyGatewayProvider),
        channelService: ref.watch(buddyChannelServiceProvider),
        workouts: ref.watch(workoutsRepositoryProvider),
        resolver: ref.watch(syncIdResolverProvider),
        currentUserId: auth?.uid ?? '',
        currentDisplayName: profile?.name,
        currentAvatarUrl: null,
      );

      // No `ref.onDispose(controller.dispose)`: StateNotifierProvider already
      // disposes the notifier it created, and StateNotifier.dispose asserts it
      // has not run before — so registering it again is a double dispose that
      // throws on every teardown. It went unnoticed only because
      // `buddyGatewayProvider` used to throw before this line was ever
      // reached in any build without Supabase credentials.
      return controller;
    });

final buddyChoreographySenderProvider = Provider.family<
  BuddyChoreographySender,
  ({String buddySessionId, int localWorkoutSessionId})
>((ref, arg) {
  return BuddyChoreographySender(
    publisher: ref.watch(buddyGatewayProvider),
    slots: ref.watch(buddySlotStoreProvider(arg.buddySessionId)),
    workouts: ref.watch(workoutsRepositoryProvider),
    resolver: ref.watch(syncIdResolverProvider),
    buddySessionId: arg.buddySessionId,
    localWorkoutSessionId: arg.localWorkoutSessionId,
  );
});
