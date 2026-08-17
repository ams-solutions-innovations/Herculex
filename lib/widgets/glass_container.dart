import 'package:flutter/material.dart';

import '../theme/tokens/tokens.dart';
import '../ui/hx_glass.dart';

/// Frosted surface used across the dashboard, health and programs cards.
///
/// Now a thin adapter over [HxGlass] so the blur, fill and border come from
/// the token palette instead of the hardcoded hex fallbacks this widget used
/// to carry (which never matched light mode).
class GlassContainer extends StatelessWidget {
  final Widget child;
  final double borderRadius;
  final EdgeInsets padding;
  final double blur;

  /// Legacy sentinel: [Colors.white10] means "use the themed fill".
  final Color color;
  final Border? border;

  const GlassContainer({
    super.key,
    required this.child,
    this.borderRadius = HxRadius.xl,
    this.padding = const EdgeInsets.all(HxSpace.x4),
    this.blur = 15.0,
    this.color = Colors.white10,
    this.border,
  });

  @override
  Widget build(BuildContext context) {
    return HxGlass(
      borderRadius: BorderRadius.circular(borderRadius),
      padding: padding,
      blur: blur,
      fill: color == Colors.white10 ? null : color,
      borderColor: border?.top.color,
      child: child,
    );
  }
}
