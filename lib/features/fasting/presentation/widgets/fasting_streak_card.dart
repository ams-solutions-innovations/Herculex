import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:herculex/features/fasting/presentation/fasting_providers.dart';
import 'package:herculex/theme/tokens/tokens.dart';

/// A prominent streak card displaying the user's intermittent fasting streak.
class FastingStreakCard extends ConsumerWidget {
  const FastingStreakCard({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final hx = context.hx;
    final streakAsync = ref.watch(fastingStreakProvider);
    final streak = streakAsync.valueOrNull ?? 0;
    final hasStreak = streak > 0;

    final flameColor = hasStreak ? hx.warning : hx.secondary;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        gradient: hasStreak
            ? LinearGradient(
                colors: [
                  hx.warning.withValues(alpha: hx.isDark ? 0.18 : 0.12),
                  hx.surfaceContainerLowest,
                ],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              )
            : null,
        color: hasStreak ? null : hx.surfaceContainerLowest,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: hasStreak
              ? hx.warning.withValues(alpha: 0.35)
              : hx.outlineVariant.withValues(alpha: 0.3),
        ),
      ),
      child: Row(
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: flameColor.withValues(alpha: hasStreak ? 0.18 : 0.10),
              shape: BoxShape.circle,
            ),
            child: Icon(
              Icons.local_fire_department_rounded,
              color: flameColor,
              size: 24,
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text(
                      "INTERMITTENT FASTING STREAK",
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: hasStreak ? hx.warning : hx.secondary,
                        fontWeight: FontWeight.bold,
                        letterSpacing: 0.8,
                        fontSize: 10,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 2),
                Text(
                  streakAsync.when(
                    data: (s) => "$s ${s == 1 ? 'day' : 'days'}",
                    loading: () => "...",
                    error: (_, _) => "0 days",
                  ),
                  style: theme.textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.bold,
                    fontSize: 20,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  hasStreak
                      ? "Great consistency! Keep the momentum going."
                      : "Start a fast today to build your streak.",
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: hx.secondary,
                    fontSize: 11,
                  ),
                ),
              ],
            ),
          ),
          if (hasStreak)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
              decoration: BoxDecoration(
                color: hx.warning.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.bolt_rounded, size: 14, color: hx.warning),
                  const SizedBox(width: 2),
                  Text(
                    "Active",
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
                      color: hx.warning,
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}
