import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:herculex/app/router/routes.dart';
import 'package:herculex/design_system/components/components.dart';
import 'package:herculex/design_system/tokens/tokens.dart';
import 'package:herculex/features/friends/application/friends_providers.dart';
import 'package:herculex/features/friends/presentation/sheets/friend_invite_sheet.dart';
import 'package:herculex/features/friends/presentation/widgets/friend_tile.dart';
import 'package:herculex/features/friends/presentation/widgets/lift_leaderboard_card.dart';

/// Settings → Gym Buddy: friends added by QR or link, a main-lift
/// leaderboard, and a way into each friend's comparison page.
class GymBuddyView extends ConsumerWidget {
  const GymBuddyView({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final available = ref.watch(friendsAvailableProvider);

    return HxScreenShell(
      title: 'Gym Buddy',
      titleIcon: Icons.groups_rounded,
      actions: [
        if (available) ...[
          IconButton(
            tooltip: 'Refresh',
            icon: const Icon(Icons.refresh_rounded),
            onPressed: () => ref.invalidate(friendsListProvider),
          ),
          IconButton(
            tooltip: 'Add friend',
            icon: const Icon(Icons.person_add_alt_1_rounded),
            onPressed: () => FriendInviteSheet.show(context),
          ),
        ],
      ],
      children: [
        if (!available)
          const _SignInCard()
        else ...[
          const _SharingCard(),
          const SizedBox(height: HxSpace.x4),
          ..._friendsSection(context, ref),
        ],
        const SizedBox(height: HxSpace.x8),
      ],
    );
  }

  List<Widget> _friendsSection(BuildContext context, WidgetRef ref) {
    final friendsAsync = ref.watch(friendsListProvider);
    final me = ref.watch(meAsFriendProvider).valueOrNull;

    return friendsAsync.when(
      loading: () => const [
        Padding(
          padding: EdgeInsets.symmetric(vertical: 60),
          child: Center(child: CircularProgressIndicator()),
        ),
      ],
      error: (e, _) => [
        Padding(
          padding: const EdgeInsets.symmetric(vertical: HxSpace.x6),
          child: Text(
            'Could not load your gym buddies. Check your connection.',
            textAlign: TextAlign.center,
            style: TextStyle(color: context.hx.danger),
          ),
        ),
      ],
      data: (friends) {
        if (friends.isEmpty) return const [_EmptyState()];
        return [
          LiftLeaderboardCard(people: [?me, ...friends]),
          const SizedBox(height: HxSpace.x5),
          Text(
            'FRIENDS',
            style: Theme.of(context).textTheme.labelSmall?.copyWith(
              color: context.hx.onSurfaceVariant,
              fontWeight: FontWeight.bold,
              letterSpacing: 0.8,
            ),
          ),
          const SizedBox(height: HxSpace.x2),
          for (final f in friends)
            FriendTile(
              friend: f,
              onTap: () => context.push(AppPaths.friendDetail(f.userId)),
            ),
        ];
      },
    );
  }
}

class _SharingCard extends ConsumerWidget {
  const _SharingCard();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final sharing = ref.watch(friendSharingProvider);
    return HxCard(
      padding: const EdgeInsets.symmetric(
        horizontal: HxSpace.x4,
        vertical: HxSpace.x2,
      ),
      // ListTiles paint on the nearest Material; HxCard's fill would hide it.
      child: Material(
        type: MaterialType.transparency,
        child: SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: const Text('Share my stats with friends'),
          subtitle: const Text(
            'Level, main lifts, recent PRs, goal progress and workouts done '
            'together. Never your raw logs or bodyweight history.',
          ),
          value: sharing,
          onChanged: (v) => ref.read(friendSharingProvider.notifier).set(v),
        ),
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final hx = context.hx;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: HxSpace.x8),
      child: Column(
        children: [
          Icon(Icons.groups_rounded, size: 56, color: hx.onSurfaceVariant),
          const SizedBox(height: HxSpace.x3),
          Text(
            'No gym buddies yet',
            style: theme.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: HxSpace.x2),
          Text(
            'Invite a friend with a QR code or a link, then compare main '
            'lifts, PRs and the workouts you do together.',
            textAlign: TextAlign.center,
            style: theme.textTheme.bodySmall?.copyWith(
              color: hx.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: HxSpace.x4),
          FilledButton.icon(
            icon: const Icon(Icons.person_add_alt_1_rounded),
            label: const Text('Add a friend'),
            onPressed: () => FriendInviteSheet.show(context),
          ),
        ],
      ),
    );
  }
}

class _SignInCard extends StatelessWidget {
  const _SignInCard();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return HxCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Sign in to use Gym Buddy',
            style: theme.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: HxSpace.x2),
          Text(
            'Friends are matched through your Herculex account. Sign in under '
            'Account on the Profile tab, then come back here.',
            style: theme.textTheme.bodyMedium?.copyWith(
              color: context.hx.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }
}
