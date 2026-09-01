part of '../profile_view.dart';

class _SettingsCard extends StatelessWidget {
  final List<Widget> children;
  const _SettingsCard({required this.children});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: context.hx.surfaceContainer,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: context.hx.outlineVariant.withValues(alpha: 0.4),
        ),
      ),
      child: Column(children: children),
    );
  }
}

class _SettingsDivider extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Divider(
      height: 1,
      indent: 56,
      color: context.hx.outlineVariant.withValues(alpha: 0.4),
    );
  }
}

class _SettingsTile extends StatelessWidget {
  final IconData icon;
  final String label;
  final Widget? trailing;
  final Color? iconColor;
  final Color? labelColor;
  final VoidCallback? onTap;

  const _SettingsTile({
    required this.icon,
    required this.label,
    this.trailing,
    this.iconColor,
    this.labelColor,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(20),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        child: Row(
          children: [
            Icon(
              icon,
              size: 22,
              color: iconColor ?? context.hx.onSurfaceVariant,
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Text(
                label,
                style: theme.textTheme.bodyLarge?.copyWith(
                  color: labelColor,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
            ?trailing,
          ],
        ),
      ),
    );
  }
}

class _ThemeToggle extends ConsumerWidget {
  const _ThemeToggle();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final mode = ref.watch(themeModeProvider);

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
          value: mode,
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
              ref.read(themeModeProvider.notifier).set(newMode);
            }
          },
        ),
      ),
    );
  }
}

class _AppColorToggle extends ConsumerWidget {
  const _AppColorToggle();

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
