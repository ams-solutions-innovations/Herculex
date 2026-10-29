import 'package:flutter/material.dart';
import 'package:herculex/design_system/components/hx_layout_scope.dart';
import 'package:herculex/design_system/components/hx_nav_rail.dart';
import 'package:herculex/design_system/tokens/tokens.dart';

/// How much of a pushed screen the main navigation rail takes on this window.
typedef HxRailLayout = ({bool shown, double inset});

/// Keeps the main navigation rail on the left of a pushed screen on wide web
/// windows, so no page is a dead end without a menu. Does nothing where the
/// shell has no rail — phones, narrow windows, native apps — or when the
/// screen already sits inside the main shell's own rail.
///
/// [HxScreenShell] does this itself; wrap a screen that builds its own
/// `Scaffold` in this instead.
class HxRailFrame extends StatelessWidget {
  const HxRailFrame({super.key, required this.child});

  final Widget child;

  /// Whether the rail shows here, and how far content must stay from the left
  /// edge to clear it (the rail plus one margin; the page keeps its own
  /// gutter).
  static HxRailLayout layoutOf(BuildContext context) {
    final scope = HxShellNavigationScope.maybeOf(context);
    final width = MediaQuery.sizeOf(context).width;
    final shown =
        scope != null &&
        scope.enabled &&
        width >= HxBreakpoints.rail &&
        HxLayoutScope.placementOf(context) != HxNavPlacement.rail;
    return (
      shown: shown,
      inset: shown ? HxNavRail.clearance - HxNavRail.margin : 0.0,
    );
  }

  /// The rail itself, to place at the left of a [Stack].
  static Widget rail(BuildContext context, HxRailLayout layout) {
    final scope = HxShellNavigationScope.maybeOf(context)!;
    return Positioned(
      left: HxNavRail.margin,
      top: HxNavRail.margin,
      bottom: HxNavRail.margin,
      child: HxNavRail(
        currentIndex: scope.currentTool == null ? scope.currentIndex : null,
        onTap: scope.onSelectTab,
        tools: scope.tools,
        currentTool: scope.currentTool,
        onToolTap: scope.onSelectTool,
        leading: scope.leading,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final layout = layoutOf(context);
    if (!layout.shown) return child;
    return Stack(
      children: [
        Positioned.fill(left: layout.inset, child: child),
        rail(context, layout),
      ],
    );
  }
}
