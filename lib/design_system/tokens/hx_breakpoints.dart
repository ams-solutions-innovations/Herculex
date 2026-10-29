import 'package:flutter/widgets.dart';

/// Window-size breakpoints for the wide (desktop browser) layout.
///
/// The phone layout is the design; these only decide when there is room to
/// move the navigation to the side and when content stops stretching.
/// Values follow Material 3's window size classes.
abstract final class HxBreakpoints {
  /// Tablet threshold.
  static const double tablet = 768;

  /// From here the bottom nav bar becomes a side rail (M3 "expanded").
  static const double rail = 840;

  /// Comfortable reading width for single-column screens: diaries, forms,
  /// lists, pushed detail screens.
  static const double readingMax = 760;

  /// Widest a multi-column screen (the dashboard grid) grows.
  static const double wideMax = 1280;

  /// Content width from which the dashboard grid gets four columns.
  static const double dashboardFourColumns = 900;

  /// Content width from which lists of cards (exercise library, templates,
  /// workout history) switch from one column to a grid.
  static const double twoColumns = 880;

  /// Content width from which a list-and-detail screen (the programs
  /// calendar with its "coming up" panel) puts the two side by side.
  static const double splitView = 1000;

  /// Wide desktop threshold.
  static const double desktop = 1080;

  /// Whether [context] is wide (tablet or desktop).
  static bool isWide(BuildContext context) =>
      MediaQuery.sizeOf(context).width >= tablet;
}
