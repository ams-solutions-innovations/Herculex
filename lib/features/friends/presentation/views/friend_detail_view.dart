import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:herculex/core/utils/units.dart';
import 'package:herculex/design_system/components/components.dart';
import 'package:herculex/design_system/tokens/tokens.dart';
import 'package:herculex/features/friends/application/friends_providers.dart';
import 'package:herculex/features/friends/domain/friend_comparison.dart';
import 'package:herculex/features/friends/domain/friend_snapshot.dart';
import 'package:herculex/features/friends/presentation/widgets/lift_leaderboard_card.dart';
import 'package:herculex/features/gamification/domain/strength_standards.dart';
import 'package:herculex/features/profile/presentation/widgets/greek_avatar_badge.dart';
import 'package:intl/intl.dart';

/// You vs one friend: main lifts side by side, goal progress, their recent
/// PRs and the workouts you did together.
class FriendDetailView extends ConsumerWidget {
  const FriendDetailView({super.key, required this.friendId});

  final String friendId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final friends = ref.watch(friendsListProvider);
    final me = ref.watch(meAsFriendProvider).valueOrNull;
    final friend = friends.valueOrNull
        ?.where((f) => f.userId == friendId)
        .firstOrNull;

    return HxScreenShell(
      title: friend?.displayName ?? 'Gym buddy',
      actions: [
        if (friend != null)
          IconButton(
            tooltip: 'Remove friend',
            icon: const Icon(Icons.person_remove_rounded),
            onPressed: () => _confirmRemove(context, ref, friend),
          ),
      ],
      children: [
        if (friends.isLoading && friend == null)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 80),
            child: Center(child: CircularProgressIndicator()),
          )
        else if (friend == null)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 60),
            child: Center(
              child: Text('This friend is no longer on your list.'),
            ),
          )
        else ...[
          _VersusHeader(me: me, friend: friend),
          const SizedBox(height: HxSpace.x4),
          if (friend.snapshot == null)
            HxCard(
              child: Text(
                '${friend.displayName} is not sharing stats right now.',
                style: TextStyle(color: context.hx.onSurfaceVariant),
              ),
            )
          else ...[
            _MainLiftsCard(me: me?.snapshot, them: friend.snapshot!),
            const SizedBox(height: HxSpace.x4),
            _GoalCard(me: me?.snapshot?.goal, them: friend.snapshot!.goal),
            _RecentPrsCard(
              name: friend.displayName,
              snapshot: friend.snapshot!,
            ),
          ],
          _SharedSessionsCard(me: me?.snapshot, friend: friend),
        ],
        const SizedBox(height: HxSpace.x8),
      ],
    );
  }

  Future<void> _confirmRemove(
    BuildContext context,
    WidgetRef ref,
    FriendEntry friend,
  ) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Remove ${friend.displayName}?'),
        content: const Text(
          'You will stop seeing each other\'s stats. You can add each other '
          'again with a new invite.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Remove'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    await ref.read(friendsGatewayProvider).removeFriend(friend.userId);
    ref.invalidate(friendsListProvider);
    if (context.mounted) context.pop();
  }
}

class _VersusHeader extends StatelessWidget {
  const _VersusHeader({required this.me, required this.friend});

  final FriendEntry? me;
  final FriendEntry friend;

  @override
  Widget build(BuildContext context) {
    Widget side(FriendEntry? e, String fallback) {
      final theme = Theme.of(context);
      return Expanded(
        child: Column(
          children: [
            GreekAvatarBadge(
              avatarId: e?.avatarId,
              fallbackName: e?.displayName ?? fallback,
              size: 64,
            ),
            const SizedBox(height: HxSpace.x2),
            Text(
              e?.displayName ?? fallback,
              style: theme.textTheme.titleSmall?.copyWith(
                fontWeight: FontWeight.w700,
              ),
            ),
            if (e?.snapshot case final s?) ...[
              Text(
                s.levelTitle,
                style: theme.textTheme.labelMedium?.copyWith(
                  color: context.hx.primary,
                ),
              ),
              Text(
                '${s.completedWorkouts} workouts',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: context.hx.onSurfaceVariant,
                ),
              ),
            ],
          ],
        ),
      );
    }

    return HxCard(
      child: Row(
        children: [
          side(me, 'You'),
          Text(
            'VS',
            style: Theme.of(context).textTheme.titleLarge?.copyWith(
              fontWeight: FontWeight.w900,
              color: context.hx.onSurfaceVariant,
            ),
          ),
          side(friend, 'Friend'),
        ],
      ),
    );
  }
}

class _MainLiftsCard extends ConsumerWidget {
  const _MainLiftsCard({required this.me, required this.them});

  final FriendSnapshot? me;
  final FriendSnapshot them;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final units = ref.watch(weightFormatProvider);
    final theme = Theme.of(context);
    final hx = context.hx;
    final lifts = [
      for (final l in StrengthLift.values)
        if (me?.liftOf(l) != null || them.liftOf(l) != null) l,
    ];
    if (lifts.isEmpty) return const SizedBox.shrink();

    String cell(FriendLift? l) => l == null ? '—' : formatFriendLift(l, units);
    double score(FriendLift? l) => l == null ? -1 : (l.e1rmKg ?? l.value);

