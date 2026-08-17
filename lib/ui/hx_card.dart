import 'package:flutter/material.dart';

import '../theme/haptics.dart';
import '../theme/tokens/tokens.dart';

/// The app's standard card surface.
///
/// Promoted from the private `_card()` helper that lived inside
/// `dashboard_widgets.dart`, which meant every other feature re-implemented
/// the same container by hand.
class HxCard extends StatelessWidget {
  const HxCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(HxSpace.x5),
    this.radius,
    this.onTap,
    this.accent,
    this.fill,
  });

  final Widget child;
  final EdgeInsets padding;

  /// Defaults to [HxRadius.xl] — the pill-family corner the app is built on.
  final double? radius;
  final VoidCallback? onTap;

  /// Tints the border and lifts the fill slightly, used to color-code a card
  /// to its domain (nutrition, training, fasting, recovery).
  final Color? accent;
  final Color? fill;

  @override
  Widget build(BuildContext context) {
    final hx = context.hx;
    final borderRadius = BorderRadius.circular(radius ?? HxRadius.xl);
    final accent = this.accent;

    final card = Container(
      width: double.infinity,
      padding: padding,
      decoration: BoxDecoration(
        color: fill ??
            (accent == null
                ? hx.surfaceContainerLowest
                : Color.alphaBlend(
                    accent.withValues(alpha: hx.isDark ? 0.06 : 0.04),
                    hx.surfaceContainerLowest,
                  )),
        borderRadius: borderRadius,
        border: Border.all(
          color: accent?.withValues(alpha: 0.35) ??
              hx.outlineVariant.withValues(alpha: 0.3),
        ),
      ),
      child: child,
    );

    if (onTap == null) return card;

    return InkWell(
      onTap: () {
        Haptics.selection();
        onTap!();
      },
      borderRadius: borderRadius,
      child: card,
    );
  }
}
