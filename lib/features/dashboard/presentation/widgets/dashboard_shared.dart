import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../theme/tokens/tokens.dart';
import '../../../../ui/ui.dart';
import '../../domain/dashboard_config.dart';
import '../dashboard_providers.dart';

/// Dashboard card surface. Now delegates to the shared [HxCard] primitive,
/// respecting the user-configured [DashboardCardShape].
Widget dashboardCard({
  required Widget child,
  VoidCallback? onTap,
  Color? accent,
  double? radius,
  EdgeInsets? padding,
  Gradient? gradient,
}) =>
    Consumer(
      builder: (context, ref, _) {
        final shape = ref.watch(dashboardCardShapeProvider);
        return HxCard(
          onTap: onTap,
          accent: accent,
          radius: radius ?? shape.cardRadius,
          padding: padding ?? const EdgeInsets.all(HxSpace.x5),
          gradient: gradient,
          child: child,
        );
      },
    );

/// Dashboard "pill" surface used by compact single-line and mini widgets
/// (CNS Load, Total Volume, Streaks). Adapts to the user-selected [DashboardCardShape]
/// so all widgets on the dashboard share cohesive geometry.
class DashboardPill extends ConsumerWidget {
  final Widget child;
  final VoidCallback? onTap;
  final double? radius;
  final EdgeInsets padding;
  final Color? color;
  final Gradient? gradient;

  const DashboardPill({
    super.key,
    required this.child,
    this.onTap,
    this.radius,
    this.padding = const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
    this.color,
    this.gradient,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final hx = context.hx;
    final shape = ref.watch(dashboardCardShapeProvider);
    final effectiveRadius = radius ?? shape.pillRadius;

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
        borderRadius: BorderRadius.circular(effectiveRadius),
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
          borderRadius: BorderRadius.circular(effectiveRadius),
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
