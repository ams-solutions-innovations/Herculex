import 'package:flutter/material.dart';

import '../theme/haptics.dart';
import '../theme/tokens/tokens.dart';
import 'hx_glass.dart';

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
                padding: const EdgeInsets.symmetric(horizontal: HxSpace.x2),
                child: LayoutBuilder(
                  builder: (context, constraints) {
                    const bubbleSize = 44.0;
                    final slotWidth =
                        constraints.maxWidth / destinations.length;
                    final bubbleLeft = slotWidth * currentIndex +
                        (slotWidth - bubbleSize) / 2;
                    final bubbleTop =
                        (constraints.maxHeight - bubbleSize) / 2;

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
            _QuickAddButton(
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

/// Floats outside the main pill, in its own tinted glass so it never reads
/// as a fifth destination.
class _QuickAddButton extends StatelessWidget {
  const _QuickAddButton({
    required this.open,
    required this.onTap,
    required this.size,
  });

  final bool open;
  final VoidCallback onTap;
  final double size;

  @override
  Widget build(BuildContext context) {
    final hx = context.hx;

    return GestureDetector(
      onTap: () {
        Haptics.selection();
        onTap();
      },
      behavior: HitTestBehavior.opaque,
      child: SizedBox(
        width: size,
        height: size,
        child: HxGlass(
          shape: BoxShape.circle,
          padding: EdgeInsets.zero,
          fill: hx.quickAdd.withValues(alpha: open ? 0.32 : 0.22),
          borderColor: hx.quickAdd.withValues(alpha: 0.55),
          child: Center(
            child: AnimatedRotation(
              duration: HxMotion.base,
              curve: HxMotion.standard,
              turns: open ? 0.125 : 0,
              child: Icon(Icons.add_rounded, color: hx.quickAdd, size: 28),
            ),
          ),
        ),
      ),
    );
  }
}
