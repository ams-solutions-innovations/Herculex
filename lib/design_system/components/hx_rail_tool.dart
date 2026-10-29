import 'package:flutter/widgets.dart';

/// A rail destination that is a screen of its own — Insights, Labs, the
/// exercise library — rather than one of the four home tabs. [path] is opaque
/// to the design system; the app decides how to open it.
@immutable
class HxRailTool {
  const HxRailTool({
    required this.icon,
    required this.label,
    required this.path,
    this.alsoUnder = const [],
  });

  final IconData icon;
  final String label;
  final String path;

  /// Other path prefixes that belong to this tool, so its detail pages keep
  /// it selected (an exercise's page sits under the library).
  final List<String> alsoUnder;

  /// Whether [location] is this tool's screen or one beneath it.
  bool owns(String location) => [
    path,
    ...alsoUnder,
  ].any((prefix) => location == prefix || location.startsWith('$prefix/'));
}
