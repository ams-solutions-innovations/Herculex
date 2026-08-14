import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

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
