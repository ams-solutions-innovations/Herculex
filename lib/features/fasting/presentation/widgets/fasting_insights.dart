import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:herculex/features/fasting/presentation/fasting_providers.dart';
import 'package:herculex/theme/tokens/tokens.dart';
import 'package:herculex/ui/ui.dart';

/// Streak + average eating window — the two headline fasting stats.
class FastingInsights extends ConsumerWidget {
  const FastingInsights({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final hx = context.hx;
    final streakAsync = ref.watch(fastingStreakProvider);
    final avgEatingAsync = ref.watch(fastingAverageEatingWindowProvider);

    return Row(
      children: [
        Expanded(
          child: _metricCard(
            context,
            title: "Current Streak",
            value: streakAsync.when(
              data: (s) => "$s ${s == 1 ? 'day' : 'days'}",
              loading: () => "...",
              error: (e, s) => "0 days",
            ),
            icon: Icons.local_fire_department_rounded,
            accent: hx.warning,
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: _metricCard(
            context,
            title: "Avg. Fasting Window",
            value: avgEatingAsync.when(
              data: (hrs) => "${(24.0 - hrs).clamp(0.0, 24.0).toStringAsFixed(1)} hrs",
              loading: () => "...",
              error: (e, s) => "16.0 hrs",
            ),
            icon: Icons.timelapse_rounded,
            accent: hx.domainFasting,
          ),
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
    return HxCard(
      accent: accent,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                title,
                style: theme.textTheme.bodySmall?.copyWith(color: hx.secondary),
              ),
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
