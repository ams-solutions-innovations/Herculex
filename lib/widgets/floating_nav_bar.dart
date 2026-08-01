import 'package:flutter/material.dart';
import 'dart:ui';

import '../theme/haptics.dart';

class FloatingNavBar extends StatelessWidget {
  final int currentIndex;
  final Function(int) onTap;

  const FloatingNavBar({
    super.key,
    required this.currentIndex,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    final items = const [
      (icon: Icons.grid_view_rounded, label: "Dashboard"),
      (icon: Icons.restaurant_rounded, label: "Nutrition"),
      (icon: Icons.fitness_center_rounded, label: "Workout"),
      (icon: Icons.layers_rounded, label: "Programs"),
      (icon: Icons.person_rounded, label: "Profile"),
    ];

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 20.0),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(999.0),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 16.0, sigmaY: 16.0),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 8.0, vertical: 8.0),
            decoration: BoxDecoration(
              color: isDark
                  ? theme.colorScheme.surface.withValues(alpha: 0.85)
                  : theme.colorScheme.surface.withValues(alpha: 0.9),
              borderRadius: BorderRadius.circular(999.0),
              border: Border.all(
                color: isDark
                    ? Colors.white.withValues(alpha: 0.12)
                    : Colors.black.withValues(alpha: 0.06),
                width: 1.5,
              ),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: isDark ? 0.4 : 0.08),
                  blurRadius: 20,
                  offset: const Offset(0, 8),
                ),
              ],
            ),
            child: LayoutBuilder(
              builder: (context, constraints) {
                final totalWidth = constraints.maxWidth;
                final itemWidth = totalWidth / items.length;
                const bubbleSize = 44.0;

                // Position calculation for sliding bubbly circle
                final leftOffset =
                    itemWidth * currentIndex + (itemWidth - bubbleSize) / 2;

                return Stack(
                  alignment: Alignment.centerLeft,
                  children: [
                    // Sliding Bubbly Colored Circle Indicator
                    AnimatedPositioned(
                      duration: const Duration(milliseconds: 300),
                      curve: Curves.easeInOutCubic,
                      left: leftOffset,
                      top: 4,
                      child: Stack(
                        alignment: Alignment.center,
                        children: [
                          // Bubbly Outer Ring Pulse / Halo on selection
                          TweenAnimationBuilder<double>(
                            key: ValueKey('halo_$currentIndex'),
                            tween: Tween<double>(begin: 0.8, end: 1.2),
                            duration: const Duration(milliseconds: 300),
                            curve: Curves.easeOutCubic,
                            builder: (context, haloScale, child) {
                              final opacity = (1.2 - haloScale).clamp(0.0, 0.3);
                              return Transform.scale(
                                scale: haloScale,
                                child: Container(
                                  width: bubbleSize,
                                  height: bubbleSize,
                                  decoration: BoxDecoration(
                                    shape: BoxShape.circle,
                                    border: Border.all(
                                      color: theme.colorScheme.primary
                                          .withValues(alpha: opacity),
                                      width: 2.0,
                                    ),
                                  ),
                                ),
                              );
                            },
                          ),
                          // Bubbly Colored Circle with Smooth Scale
                          TweenAnimationBuilder<double>(
                            key: ValueKey('bubble_$currentIndex'),
                            tween: Tween<double>(begin: 0.9, end: 1.0),
                            duration: const Duration(milliseconds: 250),
                            curve: Curves.easeOutCubic,
                            builder: (context, scale, child) {
                              return Transform.scale(
                                scale: scale,
                                child: child,
                              );
                            },
                            child: Container(
                              width: bubbleSize,
                              height: bubbleSize,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                gradient: LinearGradient(
                                  colors: [
                                    theme.colorScheme.primary,
                                    theme.colorScheme.primary.withValues(
                                      alpha: 0.85,
                                    ),
                                  ],
                                  begin: Alignment.topLeft,
                                  end: Alignment.bottomRight,
                                ),
                                boxShadow: [
                                  BoxShadow(
                                    color: theme.colorScheme.primary.withValues(
                                      alpha: 0.4,
                                    ),
                                    blurRadius: 10,
                                    spreadRadius: 2,
                                    offset: const Offset(0, 3),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),

                    // Interactive Tab Items
                    Row(
                      children: List.generate(items.length, (index) {
                        final item = items[index];
                        final isSelected = currentIndex == index;

                        return Expanded(
                          child: GestureDetector(
                            onTap: () {
                              Haptics.selection();
                              onTap(index);
                            },
                            behavior: HitTestBehavior.opaque,
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                vertical: 4.0,
                              ),
                              child: SizedBox(
                                height: bubbleSize,
                                width: bubbleSize,
                                child: Center(
                                  child: TweenAnimationBuilder<double>(
                                    key: ValueKey('icon_${index}_$isSelected'),
                                    tween: Tween<double>(
                                      begin: isSelected ? 0.85 : 1.0,
                                      end: isSelected ? 1.15 : 1.0,
                                    ),
                                    duration: const Duration(milliseconds: 300),
                                    curve: isSelected
                                        ? Curves.elasticOut
                                        : Curves.easeOut,
                                    builder: (context, scale, child) {
                                      return Transform.scale(
                                        scale: scale,
                                        child: Icon(
                                          item.icon,
                                          size: 24,
                                          color: isSelected
                                              ? theme.colorScheme.onPrimary
                                              : theme
                                                    .colorScheme
                                                    .onSurfaceVariant,
                                        ),
                                      );
                                    },
                                  ),
                                ),
                              ),
                            ),
                          ),
                        );
                      }),
                    ),
                  ],
                );
              },
            ),
          ),
        ),
      ),
    );
  }
}
