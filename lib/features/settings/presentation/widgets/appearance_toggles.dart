import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:herculex/core/notifications/in_app_notification_style.dart';
import 'package:herculex/core/utils/units.dart';
import 'package:herculex/design_system/components/components.dart';
import 'package:herculex/design_system/theme/haptics.dart';
import 'package:herculex/design_system/theme/theme_provider.dart';
import 'package:herculex/design_system/tokens/tokens.dart';
import 'package:herculex/services/platform/widget_appearance.dart';

/// Light / System / Dark dropdown, shared by the app theme and the widget theme.
class ThemeModeDropdown extends StatelessWidget {
  const ThemeModeDropdown({
    super.key,
    required this.value,
    required this.onChanged,
  });

  final ThemeMode value;
  final ValueChanged<ThemeMode> onChanged;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 2),
      decoration: BoxDecoration(
        color: context.hx.surfaceVariant,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: context.hx.outlineVariant.withValues(alpha: 0.5),
        ),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<ThemeMode>(
          value: value,
          isDense: true,
          icon: Icon(
            Icons.arrow_drop_down_rounded,
            color: context.hx.onSurfaceVariant,
            size: 20,
          ),
          dropdownColor: context.hx.surfaceContainer,
          borderRadius: BorderRadius.circular(16),
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w500,
            color: context.hx.onSurface,
          ),
          items: [
            DropdownMenuItem(
              value: ThemeMode.light,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.light_mode_rounded,
                    size: 14,
                    color: context.hx.onSurfaceVariant,
                  ),
                  const SizedBox(width: 6),
                  const Text('Light'),
                ],
              ),
            ),
            DropdownMenuItem(
              value: ThemeMode.system,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.brightness_auto_rounded,
                    size: 14,
                    color: context.hx.onSurfaceVariant,
                  ),
                  const SizedBox(width: 6),
                  const Text('System'),
                ],
              ),
            ),
            DropdownMenuItem(
              value: ThemeMode.dark,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.dark_mode_rounded,
                    size: 14,
                    color: context.hx.onSurfaceVariant,
                  ),
                  const SizedBox(width: 6),
                  const Text('Dark'),
                ],
              ),
            ),
          ],
          onChanged: (newMode) {
            if (newMode != null) {
              onChanged(newMode);
            }
          },
        ),
      ),
    );
  }
}

/// Light / System / Dark dropdown for the app theme.
class ThemeModeToggle extends ConsumerWidget {
  const ThemeModeToggle({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return ThemeModeDropdown(
      value: ref.watch(themeModeProvider),
      onChanged: ref.read(themeModeProvider.notifier).set,
    );
  }
}

/// Accent colour dropdown with a preview dot per option.
class AppColorThemeToggle extends ConsumerWidget {
  const AppColorThemeToggle({super.key});

  static Color _previewColor(AppColorTheme theme) => switch (theme) {
    AppColorTheme.classicBlue => const Color(0xFF0A84FF),
    AppColorTheme.siriousBlack => const Color(0xFF27272A),
    AppColorTheme.vividGreen => const Color(0xFF10B981),
    AppColorTheme.sunnyYellow => const Color(0xFFF59E0B),
    AppColorTheme.pinky => const Color(0xFFFF2D55),
  };

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final activeTheme = ref.watch(appColorThemeProvider);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 2),
      decoration: BoxDecoration(
        color: context.hx.surfaceVariant,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: context.hx.outlineVariant.withValues(alpha: 0.5),
        ),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<AppColorTheme>(
          value: activeTheme,
          isDense: true,
          icon: Icon(
            Icons.arrow_drop_down_rounded,
            color: context.hx.onSurfaceVariant,
            size: 20,
          ),
          dropdownColor: context.hx.surfaceContainer,
          borderRadius: BorderRadius.circular(16),
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w500,
            color: context.hx.onSurface,
          ),
          items: AppColorTheme.values.map((theme) {
            return DropdownMenuItem(
              value: theme,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 10,
                    height: 10,
                    decoration: BoxDecoration(
                      color: _previewColor(theme),
                      shape: BoxShape.circle,
                      border: theme == AppColorTheme.siriousBlack
                          ? Border.all(
                              color: context.hx.outlineVariant,
                              width: 1,
                            )
                          : null,
                    ),
                  ),
                  const SizedBox(width: 6),
                  Text(theme.label),
                ],
              ),
            );
          }).toList(),
          onChanged: (newTheme) {
            if (newTheme != null) {
              ref.read(appColorThemeProvider.notifier).set(newTheme);
            }
          },
        ),
      ),
    );
  }
}

