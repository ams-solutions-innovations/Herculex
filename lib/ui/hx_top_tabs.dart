import 'package:flutter/material.dart';

import '../theme/haptics.dart';
import '../theme/tokens/tokens.dart';

/// Segmented control for navigation *within* a section.
///
/// The app keeps one global bottom bar; anything that switches context inside
/// a section belongs up here instead of in a second bottom bar.
class HxTopTabs extends StatelessWidget {
  const HxTopTabs({
    super.key,
    required this.labels,
    required this.index,
    required this.onChanged,
    this.accent,
  });

  final List<String> labels;
  final int index;
  final ValueChanged<int> onChanged;

  /// Domain color for the active segment; defaults to the brand color.
  final Color? accent;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final hx = context.hx;
    final accent = this.accent ?? hx.primary;

    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: hx.surfaceVariant.withValues(alpha: hx.isDark ? 0.6 : 0.8),
        borderRadius: HxRadius.pillAll,
      ),
      child: Row(
        children: [
          for (var i = 0; i < labels.length; i++)
            Expanded(
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () {
                  if (i == index) return;
                  Haptics.selection();
                  onChanged(i);
                },
                child: AnimatedContainer(
                  duration: HxMotion.base,
                  curve: HxMotion.standard,
                  padding: const EdgeInsets.symmetric(vertical: HxSpace.x2 + 2),
                  decoration: BoxDecoration(
                    color: i == index ? accent : Colors.transparent,
                    borderRadius: HxRadius.pillAll,
                  ),
                  child: Text(
                    labels[i],
                    textAlign: TextAlign.center,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.labelMedium?.copyWith(
                      color: i == index ? hx.onPrimary : hx.secondary,
                      fontWeight:
                          i == index ? FontWeight.w700 : FontWeight.w500,
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
