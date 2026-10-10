import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:herculex/app/router/routes.dart';
import 'package:herculex/design_system/components/components.dart';
import 'package:herculex/features/nutrition/data/wear_sync_service.dart';
import 'package:herculex/services/platform/workout_bubble_service.dart';
import 'package:permission_handler/permission_handler.dart';

/// Everything the app needs the OS (or a health platform) to grant.
class PermissionsSettingsView extends ConsumerWidget {
  const PermissionsSettingsView({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return HxScreenShell(
      title: 'Permissions',
      titleIcon: Icons.shield_outlined,
      children: [
        const HxSectionHeader('Device access'),
        const SizedBox(height: 10),
        HxSettingsCard(
          children: [
            HxSettingsTile(
              icon: Icons.music_note_rounded,
              label: 'Media Controls Permission',
              subtitle: 'Lets workouts control music playback',
              chevron: true,
              onTap: () => WearSyncService().openMediaControlsPermission(),
            ),
            // Android-only: iOS has no system overlay windows, so the row is
            // hidden rather than shown dead.
            if (WorkoutBubbleService.instance.isSupported) ...[
              const HxSettingsDivider(),
              HxSettingsTile(
                icon: Icons.bubble_chart_rounded,
                label: 'Display over other apps',
                subtitle: 'Needed for the floating workout bubble',
                chevron: true,
                onTap: () => Permission.systemAlertWindow.request(),
              ),
            ],
            const HxSettingsDivider(),
            HxSettingsTile(
              icon: Icons.settings_applications_outlined,
              label: 'System app settings',
              subtitle: 'Camera, microphone, notifications and more',
              chevron: true,
              onTap: openAppSettings,
            ),
          ],
        ),
        const SizedBox(height: 24),
        const HxSectionHeader('Health data'),
        const SizedBox(height: 10),
        HxSettingsCard(
          children: [
            HxSettingsTile(
              icon: Icons.health_and_safety_rounded,
              label: 'Health Integrations',
              subtitle: 'Samsung Health, Apple Health, Health Connect',
              chevron: true,
              onTap: () => context.push(AppRoutes.health),
            ),
          ],
        ),
      ],
    );
  }
}