/// Dark / Light / App theme picker for the top-dropping notification pill.
class NotificationStyleToggle extends ConsumerWidget {
  const NotificationStyleToggle({super.key});

  static IconData _icon(NotificationStyle s) => switch (s) {
    NotificationStyle.dark => Icons.dark_mode_rounded,
    NotificationStyle.light => Icons.light_mode_rounded,
    NotificationStyle.app => Icons.palette_rounded,
  };

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 2),
      decoration: BoxDecoration(
        color: context.hx.surfaceVariant,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: context.hx.outlineVariant.withValues(alpha: 0.5),
        ),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<NotificationStyle>(
          value: ref.watch(notificationStyleProvider),
          isDense: true,
          icon: Icon(
            Icons.arrow_drop_down_rounded,
            color: context.hx.onSurfaceVariant,
            size: 20,
          ),
          dropdownColor: context.hx.surfaceContainer,
          borderRadius: BorderRadius.circular(16),
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w500,
            color: context.hx.onSurface,
          ),
          items: [
            for (final style in NotificationStyle.values)
              DropdownMenuItem(
                value: style,
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      _icon(style),
                      size: 14,
                      color: context.hx.onSurfaceVariant,
                    ),
                    const SizedBox(width: 6),
                    Text(style.label),
                  ],
                ),
              ),
          ],
          onChanged: (style) {
            if (style != null) {
              ref.read(notificationStyleProvider.notifier).set(style);
            }
          },
        ),
      ),
    );
  }
}

/// Light / System / Dark dropdown for the Android home-screen widgets.
class WidgetThemeModeToggle extends ConsumerWidget {
  const WidgetThemeModeToggle({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final appearance = ref.watch(widgetAppearanceProvider);
    final appMode = ref.watch(themeModeProvider);
    return ThemeModeDropdown(
      value: appearance.resolvedMode(appMode),
      onChanged: ref.read(widgetAppearanceProvider.notifier).setThemeMode,
    );
  }
}

/// A settings row with its control on a second line, for controls too wide to
/// sit beside the label.
class _StackedSettingsTile extends StatelessWidget {
  const _StackedSettingsTile({
    required this.icon,
    required this.label,
    required this.child,
    this.value,
    this.caption,
  });

  final IconData icon;
  final String label;
  final String? value;
  final String? caption;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 22, color: context.hx.onSurfaceVariant),
              const SizedBox(width: 16),
              Expanded(
                child: Text(
                  label,
                  style: text.bodyLarge?.copyWith(fontWeight: FontWeight.w500),
                ),
              ),
              if (value != null)
                Text(
                  value!,
                  style: text.bodyMedium?.copyWith(
                    color: context.hx.onSurfaceVariant,
                    fontWeight: FontWeight.w600,
                  ),
                ),
            ],
          ),
          if (caption != null)
            Padding(
              padding: const EdgeInsets.only(left: 38, top: 2),
              child: Text(
                caption!,
                style: text.bodySmall?.copyWith(
                  color: context.hx.onSurfaceVariant,
                ),
              ),
            ),
          const SizedBox(height: 4),
          child,
        ],
      ),
    );
  }
}

/// 1 (light glass) to 3 (most transparent) slider for home-screen widgets.
class WidgetTransparencyTile extends ConsumerWidget {
  const WidgetTransparencyTile({super.key, this.level, this.onChanged});

  final int? level;
  final ValueChanged<int>? onChanged;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final effectiveLevel =
        level ?? ref.watch(widgetAppearanceProvider).transparency;
    final handleChanged =
        onChanged ??
        ref.read(widgetAppearanceProvider.notifier).setTransparency;

