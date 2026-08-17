import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../theme/colors.dart';
import '../../../shell/main_scaffold.dart';
import '../dashboard_providers.dart';
import 'dashboard_shared.dart';
/// Calories left today (§18): `Goal - Food + Exercise`. Tapping opens the
/// nutrition tab.
class RemainingCaloriesCard extends ConsumerWidget {
  const RemainingCaloriesCard({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final r = ref.watch(remainingCaloriesProvider);

    if (r == null) {
      return DashboardPill(
        child: Row(
          children: [
            Expanded(child: dashboardTitle(context, 'Remaining')),
            Text('Set a goal',
                style: theme.textTheme.bodyMedium
                    ?.copyWith(color: AppColors.secondary)),
          ],
        ),
      );
    }

    final color = r.isOver ? Colors.redAccent : AppColors.macroKcal;
    return DashboardPill(
      padding: const EdgeInsets.fromLTRB(24, 18, 24, 20),
      onTap: () => ref.read(mainTabIndexProvider.notifier).state = 1,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Expanded(
                  child: dashboardTitle(
                      context, r.isOver ? 'Over budget' : 'Calories Remaining')),
              Text('${r.remaining.abs()}',
                  style: theme.textTheme.headlineSmall
                      ?.copyWith(fontWeight: FontWeight.bold, color: color)),
              const SizedBox(width: 4),
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text('kcal',
                    style: theme.textTheme.bodySmall
                        ?.copyWith(color: AppColors.secondary)),
              ),
            ],
          ),
          const SizedBox(height: 12),
          ClipRRect(
            borderRadius: BorderRadius.circular(999),
            child: LinearProgressIndicator(
              value: r.consumedFraction,
              minHeight: 6,
              backgroundColor: AppColors.surfaceVariant,
              valueColor: AlwaysStoppedAnimation<Color>(color),
            ),
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              _term(theme, 'Goal', r.goal, AppColors.secondary),
              _op(theme, '−'),
              _term(theme, 'Food', r.food, AppColors.macroProtein),
              _op(theme, '+'),
              _term(theme, 'Exercise', r.exercise, AppColors.brightness == Brightness.dark ? const Color(0xFF30D158) : const Color(0xFF34C759)),
            ],
          ),
        ],
      ),
    );
  }

  Widget _term(ThemeData theme, String label, int value, Color color) =>
      Expanded(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Text(label.toUpperCase(),
                style: theme.textTheme.labelSmall?.copyWith(
                    color: AppColors.secondary,
                    fontSize: 9,
                    letterSpacing: 0.8)),
            Text('$value',
                style: theme.textTheme.titleSmall
                    ?.copyWith(fontWeight: FontWeight.bold, color: color)),
          ],
        ),
      );

  Widget _op(ThemeData theme, String symbol) => Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Text(
            ' ',
            style: theme.textTheme.labelSmall?.copyWith(
              fontSize: 9,
              letterSpacing: 0.8,
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4),
            child: Text(
              symbol,
              style: theme.textTheme.titleSmall?.copyWith(
                color: AppColors.secondary,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ],
      );
}
