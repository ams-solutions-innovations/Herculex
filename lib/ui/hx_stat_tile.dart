import 'package:flutter/material.dart';

import '../theme/tokens/tokens.dart';
import 'hx_card.dart';

/// A labelled figure: caption, value (with optional target) and an optional
/// progress bar, all color-coded to [accent].
///
/// Generalised from the dashboard's macro cards so stat grids elsewhere stop
/// re-implementing the same layout.
class HxStatTile extends StatelessWidget {
  const HxStatTile({
    super.key,
    required this.label,
    required this.value,
    required this.icon,
    required this.accent,
    this.secondaryValue,
    this.progress,
    this.iconColor,
    this.onTap,
  });

  final String label;
  final String value;

  /// Rendered smaller next to [value], e.g. "/ 2400".
  final String? secondaryValue;
  final IconData icon;

  /// Drives the icon bubble and the progress bar.
  final Color accent;

  /// Overrides the icon color when [accent] is too light to read at icon size.
  final Color? iconColor;
  final double? progress;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final hx = context.hx;
    final iconTint = iconColor ?? accent;

    return HxCard(
      padding: const EdgeInsets.all(HxSpace.x4 - 2),
      radius: HxRadius.md,
      onTap: onTap,
      child: Column(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                label,
                style: theme.textTheme.labelSmall
                    ?.copyWith(color: hx.secondary, letterSpacing: 1.0),
              ),
              Container(
                padding: const EdgeInsets.all(6),
                decoration: BoxDecoration(
                  color: iconTint.withValues(alpha: 0.15),
                  shape: BoxShape.circle,
                ),
                child: Icon(icon, size: 18, color: iconTint),
              ),
            ],
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.baseline,
                textBaseline: TextBaseline.alphabetic,
                children: [
                  Text(
                    value,
                    style: theme.textTheme.titleLarge
                        ?.copyWith(fontWeight: FontWeight.bold),
                  ),
                  if (secondaryValue != null) ...[
                    const SizedBox(width: HxSpace.x1),
                    Text(
                      secondaryValue!,
                      style: theme.textTheme.bodySmall
                          ?.copyWith(color: hx.secondary),
                    ),
                  ],
                ],
              ),
              if (progress != null) ...[
                const SizedBox(height: HxSpace.x2),
                LinearProgressIndicator(
                  value: progress!.clamp(0.0, 1.0),
                  backgroundColor: hx.surfaceVariant,
                  valueColor: AlwaysStoppedAnimation<Color>(accent),
                  borderRadius: BorderRadius.circular(4),
                  minHeight: 4,
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }
}
