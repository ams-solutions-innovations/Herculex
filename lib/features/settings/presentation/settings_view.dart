import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:herculex/app/providers.dart';
import 'package:herculex/app/router/routes.dart';
import 'package:herculex/design_system/components/components.dart';
import 'package:herculex/design_system/tokens/tokens.dart';

/// Settings hub: one row per category, each opening its own screen.
class SettingsView extends ConsumerWidget {
  const SettingsView({super.key});

  void _showAttribution(BuildContext context) {
    showAboutDialog(
      context: context,
      applicationName: 'Herculex',
      applicationVersion: '1.0.0',
      applicationIcon: Container(
        width: 48,
        height: 48,
        decoration: BoxDecoration(
          color: context.hx.primary.withValues(alpha: 0.1),
          shape: BoxShape.circle,
        ),
        child: Icon(Icons.fitness_center_rounded, color: context.hx.primary),
      ),
      children: [
        const SizedBox(height: 16),
        const Text(
          'Herculex is a comprehensive fitness, nutrition, and recovery tracker.\n\n'
          'Designed to provide full offline capabilities and advanced analytics.',
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final email = ref.watch(authSessionProvider).valueOrNull?.email;

    return HxScreenShell(
      title: 'Settings',
      titleIcon: Icons.settings_rounded,
      children: [
        HxSettingsCard(
          children: [
            HxSettingsTile(
              icon: Icons.palette_outlined,
              label: 'Appearance',
              subtitle: 'Theme, colors, units',
              chevron: true,
              onTap: () => context.push(AppRoutes.settingsAppearance),
            ),
            const HxSettingsDivider(),
            HxSettingsTile(
              icon: Icons.shield_outlined,
              label: 'Permissions',
              subtitle: 'Media, overlay, health access',
              chevron: true,
              onTap: () => context.push(AppRoutes.settingsPermissions),
            ),
            const HxSettingsDivider(),
            HxSettingsTile(
              icon: Icons.notifications_rounded,
              label: 'Notifications',
              subtitle: 'Reminders for meals, fasting, workouts',
              chevron: true,
              onTap: () => context.push(AppRoutes.notifications),
            ),
            const HxSettingsDivider(),
            HxSettingsTile(
              icon: Icons.tune_rounded,
              label: 'Preferences',
              subtitle: 'Calories, coach tone, voice, goals',
              chevron: true,
              onTap: () => context.push(AppRoutes.settingsPreferences),
            ),
            const HxSettingsDivider(),
            HxSettingsTile(
              icon: Icons.folder_open_rounded,
              label: 'Data & Library',
              subtitle: 'Cloud sync, export, gyms, foods, exercises',
              chevron: true,
              onTap: () => context.push(AppRoutes.settingsData),
            ),
            const HxSettingsDivider(),
            HxSettingsTile(
              icon: Icons.person_outline_rounded,
              label: 'Account',
              subtitle: email ?? 'Sign in, sign out, delete data',
              chevron: true,
              onTap: () => context.push(AppRoutes.settingsAccount),
            ),
          ],
        ),
        const SizedBox(height: 24),
        HxSettingsCard(
          children: [
            HxSettingsTile(
              icon: Icons.info_outline_rounded,
              label: 'About & Attribution',
              chevron: true,
              onTap: () => _showAttribution(context),
            ),
          ],
        ),
      ],
    );
  }
}
