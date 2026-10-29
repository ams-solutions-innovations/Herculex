import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:herculex/app/providers.dart';
import 'package:herculex/app/router/routes.dart';
import 'package:herculex/core/notifications/app_notice.dart';
import 'package:herculex/design_system/components/components.dart';
import 'package:herculex/features/profile/presentation/widgets/sync_status_badge.dart';
import 'package:herculex/features/settings/data/user_data_export_service.dart';
import 'package:herculex/features/settings/presentation/sheets/auth_sheet.dart';
import 'package:herculex/features/settings/presentation/sheets/sync_detail_sheet.dart';

/// Cloud sync, export, and the user's own libraries (gyms, exercises, foods …).
class DataLibrarySettingsView extends ConsumerStatefulWidget {
  const DataLibrarySettingsView({super.key});

  @override
  ConsumerState<DataLibrarySettingsView> createState() =>
      _DataLibrarySettingsViewState();
}

class _DataLibrarySettingsViewState
    extends ConsumerState<DataLibrarySettingsView> {
  bool _exporting = false;

  Future<void> _exportData() async {
    if (_exporting) return;
    setState(() => _exporting = true);
    AppNotice.show(
      context,
      'Preparing JSON export...',
      kind: AppNoticeKind.info,
    );
    try {
      await ref.read(userDataExportServiceProvider).exportAndShare();
      if (!mounted) return;
      AppNotice.show(context, 'Data export ready.');
    } catch (e) {
      if (!mounted) return;
      AppNotice.show(
        context,
        'Could not export data. Please try again.',
        kind: AppNoticeKind.error,
      );
    } finally {
      if (mounted) setState(() => _exporting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final signedIn = ref.watch(authSessionProvider).valueOrNull != null;

    return HxScreenShell(
      title: 'Data & Library',
      titleIcon: Icons.folder_open_rounded,
      children: [
        const HxSectionHeader('Sync & backup'),
        const SizedBox(height: 10),
        HxSettingsCard(
          children: [
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
              label: _exporting ? 'Exporting Data...' : 'Export Data (JSON)',
              chevron: !_exporting,
              onTap: _exporting ? null : _exportData,
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
              icon: Icons.school_outlined,
              label: 'Training Techniques',
              chevron: true,
              onTap: () => context.push(AppRoutes.setTypesGuide),
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
