import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:herculex/app/providers.dart';
import 'package:herculex/core/notifications/app_notice.dart';
import 'package:herculex/design_system/components/components.dart';
import 'package:herculex/design_system/tokens/tokens.dart';
import 'package:herculex/features/settings/presentation/sheets/auth_sheet.dart';

/// Cloud account (sign in / out) and the destructive actions.
class AccountSettingsView extends ConsumerWidget {
  const AccountSettingsView({super.key});

  Future<void> _signOut(BuildContext context, WidgetRef ref) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Sign out'),
        content: const Text(
          'Signing out will pause cloud sync. Your local workout and nutrition data will remain on this device.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Sign out'),
          ),
        ],
      ),
    );
    if (confirmed == true && context.mounted) {
      await ref.read(authRepositoryProvider).signOut();
    }
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
          'This will permanently delete your profile, workouts, nutrition logs, and all other local data. This cannot be undone.',
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
    // Clearing the profile drops the user back to onboarding via the router
    // redirect (which watches profileProvider).
    await ref.read(localProfileRepositoryProvider).clear();
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