    return _StackedSettingsTile(
      icon: Icons.blur_on_rounded,
      label: 'Transparency',
      value: '$effectiveLevel',
      child: Slider(
        value: effectiveLevel.toDouble(),
        min: WidgetAppearance.minTransparency.toDouble(),
        max: WidgetAppearance.maxTransparency.toDouble(),
        divisions:
            WidgetAppearance.maxTransparency - WidgetAppearance.minTransparency,
        label: '$effectiveLevel',
        onChanged: (v) {
          final next = v.round();
          if (next == effectiveLevel) return;
          Haptics.selection();
          handleChanged(next);
        },
      ),
    );
  }
}

/// Corner shape of the small (2x1) home-screen widgets.
class WidgetShapeTile extends ConsumerWidget {
  const WidgetShapeTile({super.key, this.shape, this.onChanged});

  final WidgetCornerShape? shape;
  final ValueChanged<WidgetCornerShape>? onChanged;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final effectiveShape = shape ?? ref.watch(widgetAppearanceProvider).shape;
    final handleChanged =
        onChanged ?? ref.read(widgetAppearanceProvider.notifier).setShape;
    final shapeLabel = effectiveShape.label;

    return _StackedSettingsTile(
      icon: Icons.rounded_corner_rounded,
      label: 'Small widget shape',
      value: shapeLabel,
      caption: 'Applies to the one-row widgets',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Slider(
            value: effectiveShape.index.toDouble(),
            min: 0,
            max: 2,
            divisions: 2,
            label: shapeLabel,
            onChanged: (v) {
              final next = WidgetCornerShape.values[v.round()];
              if (next == effectiveShape) return;
              Haptics.selection();
              handleChanged(next);
            },
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'Squircle',
                  style: Theme.of(context).textTheme.labelSmall?.copyWith(
                    color: effectiveShape == WidgetCornerShape.squircle
                        ? Theme.of(context).colorScheme.primary
                        : Theme.of(context).colorScheme.outline,
                    fontWeight: effectiveShape == WidgetCornerShape.squircle
                        ? FontWeight.bold
                        : FontWeight.normal,
                  ),
                ),
                Text(
                  'Rounded',
                  style: Theme.of(context).textTheme.labelSmall?.copyWith(
                    color: effectiveShape == WidgetCornerShape.rounded
                        ? Theme.of(context).colorScheme.primary
                        : Theme.of(context).colorScheme.outline,
                    fontWeight: effectiveShape == WidgetCornerShape.rounded
                        ? FontWeight.bold
                        : FontWeight.normal,
                  ),
                ),
                Text(
                  'Pill',
                  style: Theme.of(context).textTheme.labelSmall?.copyWith(
                    color: effectiveShape == WidgetCornerShape.pill
                        ? Theme.of(context).colorScheme.primary
                        : Theme.of(context).colorScheme.outline,
                    fontWeight: effectiveShape == WidgetCornerShape.pill
                        ? FontWeight.bold
                        : FontWeight.normal,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Complete appearance settings card containing Theme, App Colors,
/// Notification Theme, Units, Widget Theme, Widget Transparency, and Widget Shape.
class AppAppearanceCard extends ConsumerWidget {
  const AppAppearanceCard({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isMetric = ref.watch(unitsProvider) == MeasurementUnit.metric;
    final theme = Theme.of(context);

    return HxSettingsCard(
      children: [
        const HxSettingsTile(
          icon: Icons.dark_mode_rounded,
          label: 'Theme',
          trailing: ThemeModeToggle(),
        ),
        const HxSettingsDivider(),
        const HxSettingsTile(
          icon: Icons.palette_outlined,
          label: 'App Colors',
          trailing: AppColorThemeToggle(),
        ),
        const HxSettingsDivider(),
        const HxSettingsTile(
          icon: Icons.notifications_active_outlined,
          label: 'Notification Theme',
          trailing: NotificationStyleToggle(),
        ),
        const HxSettingsDivider(),
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
        const HxSettingsDivider(),
        const HxSettingsTile(
          icon: Icons.widgets_outlined,
          label: 'Widget Theme',
          trailing: WidgetThemeModeToggle(),
        ),
        const HxSettingsDivider(),
        const WidgetTransparencyTile(),
        const HxSettingsDivider(),
        const WidgetShapeTile(),
      ],
    );
  }
}
