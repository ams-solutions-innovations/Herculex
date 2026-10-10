import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:herculex/app/router/routes.dart';
import 'package:herculex/design_system/components/components.dart';
import 'package:herculex/design_system/tokens/tokens.dart';
import 'package:herculex/features/friends/application/friends_providers.dart';
import 'package:herculex/features/friends/data/friends_gateway.dart';

/// Where an invite link or QR lands: confirm before becoming friends, since
/// a friend can see your shared stats.
class FriendInviteAcceptView extends ConsumerStatefulWidget {
  const FriendInviteAcceptView({super.key, required this.token});

  final String token;

  @override
  ConsumerState<FriendInviteAcceptView> createState() =>
      _FriendInviteAcceptViewState();
}

class _FriendInviteAcceptViewState
    extends ConsumerState<FriendInviteAcceptView> {
  bool _busy = false;
  String? _error;

  Future<void> _accept() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final friendId = await ref
          .read(friendsGatewayProvider)
          .acceptInvite(widget.token);
      ref.invalidate(friendsListProvider);
      // Publish now so the new friend sees numbers straight away.
      await ref.read(friendSnapshotPublisherProvider).publishNow();
      if (!mounted) return;
      context.pushReplacement(AppPaths.friendDetail(friendId));
    } on FriendInviteRejected {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = 'This invite is invalid, used or expired. Ask for a new one.';
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = '$e';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final hx = context.hx;
    final available = ref.watch(friendsAvailableProvider);

    return HxScreenShell(
      title: 'Gym Buddy invite',
      children: [
        const SizedBox(height: HxSpace.x8),
        Icon(Icons.group_add_rounded, size: 64, color: hx.primary),
        const SizedBox(height: HxSpace.x4),
        Text(
          'Add a gym buddy?',
          textAlign: TextAlign.center,
          style: theme.textTheme.headlineSmall?.copyWith(
            fontWeight: FontWeight.w800,
          ),
        ),
        const SizedBox(height: HxSpace.x2),
        Text(
          available
              ? 'You will see each other\'s level, main lifts, recent PRs, '
                    'goal progress and workouts you did together. You can '
                    'stop sharing or remove a friend at any time.'
              : 'Sign in on the Profile tab to add gym buddies.',
          textAlign: TextAlign.center,
          style: theme.textTheme.bodyMedium?.copyWith(
            color: hx.onSurfaceVariant,
          ),
        ),
        if (_error != null) ...[
          const SizedBox(height: HxSpace.x4),
          Text(
            _error!,
            textAlign: TextAlign.center,
            style: TextStyle(color: hx.danger),
          ),
        ],
        const SizedBox(height: HxSpace.x6),
        FilledButton(
          onPressed: available && !_busy ? _accept : null,
          child: _busy
              ? const SizedBox.square(
                  dimension: 20,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Text('Add friend'),
        ),
        const SizedBox(height: HxSpace.x2),
        TextButton(
          // A cold-start deep link has nothing underneath to pop back to.
          onPressed: _busy
              ? null
              : () => context.canPop()
                    ? context.pop()
                    : context.go(AppRoutes.app),
          child: const Text('Not now'),
        ),
      ],
    );
  }
}
