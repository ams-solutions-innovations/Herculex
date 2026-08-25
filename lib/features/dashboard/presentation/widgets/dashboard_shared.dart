import 'package:flutter/material.dart';

import '../../../../theme/tokens/tokens.dart';
import '../../../../ui/ui.dart';
/// Dashboard card surface. Now delegates to the shared [HxCard] primitive —
/// this helper stays only so the ~14 call sites below read unchanged.
Widget dashboardCard({
  required Widget child,
  VoidCallback? onTap,
  Color? accent,
  double? radius,
  EdgeInsets? padding,
  Gradient? gradient,
}) =>
    HxCard(
      onTap: onTap,
      accent: accent,
      radius: radius,
      padding: padding ?? const EdgeInsets.all(HxSpace.x5),
      gradient: gradient,
      child: child,
    );

/// Fully-rounded "pill" surface used by the compact single-line dashboard
/// widgets (CNS Load, Total Volume …). [radius] animates so a pill can open
/// into a card without the shape jumping.
class DashboardPill extends StatelessWidget {
  final Widget child;
  final VoidCallback? onTap;
  final double radius;
  final EdgeInsets padding;
  final Color? color;
  final Gradient? gradient;

  const DashboardPill({
    super.key,
    required this.child,
    this.onTap,
    this.radius = 999,
    this.padding = const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
    this.color,
    this.gradient,
  });

  @override
  Widget build(BuildContext context) {
    final hx = context.hx;
    final pillGradient = gradient ??
        (color != null
            ? LinearGradient(
                colors: [
                  color!.withValues(alpha: hx.isDark ? 0.16 : 0.12),
                  hx.surfaceContainerLowest,
                ],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              )
            : null);

    return AnimatedContainer(
      duration: const Duration(milliseconds: 220),
      curve: Curves.easeOutCubic,
      width: double.infinity,
      decoration: BoxDecoration(
        gradient: pillGradient,
        color: pillGradient == null ? hx.surfaceContainerLowest : null,
        borderRadius: BorderRadius.circular(radius),
        border: Border.all(
          color: color?.withValues(alpha: 0.3) ??
              hx.outlineVariant.withValues(alpha: 0.3),
        ),
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
