import 'package:flutter/widgets.dart';
import 'package:herculex/design_system/components/hx_rail_tool.dart';

/// Where the app's main navigation sits.
enum HxNavPlacement {
  /// [HxNavBar] floating over the bottom of the screen — phones, narrow
  /// windows.
  bottom,

  /// [HxNavRail] down the left side — wide browser windows.
  rail,
}

/// Tells screens under the main shell which navigation they share the window
/// with, so bottom-anchored controls leave the right amount of room: a lot
/// above the floating bottom bar, almost none beside a side rail.
class HxLayoutScope extends InheritedWidget {
  const HxLayoutScope({
    super.key,
    required this.placement,
    required super.child,
  });

  final HxNavPlacement placement;

  /// [HxNavPlacement.bottom] outside any scope — the phone layout.
  static HxNavPlacement placementOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<HxLayoutScope>()?.placement ??
      HxNavPlacement.bottom;

  @override
  bool updateShouldNotify(HxLayoutScope oldWidget) =>
      placement != oldWidget.placement;
}

/// Lets pushed screens ([HxScreenShell]) show the main [HxNavRail] on wide
/// windows. The design system cannot reach the tab state or the router, so the
/// app installs this above its navigator and screens only read it; without a
/// scope (tests, previews) they draw no rail.
class HxShellNavigationScope extends InheritedWidget {
  const HxShellNavigationScope({
    super.key,
    required this.enabled,
    required this.currentIndex,
    required this.onSelectTab,
    this.tools = const [],
    this.currentTool,
    this.onSelectTool,
    this.leading,
    required super.child,
  });

  /// False where there is no side rail at all — phones and native apps.
  final bool enabled;

  /// The main tab the user last had open; highlighted on pushed screens
  /// unless one of the [tools] is the screen being shown.
  final int currentIndex;
  final ValueChanged<int> onSelectTab;

  /// The rail's extra destinations below the four tabs, the one of them whose
  /// screen is open (an index into [tools]) and how to open one.
  final List<HxRailTool> tools;
  final int? currentTool;
  final ValueChanged<HxRailTool>? onSelectTool;

  /// The logo above the destinations.
  final Widget? leading;

  static HxShellNavigationScope? maybeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<HxShellNavigationScope>();

  @override
  bool updateShouldNotify(HxShellNavigationScope oldWidget) =>
      enabled != oldWidget.enabled ||
      currentIndex != oldWidget.currentIndex ||
      currentTool != oldWidget.currentTool ||
      tools != oldWidget.tools ||
      leading != oldWidget.leading;
}
