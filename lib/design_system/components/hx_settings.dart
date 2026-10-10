import 'package:flutter/material.dart';
import 'package:herculex/design_system/tokens/tokens.dart';

/// Small uppercase label above a [HxSettingsCard].
class HxSectionHeader extends StatelessWidget {
  final String title;
  const HxSectionHeader(this.title, {super.key});

  @override
  Widget build(BuildContext context) {
    return Text(
      title.toUpperCase(),
      style: Theme.of(context).textTheme.labelSmall?.copyWith(
        color: context.hx.onSurfaceVariant,
        letterSpacing: 1.2,
        fontWeight: FontWeight.bold,
      ),
    );
  }
}

/// Rounded surface that groups settings rows. Put [HxSettingsDivider]s between
/// the rows.
class HxSettingsCard extends StatelessWidget {
  final List<Widget> children;
  const HxSettingsCard({super.key, required this.children});

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

/// Hairline between two rows of a [HxSettingsCard], inset to clear the icon.
class HxSettingsDivider extends StatelessWidget {
  const HxSettingsDivider({super.key});

  @override
  Widget build(BuildContext context) {
    return Divider(
      height: 1,
      indent: 54,
      color: context.hx.outlineVariant.withValues(alpha: 0.3),
    );
  }
}

/// One row of a [HxSettingsCard]: icon, label, optional caption and a trailing
/// control. [chevron] is shorthand for a navigation chevron as the trailing
/// widget; an explicit [trailing] wins.
class HxSettingsTile extends StatelessWidget {
  final IconData icon;
  final String label;
  final String? subtitle;
  final Widget? trailing;
  final bool chevron;
  final Color? iconColor;
  final Color? labelColor;
  final VoidCallback? onTap;

  const HxSettingsTile({
    super.key,
    required this.icon,
    required this.label,
    this.subtitle,
    this.trailing,
    this.chevron = false,
    this.iconColor,
    this.labelColor,
    this.onTap,
  }) : _danger = false;

  /// A destructive row (delete, wipe): danger-coloured icon and label.
  const HxSettingsTile.danger({
    super.key,
    required this.icon,
    required this.label,
    this.subtitle,
    this.trailing,
    this.chevron = false,
    this.onTap,
  }) : iconColor = null,
       labelColor = null,
       _danger = true;

  // Resolved against the theme in [build], so the constructors can stay const.
  final bool _danger;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final danger = context.hx.danger;
    final Widget? end =
        trailing ??
        (chevron
            ? Icon(Icons.chevron_right, color: context.hx.onSurfaceVariant)
            : null);
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
              color: _danger
                  ? danger
                  : iconColor ?? context.hx.onSurfaceVariant,
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    label,
                    style: theme.textTheme.bodyLarge?.copyWith(
                      color: _danger ? danger : labelColor,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  if (subtitle != null) ...[
                    const SizedBox(height: 2),
                    Text(
                      subtitle!,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: context.hx.onSurfaceVariant,
                      ),
                    ),
                  ],
                ],
              ),
            ),
            ?end,
          ],
        ),
      ),
    );
  }
}
