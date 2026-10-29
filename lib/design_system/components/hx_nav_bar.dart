import 'package:flutter/material.dart';
import 'package:herculex/design_system/components/hx_glass.dart';
import 'package:herculex/design_system/components/hx_layout_scope.dart';
import 'package:herculex/design_system/components/hx_quick_add_button.dart';
import 'package:herculex/design_system/theme/haptics.dart';
import 'package:herculex/design_system/tokens/tokens.dart';

/// The app's single global bottom navigation: four destinations in one
/// frosted pill, plus a separate quick-add button riding outside it on the
/// right.
///
/// Replaces `widgets/floating_nav_bar.dart`. The selection bubble is a flat
/// filled circle — no colored shadow, no halo pulse. Glass reads as frosted,
/// not glowing, and that rule extends to the quick-add button too: it is its
/// own tinted glass, not a solid fill, and its accent color is deliberately
/// distinct from both the neutral bar glass and the primary selection fill.
class HxNavBar extends StatelessWidget {
  const HxNavBar({
    super.key,
    required this.currentIndex,
    required this.onTap,
    required this.quickAddOpen,
    required this.onQuickAddTap,
  });

  static const destinations = [
    (icon: Icons.grid_view_rounded, label: 'Dashboard'),
    (icon: Icons.restaurant_rounded, label: 'Nutrition'),
    (icon: Icons.fitness_center_rounded, label: 'Workouts'),
    (icon: Icons.person_rounded, label: 'Profile'),
  ];

  final int currentIndex;
  final ValueChanged<int> onTap;
  final bool quickAddOpen;
  final VoidCallback onQuickAddTap;

  static const _barHeight = 60.0;

  /// Bottom space, above the system safe area, that content sitting under
  /// the floating bar must leave free: the bar, its margins and a small gap.
  /// Use it for bottom-anchored controls (the workout action bar, the
  /// full-screen workout's Complete Set button) so they never crowd it.
  static const double clearance = _barHeight + HxSpace.x4 * 2 + 12;

  /// [clearance] where the bottom bar is shown; just a margin where the
  /// navigation is a side rail ([HxLayoutScope]) and the bottom is free.
  static double clearanceOf(BuildContext context) =>
      HxLayoutScope.placementOf(context) == HxNavPlacement.rail
      ? HxSpace.x8
      : clearance;

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.paddingOf(context).bottom;
    return Padding(
      padding: EdgeInsets.only(
        left: HxSpace.x4,
        right: HxSpace.x4,
        top: HxSpace.x4,
        bottom: bottomInset > 0 ? bottomInset + HxSpace.x2 : HxSpace.x4,
      ),
      child: SizedBox(
        height: _barHeight,
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(
              child: HxGlass(
                borderRadius: HxRadius.pillAll,
                fill: HxGlass.frostedFill(context.hx),
                borderColor: HxGlass.frostedBorder(context.hx),
                padding: const EdgeInsets.symmetric(horizontal: HxSpace.x2),
                child: LayoutBuilder(
                  builder: (context, constraints) {
                    const bubbleSize = 44.0;
                    final slotWidth =
                        constraints.maxWidth / destinations.length;
                    final bubbleLeft =
                        slotWidth * currentIndex + (slotWidth - bubbleSize) / 2;
                    final bubbleTop = (constraints.maxHeight - bubbleSize) / 2;

                    return Stack(
                      children: [
                        AnimatedPositioned(
                          duration: HxMotion.slow,
                          curve: HxMotion.emphasized,
                          left: bubbleLeft,
                          top: bubbleTop,
                          child: Container(
                            width: bubbleSize,
                            height: bubbleSize,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: context.hx.primary,
                            ),
                          ),
                        ),
                        Row(
                          children: [
                            for (var i = 0; i < destinations.length; i++)
                              Expanded(
                                child: _NavItem(
                                  item: destinations[i],
                                  selected: currentIndex == i,
                                  onTap: () => onTap(i),
                                ),
                              ),
                          ],
                        ),
                      ],
                    );
                  },
                ),
              ),
            ),
            const SizedBox(width: HxSpace.x3),
            HxQuickAddButton(
              open: quickAddOpen,
              onTap: onQuickAddTap,
              size: _barHeight,
            ),
          ],
        ),
      ),
    );
  }
}

class _NavItem extends StatelessWidget {
  const _NavItem({
    required this.item,
    required this.selected,
    required this.onTap,
  });

  final ({IconData icon, String label}) item;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final hx = context.hx;
    return Tooltip(
      message: item.label,
      child: GestureDetector(
        onTap: () {
          if (selected) return;
          Haptics.selection();
          onTap();
        },
        behavior: HitTestBehavior.opaque,
        child: Center(
          child: Icon(
            item.icon,
            size: 24,
            color: selected ? hx.onPrimary : hx.secondary,
          ),
        ),
      ),
    );
  }
}
