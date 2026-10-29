import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:herculex/app/router/routes.dart';
import 'package:herculex/design_system/components/hx_rail_tool.dart';

/// What the wide-window rail offers below the four home tabs: the screens a
/// phone reaches through Profile and its cards, one click away on a desktop.
///
/// Shared by the main shell's rail and the one pushed screens draw beside
/// themselves (`HxShellNavigationScope`).
const railTools = <HxRailTool>[
  HxRailTool(
    icon: Icons.menu_book_rounded,
    label: 'Exercise library',
    path: AppRoutes.exercises,
    // An exercise's own page belongs to the library.
    alsoUnder: ['/exercise'],
  ),
  HxRailTool(
    icon: Icons.analytics_rounded,
    label: 'Insights',
    path: AppRoutes.insights,
  ),
  HxRailTool(icon: Icons.science_outlined, label: 'Labs', path: AppRoutes.labs),
  HxRailTool(
    icon: Icons.straighten,
    label: 'Body measurements',
    path: AppRoutes.measurements,
  ),
  HxRailTool(
    icon: Icons.timer_outlined,
    label: 'Fasting',
    path: AppRoutes.fasting,
  ),
  HxRailTool(
    icon: Icons.medication_outlined,
    label: 'Supplements',
    path: AppRoutes.supplements,
  ),
];

/// Opens [tool] directly as a top-level route in the shell: no intermediate
/// screen flashes, duplicate pushes, or stacked tools.
void openRailTool(GoRouter router, HxRailTool tool) {
  router.go(tool.path);
}

/// Index into [railTools] of the tool whose screen [location] is, or null on
/// the home tabs and on screens that belong to none of them.
int? railToolIndexFor(String location) {
  final index = railTools.indexWhere((tool) => tool.owns(location));
  return index < 0 ? null : index;
}
