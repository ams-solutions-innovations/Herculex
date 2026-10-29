import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:herculex/app/router/routes.dart';
import 'package:herculex/core/platform/platform_capabilities.dart';
import 'package:herculex/design_system/components/hx_layout_scope.dart';
import 'package:herculex/design_system/components/hx_nav_rail.dart';
import 'package:herculex/design_system/components/hx_rail_tool.dart';
import 'package:herculex/design_system/tokens/tokens.dart';
import 'package:herculex/features/shell/quick_add_menu.dart';

/// Top-level persistent shell for wide desktop/web windows.
///
/// Anchors the frosted navigation rail on the left and the quick-add "+"
/// button permanently, so switching between the four home tabs and any of
/// the rail tools (Exercise library, Insights, Labs, Measurements, Fasting,
/// Supplements) feels identical to switching between tabs: no page re-creation,
/// no flicker, and the "+" button is always available.
class DesktopAppShell extends ConsumerStatefulWidget {
  const DesktopAppShell({
    super.key,
    required this.child,
    required this.location,
    required this.currentIndex,
    required this.onSelectTab,
    required this.tools,
    required this.currentTool,
    required this.onSelectTool,
    this.leading,
  });

  final Widget child;
  final String location;
  final int currentIndex;
  final ValueChanged<int> onSelectTab;
  final List<HxRailTool> tools;
  final int? currentTool;
  final ValueChanged<HxRailTool> onSelectTool;
  final Widget? leading;

  @override
  ConsumerState<DesktopAppShell> createState() => _DesktopAppShellState();
}

class _DesktopAppShellState extends ConsumerState<DesktopAppShell> {
  final _quickAddMenuKey = GlobalKey<QuickAddMenuState>();
  bool _quickAddOpen = false;

  void _toggleQuickAdd() {
    if (_quickAddOpen) {
      _quickAddMenuKey.currentState?.close();
    } else {
      setState(() => _quickAddOpen = true);
    }
  }

  static const _noRailRoutes = <String>{
    AppRoutes.splash,
    AppRoutes.signIn,
    AppRoutes.resetPassword,
    AppRoutes.onboarding,
    AppRoutes.restoring,
  };

  @override
  Widget build(BuildContext context) {
    final caps = ref.watch(platformCapabilitiesProvider);
    final windowWidth = MediaQuery.sizeOf(context).width;
    final isWide = caps.isWeb && windowWidth >= HxBreakpoints.rail;
    final showRail = isWide && !_noRailRoutes.contains(widget.location);

    if (!showRail) {
      return widget.child;
    }

    const railClearance = HxNavRail.clearance;
    final availableContentWidth =
        windowWidth - (railClearance - HxNavRail.margin);

    return Scaffold(
      backgroundColor: Colors.transparent,
      body: Stack(
        children: [
          Positioned(
            left: railClearance - HxNavRail.margin,
            top: 0,
            right: 0,
            bottom: 0,
            child: HxLayoutScope(
              placement: HxNavPlacement.rail,
              child: Builder(
                builder: (context) {
                  final mq = MediaQuery.of(context);
                  return MediaQuery(
                    data: mq.copyWith(
                      size: Size(availableContentWidth, mq.size.height),
                    ),
                    child: widget.child,
                  );
                },
              ),
            ),
          ),
          if (_quickAddOpen)
            QuickAddMenu(
              key: _quickAddMenuKey,
              leftAnchor: railClearance,
              onClose: () => setState(() => _quickAddOpen = false),
              onActionSelected: (action) {
                setState(() => _quickAddOpen = false);
                action(context, ref);
              },
            ),
          Positioned(
            left: HxNavRail.margin,
            top: HxNavRail.margin,
            bottom: HxNavRail.margin,
            child: HxNavRail(
              currentIndex:
                  widget.currentTool == null ? widget.currentIndex : null,
              onTap: widget.onSelectTab,
              tools: widget.tools,
              currentTool: widget.currentTool,
              onToolTap: widget.onSelectTool,
              quickAddOpen: _quickAddOpen,
              onQuickAddTap: _toggleQuickAdd,
              leading: widget.leading,
            ),
          ),
        ],
      ),
    );
  }
}
