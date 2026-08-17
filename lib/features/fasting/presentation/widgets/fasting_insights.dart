import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../theme/tokens/tokens.dart';
import '../../../../ui/ui.dart';
import '../fasting_providers.dart';

/// Streak + average eating window — the two headline fasting stats.
class FastingInsights extends ConsumerWidget {
  const FastingInsights({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final hx = context.hx;
    final streakAsync = ref.watch(fastingStreakProvider);
    final avgEatingAsync = ref.watch(fastingAverageEatingWindowProvider);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Center(
          child: Text(
            "FASTING INSIGHTS",
            textAlign: TextAlign.center,
            style: theme.textTheme.labelSmall
                ?.copyWith(color: hx.secondary, letterSpacing: 1.0),
          ),
        ),
        const SizedBox(height: 16),
        Row(
          children: [
            Expanded(
              child: _metricCard(
                context,
                title: "Current Streak",
                value: streakAsync.when(
                  data: (s) => "$s ${s == 1 ? 'day' : 'days'}",
                  loading: () => "...",
                  error: (e, s) => "0",
                ),
                icon: Icons.local_fire_department,
                accent: hx.warning,
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: _metricCard(
                context,
                title: "Avg. Window",
                value: avgEatingAsync.when(
                  data: (hrs) => "${hrs.toStringAsFixed(1)} hrs",
                  loading: () => "...",
                  error: (e, s) => "8.0 hrs",
                ),
                icon: Icons.restaurant,
                accent: hx.domainNutrition,
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _metricCard(
    BuildContext context, {
    required String title,
    required String value,
    required IconData icon,
    required Color accent,
  }) {
    final theme = Theme.of(context);
    final hx = context.hx;
    return HxGlass(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(title, style: theme.textTheme.bodySmall?.copyWith(color: hx.secondary)),
              Icon(icon, size: 18, color: accent),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            value,
            style: theme.textTheme.headlineMedium?.copyWith(fontSize: 22),
          ),
        ],
      ),
    );
  }
}
