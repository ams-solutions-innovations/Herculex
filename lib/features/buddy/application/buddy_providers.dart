import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../app/providers.dart';
import '../../../core/env.dart';
import '../../../data/sync/sync_id_resolver.dart';
import '../../workouts/presentation/workouts_providers.dart';
import '../data/buddy_channel_service.dart';
import '../data/buddy_remote_gateway.dart';
import '../data/buddy_slot_store.dart';
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

final buddyGatewayProvider = Provider<BuddyGateway>((ref) {
  final client = ref.watch(supabaseClientProvider);
  if (client == null) {
    throw StateError('Supabase is not configured in this build');
  }
  return SupabaseBuddyGateway(client: client);
});

final buddyChannelServiceProvider = Provider<BuddyChannelService>((ref) {
  final client = ref.watch(supabaseClientProvider);
  if (client == null) {
    throw StateError('Supabase is not configured in this build');
  }
  return BuddyChannelService(
    client: client,
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

      ref.onDispose(controller.dispose);
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
