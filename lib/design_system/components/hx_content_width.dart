import 'dart:math' as math;

import 'package:flutter/widgets.dart';
import 'package:herculex/design_system/tokens/hx_breakpoints.dart';

/// Centres [child] and stops it growing past [maxWidth], so phone-first
/// screens stay readable in a wide browser window instead of stretching a
/// meal list or a set table across 2000 pixels.
///
/// The background (the app-wide gradient) still fills the window; only the
/// content column is limited. The height is passed through unchanged, so a
/// scrolling screen still fills it.
class HxContentWidth extends StatelessWidget {
  const HxContentWidth({
    super.key,
    this.maxWidth = HxBreakpoints.readingMax,
    required this.child,
  });

  final double maxWidth;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) => Center(
        child: SizedBox(
          width: math.min(maxWidth, constraints.maxWidth),
          height: constraints.hasBoundedHeight ? constraints.maxHeight : null,
          child: child,
        ),
      ),
    );
  }
}
