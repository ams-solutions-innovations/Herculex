import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:herculex/app/providers.dart';
import 'package:herculex/app/router/routes.dart';
import 'package:herculex/core/notifications/app_notice.dart';
import 'package:herculex/design_system/components/components.dart';
import 'package:herculex/design_system/tokens/tokens.dart';
import 'package:herculex/features/settings/presentation/sheets/auth_sheet.dart';

/// Cloud account (sign in / out) and the destructive actions.
class AccountSettingsView extends ConsumerWidget {
  const AccountSettingsView({super.key});

  Future<bool> _confirm(
    BuildContext context, {
    required String title,
    required String body,
    required String action,
  }) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(title),
        content: Text(body),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(action),
          ),
        ],
      ),
    );
    return confirmed == true;
  }

  Future<void> _signOut(BuildContext context, WidgetRef ref) async {
    if (ref.read(accountRequiredProvider)) {
      return _signOutOfBrowser(context, ref);
    }
    final confirmed = await _confirm(
      context,
      title: 'Sign out',
      body:
          'Signing out will pause cloud sync. Your local workout and nutrition data will remain on this device.',
      action: 'Sign out',
    );
    if (confirmed && context.mounted) {
      await ref.read(authRepositoryProvider).signOut();
    }
  }

  /// The web has no signed-out mode, so signing out also removes this
  /// browser's copy of the account — it would otherwise sit readable in
  /// browser storage for whoever uses the machine next. Unsynced edits get
  /// one last push first, and the user hears about any that still fail.
  Future<void> _signOutOfBrowser(BuildContext context, WidgetRef ref) async {
    final confirmed = await _confirm(
      context,
      title: 'Sign out',
      body:
          'You will be signed out and this browser’s copy of your data will be '
          'removed. Everything already synced stays in your account.',
      action: 'Sign out',
    );
    if (!confirmed || !context.mounted) return;

    final sync = ref.read(syncServiceProvider);
    await sync.pushOnce();
    final unsynced = sync.state.pendingCount;
    if (unsynced > 0 && context.mounted) {
      final discard = await _confirm(
        context,
        title: 'Some changes haven’t synced',
        body:
            '$unsynced change${unsynced == 1 ? '' : 's'} from this browser '
            'could not be uploaded yet. Signing out now discards '
            '${unsynced == 1 ? 'it' : 'them'}.',
        action: 'Sign out anyway',
      );
      if (!discard) return;
    }
    await ref.read(accountDeletionServiceProvider).clearAllLocalDataOnly();
  }

  Future<void> _deleteAccount(BuildContext context, WidgetRef ref) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text('Delete account?'),
        content: const Text(
          'Your Herculex account and everything stored in the cloud for it — '
          'workouts, nutrition logs, measurements, cycle records — are deleted '
          'permanently, and this device is wiped too.\n\n'
          'This cannot be undone and the data cannot be recovered.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: FilledButton.styleFrom(
              backgroundColor: ctx.hx.danger,
              shape: const StadiumBorder(),
            ),
            child: const Text('Delete account'),
          ),
        ],
      ),
    );
    if (confirmed != true || !context.mounted) return;

    // The remote call is a network round trip that ends in an irreversible
    // deletion, so the screen is blocked rather than left tappable — a second
    // tap would hit an account that is already gone.
    unawaited(
      showDialog<void>(
        context: context,
        barrierDismissible: false,
        builder: (_) => const Center(child: CircularProgressIndicator()),
      ),
    );

    String? error;
    try {
      await ref
          .read(accountDeletionServiceProvider)
          .deleteAccountAndWipeDevice();
    } catch (e) {
      error = e is Exception
          ? e.toString().replaceFirst('Exception: ', '')
          : '$e';
    }

    if (!context.mounted) return;
    Navigator.of(context, rootNavigator: true).pop(); // the spinner

    if (error != null) {
      // Nothing was deleted — `AccountDeletionService` only wipes the device
      // after the backend confirms — so this is safe to retry.
      AppNotice.showWith(
        ref,
        error.trim().isEmpty ? 'Check your connection and retry' : error,
        title: 'Could not save',
        kind: AppNoticeKind.error,
      );
    }
    // On success the cleared profile drops the router back to onboarding,
    // exactly as clearing local data does.
  }

  Future<void> _clearData(BuildContext context, WidgetRef ref) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text('Clear all data?'),
        content: const Text(
          'This will permanently delete your profile, workouts, nutrition logs, photos, and all other local data on this device. Your cloud account is untouched. This cannot be undone.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: FilledButton.styleFrom(
              backgroundColor: ctx.hx.danger,
              shape: const StadiumBorder(),
            ),
            child: const Text('Delete everything'),
          ),
        ],
      ),
    );
    if (confirmed != true || !context.mounted) return;
    await ref.read(accountDeletionServiceProvider).clearAllLocalDataOnly();
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final session = ref.watch(authSessionProvider).valueOrNull;

    return HxScreenShell(
      title: 'Account',
      titleIcon: Icons.person_outline_rounded,
      children: [
        const HxSectionHeader('Cloud account'),
        const SizedBox(height: 10),
        HxSettingsCard(
          children: [
            if (session == null)
              HxSettingsTile(
                icon: Icons.cloud_sync_rounded,
                label: 'Sign in to Supabase',
                subtitle: 'Sync your data across devices',
                trailing: Icon(Icons.chevron_right, color: context.hx.primary),
                onTap: () => AuthSheet.show(context),
              )
            else ...[
              HxSettingsTile(
                icon: Icons.person_outline_rounded,
                label: session.email ?? 'Signed in',
                trailing: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 2,
                  ),
                  decoration: BoxDecoration(
                    color: context.hx.primary.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    'Online',
                    style: TextStyle(
                      color: context.hx.primary,
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ),
              const HxSettingsDivider(),
              HxSettingsTile(
                icon: Icons.logout_rounded,
                label: 'Sign Out',
                chevron: true,
                onTap: () => _signOut(context, ref),
              ),
            ],
          ],
        ),
        const SizedBox(height: 24),
        const HxSectionHeader('Social & Gym Buddy'),
        const SizedBox(height: 10),
        HxSettingsCard(
          children: [
            HxSettingsTile(
              icon: Icons.group_rounded,
              label: 'Gym Buddy & Friends',
              subtitle: 'Compare lifts, goals, and shared workouts',
              chevron: true,
              onTap: () => context.push(AppRoutes.gymBuddy),
            ),
          ],
        ),
        const SizedBox(height: 24),
        const HxSectionHeader('Danger zone'),
        const SizedBox(height: 10),
        HxSettingsCard(
          children: [
            if (session != null) ...[
              // App Store Guideline 5.1.1(v) and GDPR Article 17: an account
              // created in the app must be deletable from inside the app.
              // Distinct from "Clear All Data" below, which never touches the
              // cloud — this deletes the account itself.
              HxSettingsTile.danger(
                icon: Icons.person_remove_rounded,
                label: 'Delete Account',
                subtitle: 'Removes your cloud account and wipes this device',
                onTap: () => _deleteAccount(context, ref),
              ),
              const HxSettingsDivider(),
            ],
            HxSettingsTile.danger(
              icon: Icons.delete_forever_rounded,
              label: 'Clear All Data',
              subtitle: 'Deletes local data only; the cloud is untouched',
              onTap: () => _clearData(context, ref),
            ),
          ],
        ),
      ],
    );
  }
}
