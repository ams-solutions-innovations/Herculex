import 'dart:ui';

import 'package:flutter/material.dart';

import '../theme/tokens/tokens.dart';

/// Frosted-glass surface: a real backdrop blur behind a translucent fill with
/// a hairline border.
///
/// Deliberately has no colored shadow or bloom. Glass reads as *frosted*, not
/// *glowing* — depth comes from the blur and the border, never from emitted
/// light. Any elevation shadow must stay neutral and soft.
class HxGlass extends StatelessWidget {
  const HxGlass({
    super.key,
    required this.child,
    this.borderRadius,
    this.padding = const EdgeInsets.all(HxSpace.x4),
    this.blur = 16,
    this.fill,
    this.borderColor,
    this.shape = BoxShape.rectangle,
  });

  final Widget child;

  /// Ignored when [shape] is [BoxShape.circle]. Defaults to [HxRadius.xl].
  final BorderRadius? borderRadius;
  final EdgeInsets padding;
  final double blur;

  /// Overrides the themed translucent fill.
  final Color? fill;
  final Color? borderColor;
  final BoxShape shape;

  @override
  Widget build(BuildContext context) {
    final hx = context.hx;
    final radius = borderRadius ?? HxRadius.xlAll;
    final isCircle = shape == BoxShape.circle;

    // Dark glass sits slightly more opaque so blurred content behind it does
    // not muddy the foreground text.
    final resolvedFill =
        fill ?? hx.glassFill.withValues(alpha: hx.isDark ? 0.72 : 0.78);
    final resolvedBorder =
        borderColor ?? hx.glassBorder.withValues(alpha: hx.isDark ? 0.5 : 0.9);

    return ClipPath(
      clipper: ShapeBorderClipper(
        shape: isCircle
            ? const CircleBorder()
            : RoundedRectangleBorder(borderRadius: radius),
      ),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: blur, sigmaY: blur),
        child: Container(
          padding: padding,
          decoration: BoxDecoration(
            color: resolvedFill,
            shape: shape,
            borderRadius: isCircle ? null : radius,
            border: Border.all(color: resolvedBorder, width: 1),
          ),
          child: child,
        ),
      ),
    );
  }
}
