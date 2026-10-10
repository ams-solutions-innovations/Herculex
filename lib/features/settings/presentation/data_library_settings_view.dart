import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:herculex/app/providers.dart';
import 'package:herculex/app/router/routes.dart';
import 'package:herculex/core/notifications/app_notice.dart';
import 'package:herculex/design_system/components/components.dart';
import 'package:herculex/features/profile/presentation/widgets/sync_status_badge.dart';
import 'package:herculex/features/settings/presentation/sheets/auth_sheet.dart';
import 'package:herculex/features/settings/presentation/sheets/sync_detail_sheet.dart';

/// Cloud sync, export, and the user's own libraries (gyms, exercises, foods …).
class DataLibrarySettingsView extends ConsumerWidget {
  const DataLibrarySettingsView({super.key});

  void _exportData(BuildContext context) {
    // Tell the user the export has started
    AppNotice.show(
      context,
      'Exporting data as JSON...',
      kind: AppNoticeKind.info,
    );
    final notices = AppNotice.of(context);
    // In a real implementation this would fetch from Drift and use path_provider to save a file.
    Future.delayed(const Duration(seconds: 1), () {
      if (!context.mounted) return;
      notices.show('Data export saved to Downloads folder.');
    });
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final signedIn = ref.watch(authSessionProvider).valueOrNull != null;

    return HxScreenShell(
      title: 'Data & Library',
      titleIcon: Icons.folder_open_rounded,
      children: [
        const HxSectionHeader('Sync & backup'),
        const SizedBox(height: 10),
        HxSettingsCard(
          children: [
            // Its own row: this reports cloud sync, and hanging it off the
            // Samsung Health tile read as that integration's status.
            HxSettingsTile(
              icon: Icons.cloud_outlined,
              label: 'Cloud sync',
              trailing: const SyncStatusBadge(),
              onTap: signedIn
                  ? () => SyncDetailSheet.show(context)
                  : () => AuthSheet.show(context),
            ),
            const HxSettingsDivider(),
            HxSettingsTile(
              icon: Icons.download_rounded,
              label: 'Export Data (JSON)',
              chevron: true,
              onTap: () => _exportData(context),
            ),
          ],
        ),
        const SizedBox(height: 24),
        const HxSectionHeader('Your data'),
        const SizedBox(height: 10),
        HxSettingsCard(
          children: [
            HxSettingsTile(
              icon: Icons.analytics_rounded,
              label: 'Insights',
              chevron: true,
              onTap: () => context.push(AppRoutes.insights),
            ),
            const HxSettingsDivider(),
            HxSettingsTile(
              icon: Icons.straighten,
              label: 'Body Measurements',
              chevron: true,
              onTap: () => context.push(AppRoutes.measurements),
            ),
          ],
        ),
        const SizedBox(height: 24),
        const HxSectionHeader('Libraries'),
        const SizedBox(height: 10),
        HxSettingsCard(
          children: [
            HxSettingsTile(
              icon: Icons.location_on_outlined,
              label: 'My Gyms',
              chevron: true,
              onTap: () => context.push(AppRoutes.gyms),
            ),
            const HxSettingsDivider(),
            HxSettingsTile(
              icon: Icons.task_alt,
              label: 'Micro Workouts',
              chevron: true,
              onTap: () => context.push(AppRoutes.microWorkouts),
            ),
            const HxSettingsDivider(),
            HxSettingsTile(
              icon: Icons.fitness_center_rounded,
              label: 'Exercise Library',
              chevron: true,
              onTap: () => context.push(AppRoutes.exercises),
            ),
            const HxSettingsDivider(),
            HxSettingsTile(
              icon: Icons.restaurant_menu_rounded,
              label: 'Custom Foods',
              chevron: true,
              onTap: () => context.push(AppRoutes.customFoods),
            ),
            const HxSettingsDivider(),
            HxSettingsTile(
              icon: Icons.menu_book_rounded,
              label: 'Custom Recipes',
              chevron: true,
              onTap: () => context.push(AppRoutes.customRecipes),
            ),
          ],
        ),
      ],
    );
  }
}
