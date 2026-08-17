import 'package:flutter/material.dart';

import '../../../../theme/colors.dart';
import '../../../../ui/ui.dart';
/// Dashboard card surface. Now delegates to the shared [HxCard] primitive —
/// this helper stays only so the ~14 call sites below read unchanged.
Widget dashboardCard({required Widget child, VoidCallback? onTap}) =>
    HxCard(onTap: onTap, child: child);

/// Fully-rounded "pill" surface used by the compact single-line dashboard
/// widgets (CNS Load, Total Volume …). [radius] animates so a pill can open
/// into a card without the shape jumping.
class DashboardPill extends StatelessWidget {
  final Widget child;
  final VoidCallback? onTap;
  final double radius;
  final EdgeInsets padding;

  const DashboardPill({
    required this.child,
    this.onTap,
    this.radius = 999,
    this.padding = const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
  });

  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 220),
      curve: Curves.easeOutCubic,
      width: double.infinity,
      decoration: BoxDecoration(
        color: AppColors.surfaceContainerLowest,
        borderRadius: BorderRadius.circular(radius),
        border:
            Border.all(color: AppColors.outlineVariant.withValues(alpha: 0.3)),
      ),
      clipBehavior: Clip.antiAlias,
      child: Material(
        type: MaterialType.transparency,
        child: InkWell(
          onTap: onTap,
          child: Padding(padding: padding, child: child),
        ),
      ),
    );
  }
}

Widget dashboardTitle(BuildContext context, String text) => Text(text,
    style: Theme.of(context)
        .textTheme
        .titleMedium
        ?.copyWith(fontWeight: FontWeight.bold));
