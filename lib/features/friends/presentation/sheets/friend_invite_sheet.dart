import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:herculex/app/router/routes.dart';
import 'package:herculex/core/notifications/app_notice.dart';
import 'package:herculex/design_system/components/components.dart';
import 'package:herculex/design_system/tokens/tokens.dart';
import 'package:herculex/features/friends/application/friends_providers.dart';
import 'package:herculex/features/friends/domain/friend_invite_payload.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:share_plus/share_plus.dart';

/// Add a friend: show my QR / share my link, or scan / paste theirs.
class FriendInviteSheet extends ConsumerStatefulWidget {
  const FriendInviteSheet({super.key});

  static Future<void> show(BuildContext context) =>
      HxSheet.show<void>(context, builder: (_) => const FriendInviteSheet());

  @override
  ConsumerState<FriendInviteSheet> createState() => _FriendInviteSheetState();
}

class _FriendInviteSheetState extends ConsumerState<FriendInviteSheet> {
  late final Future<String> _token = ref
      .read(friendsGatewayProvider)
      .createInvite();
  final _codeCtrl = TextEditingController();
  String? _codeError;

  @override
  void dispose() {
    _codeCtrl.dispose();
    super.dispose();
  }

  void _openInvite(String raw) {
    final invite = FriendInvitePayload.tryDecode(raw);
    if (invite == null) {
      setState(() => _codeError = 'That is not a Herculex invite');
      return;
    }
    final router = GoRouter.of(context);
    Navigator.of(context).pop();
    router.push(AppPaths.friendInvite(invite.token));
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final hx = context.hx;

    return HxSheet(
      title: 'Add a gym buddy',
      subtitle: 'Each invite works once and expires in 7 days.',
      initialSize: 0.85,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          FutureBuilder<String>(
            future: _token,
            builder: (context, snap) {
              if (snap.hasError) {
                return Padding(
                  padding: const EdgeInsets.symmetric(vertical: HxSpace.x6),
                  child: Text(
                    'Could not create an invite: ${snap.error}',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: hx.danger),
                  ),
                );
              }
              final token = snap.data;
              if (token == null) {
                return const Padding(
                  padding: EdgeInsets.symmetric(vertical: 80),
                  child: Center(child: CircularProgressIndicator()),
                );
              }
              final link = FriendInvitePayload(token).encode();
              return Column(
                children: [
                  Center(
                    child: Container(
                      padding: const EdgeInsets.all(HxSpace.x3),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(HxRadius.lg),
                      ),
                      child: QrImageView(
                        data: link,
                        version: QrVersions.auto,
                        size: 200,
                        backgroundColor: Colors.white,
                      ),
                    ),
                  ),
                  const SizedBox(height: HxSpace.x3),
                  Text(
                    'Let your friend scan this, or send the link.',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: hx.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: HxSpace.x3),
                  Row(
                    children: [
                      Expanded(
                        child: FilledButton.icon(
                          icon: const Icon(Icons.share_rounded),
                          label: const Text('Share link'),
                          onPressed: () => Share.share(
                            'Add me on Herculex Gym Buddy: $link\n'
                            'Or paste this code in Gym Buddy: $token',
                          ),
                        ),
                      ),
                      const SizedBox(width: HxSpace.x2),
                      Expanded(
                        child: OutlinedButton.icon(
                          icon: const Icon(Icons.copy_rounded),
                          label: const Text('Copy code'),
                          onPressed: () async {
                            await Clipboard.setData(ClipboardData(text: token));
                            if (!context.mounted) return;
                            AppNotice.show(context, 'Invite code copied');
                          },
                        ),
                      ),
                    ],
                  ),
                ],
              );
            },
          ),
          const SizedBox(height: HxSpace.x6),
          Text(
            'GOT A CODE FROM A FRIEND?',
            style: theme.textTheme.labelSmall?.copyWith(
              color: hx.onSurfaceVariant,
              fontWeight: FontWeight.bold,
              letterSpacing: 0.8,
            ),
          ),
          const SizedBox(height: HxSpace.x2),
          TextField(
            controller: _codeCtrl,
            decoration: InputDecoration(
              hintText: 'Paste the code or link',
              errorText: _codeError,
              suffixIcon: IconButton(
                tooltip: 'Add friend',
                icon: const Icon(Icons.arrow_forward_rounded),
                onPressed: () => _openInvite(_codeCtrl.text),
              ),
            ),
            onChanged: (_) {
              if (_codeError != null) setState(() => _codeError = null);
            },
            onSubmitted: _openInvite,
          ),
          const SizedBox(height: HxSpace.x3),
          OutlinedButton.icon(
            icon: const Icon(Icons.qr_code_scanner_rounded),
            label: const Text('Scan a friend\'s QR code'),
            onPressed: () {
              final router = GoRouter.of(context);
              Navigator.of(context).pop();
              router.push(AppRoutes.buddyJoin);
            },
          ),
        ],
      ),
    );
  }
}
