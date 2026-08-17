import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/providers.dart';
import '../../../widgets/glass_container.dart';

/// Developer-only content tooling. Reachable only in debug builds (the routes
/// are excluded from release in the router).
class AdminDashboardView extends ConsumerWidget {
  const AdminDashboardView({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: Text("Admin Dashboard", style: theme.textTheme.labelLarge),
        backgroundColor: Colors.transparent,
        elevation: 0,
        actions: [
          IconButton(
            icon: const Icon(Icons.exit_to_app),
            tooltip: 'Back to app',
            onPressed: () => context.go('/app'),
          )
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(24.0),
        children: [
          Text("Manage Content", style: theme.textTheme.displayMedium),
          const SizedBox(height: 32),
          _buildActionCard(
            context: context,
            title: "Insert Custom Workout",
            icon: Icons.fitness_center,
            onTap: () => context.push('/admin/workout'),
          ),
          const SizedBox(height: 16),
          _buildActionCard(
            context: context,
            title: "Insert Custom Recipe",
            icon: Icons.restaurant_menu,
            onTap: () => context.push('/admin/recipe'),
          ),
          const SizedBox(height: 32),
          Divider(color: Colors.grey.withValues(alpha: 0.2)),
          const SizedBox(height: 32),
          Text("Rep Tracking", style: theme.textTheme.displayMedium),
          const SizedBox(height: 16),
          _buildActionCard(
            context: context,
            title: "Fixture Recording (REP-06)",
            icon: Icons.fiber_manual_record,
            onTap: () => context.push('/admin/fixture-recording'),
          ),
          const SizedBox(height: 32),
          Divider(color: Colors.grey.withValues(alpha: 0.2)),
          const SizedBox(height: 32),
          Text("Cloud Sync", style: theme.textTheme.displayMedium),
          const SizedBox(height: 16),
          _buildActionCard(
            context: context,
            title: "Re-upload All Local Data",
            icon: Icons.cloud_upload,
            onTap: () => _confirmReupload(context, ref),
          ),
          const SizedBox(height: 32),
          Divider(color: Colors.grey.withValues(alpha: 0.2)),
          const SizedBox(height: 32),
          Text("App Previews", style: theme.textTheme.displayMedium),
          const SizedBox(height: 16),
          _buildActionCard(
            context: context,
            title: "Preview App",
            icon: Icons.phone_iphone,
            onTap: () => context.go('/app'),
          ),
        ],
      ),
    );
  }

  /// Forces every local row back up to the cloud. Only meaningful after the
  /// app has been repointed at a different Supabase project — rows already
  /// marked synced against the *old* project are otherwise never re-pushed.
  ///
  /// Sign in first: the push is a no-op without a user id, and signing in
  /// after enqueueing would clear the outbox again (`_claimLocalDatabaseFor`).
  Future<void> _confirmReupload(BuildContext context, WidgetRef ref) async {
    final messenger = ScaffoldMessenger.of(context);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Re-upload all local data?'),
        content: const Text(
          'Queues every local row for upload to the cloud account you are '
          'signed in as. Use this after switching the app to a different '
          'Supabase project.\n\n'
          'Make sure you are signed in first.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Re-upload'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    messenger.showSnackBar(
      const SnackBar(content: Text('Queueing local data for upload…')),
    );
    try {
      final count = await ref.read(syncServiceProvider).reuploadAllLocalData();
      messenger.showSnackBar(
        SnackBar(content: Text('Queued $count row(s). Watch the sync badge.')),
      );
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text('Re-upload failed: $e')));
    }
  }

  Widget _buildActionCard({
    required BuildContext context,
    required String title,
    required IconData icon,
    required VoidCallback onTap,
  }) {
    final theme = Theme.of(context);
    return GestureDetector(
      onTap: onTap,
      child: GlassContainer(
        padding: const EdgeInsets.all(24),
        child: Row(
          children: [
            Icon(icon, size: 32, color: theme.colorScheme.primary),
            const SizedBox(width: 24),
            Expanded(
              child: Text(title, style: theme.textTheme.labelLarge?.copyWith(fontSize: 16)),
            ),
            Icon(Icons.arrow_forward_ios, size: 16, color: theme.textTheme.bodyMedium?.color),
          ],
        ),
      ),
    );
  }
}
