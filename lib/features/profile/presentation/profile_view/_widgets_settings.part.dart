part of '../profile_view.dart';

/// The Widgets section: how the Android home-screen widgets look. Changes are
/// pushed to them by `widgetThemeSyncControllerProvider`.
class _WidgetsSettingsCard extends ConsumerWidget {
  const _WidgetsSettingsCard();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final appearance = ref.watch(widgetAppearanceProvider);
    final appMode = ref.watch(themeModeProvider);
    final notifier = ref.read(widgetAppearanceProvider.notifier);

    return _SettingsCard(
      children: [
        _SettingsTile(
          icon: Icons.widgets_outlined,
          label: 'Widget theme',
          trailing: _ThemeModeDropdown(
            value: appearance.resolvedMode(appMode),
            onChanged: notifier.setThemeMode,
          ),
        ),
        _SettingsDivider(),
        _TransparencyTile(
          level: appearance.transparency,
          onChanged: notifier.setTransparency,
        ),
        _SettingsDivider(),
        _ShapeTile(shape: appearance.shape, onChanged: notifier.setShape),
      ],
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

/// 1 (light glass) to 3 (most transparent).
class _TransparencyTile extends StatelessWidget {
  const _TransparencyTile({required this.level, required this.onChanged});

  final int level;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    return _StackedSettingsTile(
      icon: Icons.blur_on_rounded,
      label: 'Transparency',
      value: '$level',
      child: Slider(
        value: level.toDouble(),
        min: WidgetAppearance.minTransparency.toDouble(),
        max: WidgetAppearance.maxTransparency.toDouble(),
        divisions:
            WidgetAppearance.maxTransparency - WidgetAppearance.minTransparency,
        label: '$level',
        onChanged: (v) {
          final next = v.round();
          if (next == level) return;
          Haptics.selection();
          onChanged(next);
        },
      ),
    );
  }
}

/// Corner shape of the small (2x1) widgets.
class _ShapeTile extends StatelessWidget {
  const _ShapeTile({required this.shape, required this.onChanged});

  final WidgetCornerShape shape;
  final ValueChanged<WidgetCornerShape> onChanged;

  @override
  Widget build(BuildContext context) {
    return _StackedSettingsTile(
      icon: Icons.rounded_corner_rounded,
      label: 'Small widget shape',
      caption: 'Applies to the one-row widgets',
      child: Padding(
        padding: const EdgeInsets.only(top: 8),
        child: SizedBox(
          width: double.infinity,
          child: SegmentedButton<WidgetCornerShape>(
            showSelectedIcon: false,
            segments: const [
              ButtonSegment(
                value: WidgetCornerShape.squircle,
                label: Text('Squircle'),
              ),
              ButtonSegment(value: WidgetCornerShape.pill, label: Text('Pill')),
            ],
            selected: {shape},
            onSelectionChanged: (s) {
              Haptics.selection();
              onChanged(s.single);
            },
          ),
        ),
      ),
    );
  }
}