    return HxCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Main lifts',
            style: theme.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: HxSpace.x3),
          for (final lift in lifts)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: HxSpace.x1 + 2),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      cell(me?.liftOf(lift)),
                      style: TextStyle(
                        fontWeight: FontWeight.w700,
                        color:
                            score(me?.liftOf(lift)) >= score(them.liftOf(lift))
                            ? hx.primary
                            : null,
                      ),
                    ),
                  ),
                  Expanded(
                    flex: 2,
                    child: Text(
                      lift.label,
                      textAlign: TextAlign.center,
                      style: TextStyle(color: hx.onSurfaceVariant),
                    ),
                  ),
                  Expanded(
                    child: Text(
                      cell(them.liftOf(lift)),
                      textAlign: TextAlign.end,
                      style: TextStyle(
                        fontWeight: FontWeight.w700,
                        color:
                            score(them.liftOf(lift)) > score(me?.liftOf(lift))
                            ? hx.primary
                            : null,
                      ),
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

class _GoalCard extends StatelessWidget {
  const _GoalCard({required this.me, required this.them});

  final FriendGoal? me;
  final FriendGoal? them;

  @override
  Widget build(BuildContext context) {
    if (me == null && them == null) return const SizedBox.shrink();
    final theme = Theme.of(context);

    Widget bar(String who, FriendGoal? g) => Padding(
      padding: const EdgeInsets.only(top: HxSpace.x3),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(who),
              Text(
                g == null ? 'No goal set' : '${(g.progress * 100).round()}%',
                style: const TextStyle(fontWeight: FontWeight.w700),
              ),
            ],
          ),
          const SizedBox(height: HxSpace.x1),
          ClipRRect(
            borderRadius: HxRadius.pillAll,
            child: LinearProgressIndicator(
              value: g?.progress ?? 0,
              minHeight: 8,
              backgroundColor: context.hx.surfaceVariant,
            ),
          ),
        ],
      ),
    );

    return Padding(
      padding: const EdgeInsets.only(bottom: HxSpace.x4),
      child: HxCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Closest to the goal',
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w800,
              ),
            ),
            bar('You', me),
            bar('Them', them),
          ],
        ),
      ),
    );
  }
}

class _RecentPrsCard extends ConsumerWidget {
  const _RecentPrsCard({required this.name, required this.snapshot});

  final String name;
  final FriendSnapshot snapshot;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (snapshot.recentPrs.isEmpty) return const SizedBox.shrink();
    final units = ref.watch(weightFormatProvider);
    final theme = Theme.of(context);
    final date = DateFormat.MMMd();
    return Padding(
      padding: const EdgeInsets.only(bottom: HxSpace.x4),
      child: HxCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '$name\'s recent PRs',
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: HxSpace.x2),
            for (final pr in snapshot.recentPrs)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: HxSpace.x1 + 2),
                child: Row(
                  children: [
                    Icon(Icons.emoji_events_rounded, color: context.hx.warning),
                    const SizedBox(width: HxSpace.x3),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(pr.exercise),
                          Text(
                            date.format(pr.at),
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: context.hx.onSurfaceVariant,
                            ),
                          ),
                        ],
                      ),
                    ),
                    Text(
                      'e1RM ${units.format(pr.e1rmKg, decimals: 0)}',
                      style: const TextStyle(fontWeight: FontWeight.w700),
                    ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _SharedSessionsCard extends ConsumerWidget {
  const _SharedSessionsCard({required this.me, required this.friend});

  final FriendSnapshot? me;
  final FriendEntry friend;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final server =
        ref.watch(friendSharedSessionsProvider(friend.userId)).valueOrNull ??
        const <String, DateTime>{};
    final sessions = FriendComparison.sharedSessions(
      mine: me,
      theirs: friend.snapshot,
      serverIds: server,
    );
    final theme = Theme.of(context);
    final hx = context.hx;
    final units = ref.watch(weightFormatProvider);
    final date = DateFormat.yMMMd();

    String side(FriendBuddySession? s) => s == null
        ? '—'
        : '${units.formatTonnage(s.tonnageKg)} · ${s.sets} sets';

    return HxCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Trained together',
            style: theme.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: HxSpace.x2),
          if (sessions.isEmpty)
            Text(
              'Start a workout, tap the Gym Buddy icon and let '
              '${friend.displayName} scan the code. Shared sessions show up '
              'here.',
              style: theme.textTheme.bodySmall?.copyWith(
                color: hx.onSurfaceVariant,
              ),
            ),
          for (final s in sessions)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: HxSpace.x2),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    date.format(s.at),
                    style: theme.textTheme.labelLarge?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Row(
                    children: [
                      Expanded(child: Text('You: ${side(s.mine)}')),
                      Expanded(
                        child: Text(
                          'Them: ${side(s.theirs)}',
                          textAlign: TextAlign.end,
                        ),
                      ),
                    ],
                  ),
                  if (s.mine?.topExercise != null ||
                      s.theirs?.topExercise != null)
                    Text(
                      [
                        if (s.mine case FriendBuddySession(
                          :final topExercise?,
                          :final topKg?,
                        ))
                          'Your top: $topExercise ${units.format(topKg)}',
                        if (s.theirs case FriendBuddySession(
                          :final topExercise?,
                          :final topKg?,
                        ))
                          'Their top: $topExercise ${units.format(topKg)}',
                      ].join(' · '),
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: hx.onSurfaceVariant,
                      ),
                    ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}
