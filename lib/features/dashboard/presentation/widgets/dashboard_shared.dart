import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:herculex/design_system/components/components.dart';
import 'package:herculex/design_system/tokens/tokens.dart';
import 'package:herculex/features/dashboard/application/dashboard_providers.dart';
import 'package:herculex/features/dashboard/domain/dashboard_config.dart';

/// Dashboard card surface. Now delegates to the shared [HxCard] primitive,
/// respecting the user-configured [DashboardCardShape].
Widget dashboardCard({
  required Widget child,
  VoidCallback? onTap,
  Color? accent,
  double? radius,
  EdgeInsets? padding,
  Gradient? gradient,
}) => Consumer(
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

    final pillGradient =
        gradient ??
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
          color:
              color?.withValues(alpha: 0.3) ??
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

Widget dashboardTitle(BuildContext context, String text) => Row(
  mainAxisSize: MainAxisSize.min,
  children: [
    Icon(_dashboardTitleIcon(text), size: 17, color: context.hx.primary),
    const SizedBox(width: HxSpace.x1),
    Flexible(
      child: Text(
        text,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: Theme.of(
          context,
        ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
      ),
    ),
  ],
);

IconData _dashboardTitleIcon(String title) {
  final value = title.toLowerCase();
  if (value.contains('volume')) return Icons.bar_chart_rounded;
  if (value.contains('bodyweight')) return Icons.monitor_weight_outlined;
  if (value.contains('workout') || value.contains('plan')) {
    return Icons.fitness_center_rounded;
  }
  if (value.contains('calorie') || value.contains('remaining')) {
    return Icons.local_fire_department_outlined;
  }
  if (value.contains('recovery') || value.contains('cns')) {
    return Icons.favorite_border_rounded;
  }
  if (value.contains('nutrition') || value.contains('macro')) {
    return Icons.restaurant_menu_rounded;
  }
  return Icons.insights_rounded;
}

/// Dynamically fades the left and right edges during horizontal swiping of
/// stacked dashboard widgets so cards never get clipped with a harsh vertical
/// straight line against the container boundary.
class StackedEdgeFadeMask extends StatelessWidget {
  const StackedEdgeFadeMask({
    super.key,
    required this.controller,
    required this.child,
  });

  final PageController controller;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: controller,
      builder: (context, child) {
        double fadeFactor = 0.0;
        if (controller.hasClients &&
            controller.positions.length == 1 &&
            controller.position.hasContentDimensions) {
          final page = controller.page;
          if (page != null) {
            final offsetFromPage = (page - page.round()).abs();
            final normalized = (offsetFromPage / 0.12).clamp(0.0, 1.0);
            fadeFactor = Curves.easeOutCubic.transform(normalized);
          }
        }

        return ShaderMask(
          shaderCallback: (rect) {
            if (rect.width <= 0 || rect.height <= 0 || fadeFactor <= 0.001) {
              return const LinearGradient(
                colors: [Colors.white, Colors.white],
              ).createShader(rect);
            }

            final fadeWidth = (rect.width * 0.12).clamp(28.0, 44.0);
            final fadeFraction = (fadeWidth / rect.width).clamp(0.01, 0.45);
            final edgeAlpha = (1.0 - fadeFactor).clamp(0.0, 1.0);

            return LinearGradient(
              begin: Alignment.centerLeft,
              end: Alignment.centerRight,
              colors: [
                Colors.white.withValues(alpha: edgeAlpha),
                Colors.white,
                Colors.white,
                Colors.white.withValues(alpha: edgeAlpha),
              ],
              stops: [0.0, fadeFraction, 1.0 - fadeFraction, 1.0],
            ).createShader(rect);
          },
          blendMode: BlendMode.dstIn,
          child: child,
        );
      },
      child: child,
    );
  }
}
