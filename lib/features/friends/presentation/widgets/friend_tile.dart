import 'package:flutter/material.dart';
import 'package:herculex/design_system/components/components.dart';
import 'package:herculex/design_system/tokens/tokens.dart';
import 'package:herculex/features/friends/domain/friend_comparison.dart';
import 'package:herculex/features/profile/presentation/widgets/greek_avatar_badge.dart';

/// One friend in the Gym Buddy list: who, their level, and the latest news.
class FriendTile extends StatelessWidget {
  const FriendTile({super.key, required this.friend, required this.onTap});

  final FriendEntry friend;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final hx = context.hx;
    final s = friend.snapshot;
    final latestPr = s?.recentPrs.firstOrNull;
    final subtitle = s == null
        ? 'Not sharing stats right now'
        : latestPr != null
        ? 'New PR: ${latestPr.exercise}'
        : '${s.completedWorkouts} workouts logged';

    return Padding(
      padding: const EdgeInsets.only(bottom: HxSpace.x2),
      child: HxCard(
        onTap: onTap,
        padding: const EdgeInsets.all(HxSpace.x4),
        child: Row(
          children: [
            GreekAvatarBadge(
              avatarId: friend.avatarId,
              fallbackName: friend.displayName,
              size: 44,
            ),
            const SizedBox(width: HxSpace.x3),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    friend.displayName,
                    style: theme.textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    subtitle,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: hx.onSurfaceVariant,
                    ),
                  ),
                  if (s?.goal case final goal?) ...[
                    const SizedBox(height: HxSpace.x2),
                    ClipRRect(
                      borderRadius: HxRadius.pillAll,
                      child: LinearProgressIndicator(
                        value: goal.progress,
                        minHeight: 4,
                        backgroundColor: hx.surfaceVariant,
                      ),
                    ),
                  ],
                ],
              ),
            ),
            if (s != null && s.levelTitle.isNotEmpty) ...[
              const SizedBox(width: HxSpace.x2),
              Text(
                s.levelTitle,
                style: theme.textTheme.labelMedium?.copyWith(
                  color: hx.primary,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
            Icon(Icons.chevron_right_rounded, color: hx.onSurfaceVariant),
          ],
        ),
      ),
    );
  }
}
