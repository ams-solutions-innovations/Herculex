import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:herculex/core/utils/units.dart';
import 'package:herculex/design_system/components/components.dart';
import 'package:herculex/design_system/tokens/tokens.dart';
import 'package:herculex/features/settings/presentation/widgets/appearance_toggles.dart';

/// Theme, accent colour, notification theme, measurement system, and widget appearance.
class AppearanceSettingsView extends ConsumerWidget {
  const AppearanceSettingsView({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isMetric = ref.watch(unitsProvider) == MeasurementUnit.metric;
    final theme = Theme.of(context);

    return HxScreenShell(
      title: 'Appearance',
      titleIcon: Icons.palette_outlined,
      children: [
        const HxSectionHeader('Look'),
        const SizedBox(height: 10),
        const HxSettingsCard(
          children: [
            HxSettingsTile(
              icon: Icons.dark_mode_rounded,
              label: 'Theme',
              trailing: ThemeModeToggle(),
            ),
            HxSettingsDivider(),
            HxSettingsTile(
              icon: Icons.palette_outlined,
              label: 'App Colors',
              trailing: AppColorThemeToggle(),
            ),
            HxSettingsDivider(),
            HxSettingsTile(
              icon: Icons.notifications_active_outlined,
              label: 'Notification Theme',
              trailing: NotificationStyleToggle(),
            ),
          ],
        ),
        const SizedBox(height: 24),
        const HxSectionHeader('Units'),
        const SizedBox(height: 10),
        HxSettingsCard(
          children: [
            HxSettingsTile(
              icon: Icons.straighten_rounded,
              label: 'Units',
              trailing: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    isMetric ? 'Metric' : 'Freedom',
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: context.hx.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Switch(
                    value: isMetric,
                    onChanged: (_) => ref.read(unitsProvider.notifier).toggle(),
                  ),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: 24),
        const HxSectionHeader('Widgets'),
        const SizedBox(height: 10),
        const HxSettingsCard(
          children: [
            HxSettingsTile(
              icon: Icons.widgets_outlined,
              label: 'Widget Theme',
              trailing: WidgetThemeModeToggle(),
            ),
            HxSettingsDivider(),
            WidgetTransparencyTile(),
            HxSettingsDivider(),
            WidgetShapeTile(),
          ],
        ),
      ],
    );
  }
}
