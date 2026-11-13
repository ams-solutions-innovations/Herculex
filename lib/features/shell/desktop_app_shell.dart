import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:herculex/app/router/router.dart' show rootNavigatorKey;
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

    // This shell is mounted in `MaterialApp.router(builder:)`, i.e. above the
    // Navigator and so above every Overlay. The rail's Tooltips (and anything
    // else that floats) need one, otherwise each rail item throws "No Overlay
    // widget found" on build and the rail is dead.
    return _ShellOverlay(
      child: Scaffold(
        backgroundColor: Colors.transparent,
        body: _buildStack(railClearance, availableContentWidth),
      ),
    );
  }

  Widget _buildStack(double railClearance, double availableContentWidth) {
    return Stack(
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
              // This shell sits above the Navigator, so its own context cannot
              // open sheets, dialogs or routes; the root navigator's can.
              action(rootNavigatorKey.currentContext ?? context, ref);
            },
          ),
        Positioned(
          left: HxNavRail.margin,
          top: HxNavRail.margin,
          bottom: HxNavRail.margin,
          child: HxNavRail(
            currentIndex: widget.currentTool == null
                ? widget.currentIndex
                : null,
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
    );
  }
}

/// Gives [child] an [Overlay] of its own. The entry is rebuilt whenever the
/// parent rebuilds, since an [OverlayEntry] otherwise holds a stale subtree.
class _ShellOverlay extends StatefulWidget {
  const _ShellOverlay({required this.child});

  final Widget child;

  @override
  State<_ShellOverlay> createState() => _ShellOverlayState();
}

class _ShellOverlayState extends State<_ShellOverlay> {
  late final OverlayEntry _entry = OverlayEntry(builder: (_) => widget.child);

  @override
  void didUpdateWidget(_ShellOverlay oldWidget) {
    super.didUpdateWidget(oldWidget);
    _entry.markNeedsBuild();
  }

  @override
  void dispose() {
    _entry
      ..remove()
      ..dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Overlay(initialEntries: [_entry]);
}
